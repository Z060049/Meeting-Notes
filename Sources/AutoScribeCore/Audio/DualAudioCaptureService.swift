import Foundation

public final class DualAudioCaptureService: @unchecked Sendable {
    private let microphoneRecorder: MicrophoneRecorder
    private var systemAudioRecorders: [SystemAudioRecording] = []
    private var activeSystemAudioRecorder: SystemAudioRecording?
    private var currentSession: RecordingSession?
    private var currentFiles: [CapturedAudioFile] = []

    public var onAudioLevel: ((AudioSource, Float) -> Void)? {
        didSet {
            microphoneRecorder.onAudioLevel = { [weak self] level in
                self?.onAudioLevel?(.microphone, level)
            }

            for recorder in systemAudioRecorders {
                recorder.onAudioLevel = { [weak self] level in
                    self?.onAudioLevel?(.systemAudio, level)
                }
            }
        }
    }

    public func setOnAudioLevel(_ handler: ((AudioSource, Float) -> Void)?) {
        onAudioLevel = handler
    }

    public init(microphoneRecorder: MicrophoneRecorder = MicrophoneRecorder()) {
        self.microphoneRecorder = microphoneRecorder
        self.systemAudioRecorders = SystemAudioRecorderFactory.makePreferredRecorders()
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
            let microphoneURL = try await microphoneRecorder.start(in: session.temporaryDirectory)
            files.append(CapturedAudioFile(source: .microphone, url: microphoneURL))
            currentFiles = files

            for recorder in systemAudioRecorders {
                do {
                    warnings.append("System audio backend: \(recorder.backendName)")
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
                warnings.append("System audio capture unavailable: all configured backends failed.")
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

    public func stop() async throws -> AudioCaptureResult {
        guard let session = currentSession else {
            throw AudioCaptureError.notRecording
        }

        var files: [CapturedAudioFile] = []
        let microphoneURL = try microphoneRecorder.stop()
        files.append(CapturedAudioFile(source: .microphone, url: microphoneURL))

        if currentFiles.contains(where: { $0.source == .systemAudio }),
           let recorder = activeSystemAudioRecorder {
            let systemURL = try await recorder.stop()
            files.append(CapturedAudioFile(source: .systemAudio, url: systemURL))
        }

        var finishedSession = session.finished
        finishedSession.audioSources = Set(files.map(\.source))
        currentSession = nil
        currentFiles = []
        activeSystemAudioRecorder = nil
        return AudioCaptureResult(session: finishedSession, files: files)
    }
}
