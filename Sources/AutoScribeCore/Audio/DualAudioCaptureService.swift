import Foundation

public final class DualAudioCaptureService: @unchecked Sendable {
    private let microphoneRecorder: MicrophoneRecorder
    private var systemAudioRecorders: [SystemAudioRecording] = []
    private var activeSystemAudioRecorder: SystemAudioRecording?
    private var currentSession: RecordingSession?
    private var currentFiles: [CapturedAudioFile] = []

    public var onAudioLevel: ((AudioSource, Float) -> Void)? {
        didSet {
            installAudioLevelHandlers()
        }
    }

    public func setOnAudioLevel(_ handler: ((AudioSource, Float) -> Void)?) {
        onAudioLevel = handler
    }

    public init(microphoneRecorder: MicrophoneRecorder = MicrophoneRecorder()) {
        self.microphoneRecorder = microphoneRecorder
        self.systemAudioRecorders = SystemAudioRecorderFactory.makePreferredRecorders()
        installAudioLevelHandlers()
    }

    public func start(session: RecordingSession) async throws -> [String] {
        guard currentSession == nil else {
            throw AudioCaptureError.alreadyRecording
        }

        try FileManager.default.createDirectory(at: session.temporaryDirectory, withIntermediateDirectories: true)

        var files: [CapturedAudioFile] = []
        var warnings: [String] = []
        currentSession = session

        do {
            let route = AudioRouteInspector.currentRoute()
            warnings.append("Active audio route: \(route.description)")
            if route.usesBluetoothInput || route.usesBluetoothOutput {
                warnings.append("Bluetooth audio route detected. Using Core Audio Tap for system audio.")
            }

            let microphoneURL = try await microphoneRecorder.start(in: session.temporaryDirectory)
            files.append(CapturedAudioFile(source: .microphone, url: microphoneURL))
            currentFiles = files

            guard await microphoneRecorder.waitForFirstBuffer(timeoutSeconds: 2) else {
                throw AudioCaptureError.captureStartupTimedOut(
                    "Microphone capture did not produce a writable audio buffer within 2 seconds. Check the selected input device or AirPods route."
                )
            }
            warnings.append("Microphone capture started.")

            for recorder in systemAudioRecorders {
                do {
                    warnings.append("Starting system audio backend \(recorder.backendName) for route: \(route.description)")
                    let systemURL = try await recorder.start(in: session.temporaryDirectory)
                    files.append(CapturedAudioFile(source: .systemAudio, url: systemURL))
                    activeSystemAudioRecorder = recorder
                    warnings.append("System audio capture started with \(recorder.backendName).")
                    break
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    warnings.append("System audio backend \(recorder.backendName) unavailable: \(message)")
                }
            }

            if activeSystemAudioRecorder == nil {
                warnings.append("System audio capture unavailable: all configured backends failed. Microphone recording continued.")
            }

            currentFiles = files
            return warnings
        } catch {
            _ = try? microphoneRecorder.stop()
            if let recorder = activeSystemAudioRecorder {
                _ = try? await recorder.stop()
            }
            currentSession = nil
            currentFiles = []
            activeSystemAudioRecorder = nil
            throw error
        }
    }

    private func installAudioLevelHandlers() {
        microphoneRecorder.onAudioLevel = { [weak self] level in
            self?.onAudioLevel?(.microphone, level)
        }

        for recorder in systemAudioRecorders {
            recorder.onAudioLevel = { [weak self] level in
                self?.onAudioLevel?(.systemAudio, level)
            }
        }
    }

    public func stop() async throws -> AudioCaptureResult {
        guard let session = currentSession else {
            throw AudioCaptureError.notRecording
        }

        var files: [CapturedAudioFile] = []
        var diagnostics: [String] = []
        let microphoneURL = try microphoneRecorder.stop()
        files.append(CapturedAudioFile(source: .microphone, url: microphoneURL))

        if currentFiles.contains(where: { $0.source == .systemAudio }),
           let recorder = activeSystemAudioRecorder {
            let systemURL = try await recorder.stop()
            files.append(CapturedAudioFile(source: .systemAudio, url: systemURL))
            if let summary = recorder.diagnosticSummary {
                diagnostics.append(summary)
            }
        }

        var finishedSession = session.finished
        finishedSession.audioSources = Set(files.map(\.source))
        currentSession = nil
        currentFiles = []
        activeSystemAudioRecorder = nil
        return AudioCaptureResult(session: finishedSession, files: files, diagnostics: diagnostics)
    }
}
