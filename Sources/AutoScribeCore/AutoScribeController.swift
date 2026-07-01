import Combine
import Foundation

public final class AutoScribeController: ObservableObject {
    @Published public private(set) var state: AppState = .idle
    @Published public private(set) var settings: AppSettings
    @Published public private(set) var lastError: String?
    @Published public private(set) var diagnostics: [DiagnosticEvent] = []
    @Published public private(set) var latestOutputURL: URL?

    public let silenceDetected = PassthroughSubject<Void, Never>()

    private let settingsStore: SettingsStore
    private let audioCaptureService: DualAudioCaptureService
    private let markdownExporter: MarkdownExporter
    private var processingProvider: ProcessingProvider
    private var inactivityMonitor: InactivityMonitor?
    private var isStartingRecording = false

    public init(
        settingsStore: SettingsStore = SettingsStore(),
        audioCaptureService: DualAudioCaptureService = DualAudioCaptureService(),
        markdownExporter: MarkdownExporter = MarkdownExporter(),
        processingProvider: ProcessingProvider? = nil
    ) {
        self.settingsStore = settingsStore
        self.audioCaptureService = audioCaptureService
        self.markdownExporter = markdownExporter
        self.settings = settingsStore.load()
        self.processingProvider = processingProvider ?? OpenAIProcessingProvider {
            EnvironmentConfiguration.openAIAPIKey()
        }
        Task { @MainActor in
            self.addDiagnostic("Controller initialized. Output folder: \(self.settings.outputDirectory.path)")
        }
    }

    @MainActor public func updateSettings(_ settings: AppSettings) {
        self.settings = settings
        settingsStore.save(settings)
        addDiagnostic("Settings saved. Timeout: \(Int(settings.inactivityTimeoutSeconds))s, output: \(settings.outputDirectory.path)")
    }

    @MainActor public func acceptConsentChecklist() {
        var updated = settings
        updated.hasAcceptedConsentChecklist = true
        updateSettings(updated)
        addDiagnostic("Consent checklist accepted.")
    }

    @MainActor public func toggleRecording() {
        if state.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    @MainActor public func startRecording() {
        addDiagnostic("Start recording requested.")
        guard !isStartingRecording else {
            addDiagnostic("Recording startup is already in progress.", level: .warning)
            return
        }

        guard settings.hasAcceptedConsentChecklist else {
            setState(.failed("Please accept the recording consent checklist before starting."))
            return
        }

        let session = RecordingSession(
            processingMode: settings.processingMode,
            outputDirectory: settings.outputDirectory
        )

        latestOutputURL = nil
        addDiagnostic("Recording session \(Self.shortSessionID(session.id)) started.")
        addDiagnostic("Recording output folder: \(settings.outputDirectory.path)")
        addDiagnostic("Recording mode: \(settings.processingMode.rawValue), silence prompt after: \(Int(settings.inactivityTimeoutSeconds))s")
        addDiagnostic("Audio capture startup in progress.")
        isStartingRecording = true
        lastError = nil

        Task {
            do {
                await configureInactivityMonitor()
                await MainActor.run {
                    self.addDiagnostic("Starting audio capture in \(session.temporaryDirectory.path)")
                }
                let warnings = try await audioCaptureService.start(session: session)
                await MainActor.run {
                    self.isStartingRecording = false
                    self.setState(.recording(session))
                    self.addDiagnostic("Audio capture started.")
                    for warning in warnings {
                        self.addDiagnostic(warning, level: .warning)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isStartingRecording = false
                    self.fail(error)
                }
            }
        }
    }

    @MainActor public func stopRecording() {
        addDiagnostic("Stop recording requested.")
        Task {
            do {
                let result = try await audioCaptureService.stop()
                inactivityMonitor?.stop()
                inactivityMonitor = nil
                addDiagnostic("Audio capture stopped. Files: \(result.files.map { $0.url.lastPathComponent }.joined(separator: ", "))")
                for diagnostic in result.diagnostics {
                    addDiagnostic(diagnostic)
                }
                for file in result.files {
                    addDiagnostic("\(file.source.rawValue) file size: \(Self.fileSizeDescription(for: file.url))")
                }
                await process(result)
            } catch {
                fail(error)
            }
        }
    }

    @MainActor private func process(_ capture: AudioCaptureResult) async {
        setState(.processing(capture.session))
        addDiagnostic("Processing session \(Self.shortSessionID(capture.session.id)).")
        addDiagnostic("Processing started with \(capture.files.count) audio file(s).")
        logTranscriptionDecisions(for: capture.files)

        do {
            let result = try await processingProvider.process(capture: capture, settings: settings)
            addDiagnostic("Processing complete. Exporting Markdown.")
            let outputURL = try markdownExporter.export(
                result: result,
                session: capture.session,
                to: settings.outputDirectory
            )
            cleanupTemporaryFiles(for: capture.session)
            latestOutputURL = outputURL
            setState(.complete(outputURL))
            addDiagnostic("Markdown saved to \(outputURL.path)")
            addDiagnostic("Validation output: duration \(Self.durationDescription(capture.session.duration)), path \(outputURL.path)")
        } catch {
            fail(error)
        }
    }

    @MainActor private func configureInactivityMonitor() async {
        let cutoff = settings.inactivityTimeoutSeconds
        let monitor = InactivityMonitor(timeout: cutoff) { [weak self] in
            Task { @MainActor in
                self?.addDiagnostic("No audio detected for \(Int(cutoff))s. Prompting to stop.", level: .warning)
                self?.silenceDetected.send()
            }
        }

        audioCaptureService.setOnAudioLevel { [weak monitor] _, level in
            monitor?.recordAudioLevel(level)
        }

        monitor.start()
        inactivityMonitor = monitor
        addDiagnostic("Silence monitor started (prompt after \(Int(cutoff))s).")
    }

    @MainActor public func keepRecordingAfterSilence() {
        inactivityMonitor?.restart()
        addDiagnostic("Continuing recording after silence prompt.")
    }

    private func cleanupTemporaryFiles(for session: RecordingSession) {
        do {
            try FileManager.default.removeItem(at: session.temporaryDirectory)
            Task { @MainActor in
                self.addDiagnostic("Temporary files cleaned up.")
            }
        } catch {
            Task { @MainActor in
                self.addDiagnostic("Temporary cleanup skipped: \(error.localizedDescription)", level: .warning)
            }
        }
    }

    @MainActor private func fail(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastError = message
        setState(.failed(message))
        addDiagnostic(message, level: .error)
        inactivityMonitor?.stop()
        inactivityMonitor = nil
    }

    @MainActor public func addDiagnostic(_ message: String, level: DiagnosticEvent.Level = .info) {
        diagnostics.append(DiagnosticEvent(level: level, message: message))
        if diagnostics.count > 100 {
            diagnostics.removeFirst(diagnostics.count - 100)
        }
    }

    @MainActor public func clearDiagnostics() {
        diagnostics.removeAll()
    }

    @MainActor public func validationReportText() -> String {
        let outputPath = latestOutputURL?.path ?? "None"
        let error = lastError ?? "None"
        let diagnosticsText = diagnostics.map(\.formatted).joined(separator: "\n")

        return """
        AutoScribe Validation Report
        Generated: \(Self.reportDateFormatter.string(from: Date()))
        State: \(state.title)
        Output folder: \(settings.outputDirectory.path)
        Latest output: \(outputPath)
        Processing mode: \(settings.processingMode.rawValue)
        Summary depth: \(settings.summaryDepth.rawValue)
        Silence prompt after: \(Int(settings.inactivityTimeoutSeconds))s
        Last error: \(error)

        Diagnostics:
        \(diagnosticsText)
        """
    }

    @MainActor private func setState(_ state: AppState) {
        self.state = state
        addDiagnostic("State changed to \(state.title).")
    }

    @MainActor private func logTranscriptionDecisions(for files: [CapturedAudioFile]) {
        for file in files {
            let decision = AudioTranscriptionPolicy.decision(for: file)
            let action = decision.shouldTranscribe ? "sent to transcription" : "skipped"
            let size = decision.fileSizeBytes.map { "\($0) bytes" } ?? "unknown size"
            addDiagnostic("\(file.source.rawValue) transcription \(action): \(decision.reason) (\(size))")
        }
    }

    private static func fileSizeDescription(for url: URL) -> String {
        guard let size = AudioTranscriptionPolicy.fileSizeBytes(for: url) else {
            return "unknown"
        }
        return "\(size) bytes"
    }

    private static func shortSessionID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private static func durationDescription(_ interval: TimeInterval) -> String {
        "\(Int(interval.rounded()))s"
    }

    private static let reportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
