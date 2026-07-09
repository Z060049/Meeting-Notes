import Foundation
import WhisperKit

/// Shared download/load state for a locally-stored model.
public enum ModelDownloadState: Sendable, Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case loading
    case ready
    case failed(String)

    public var isReady: Bool { self == .ready }

    public var progressValue: Double? {
        if case .downloading(let p) = self { return p }
        return nil
    }
}

/// Wraps WhisperKit for on-device speech-to-text transcription.
///
/// Model download and loading happen explicitly via `prepareModel(_:)` before
/// any call to `transcribe(files:modelSize:)`.
public final class WhisperKitTranscriptionService: ObservableObject, @unchecked Sendable {
    @Published public private(set) var downloadState: ModelDownloadState = .notDownloaded

    private var pipeline: WhisperKit?
    private var loadedSize: WhisperModelSize?

    public init() {}

    // MARK: - Model management

    /// Downloads and loads the requested Whisper model, if not already loaded.
    public func prepareModel(_ size: WhisperModelSize) async throws {
        if loadedSize == size, pipeline != nil {
            await setDownloadState(.ready)
            return
        }

        await setDownloadState(.downloading(progress: 0.0))

        do {
            // WhisperKit downloads the model to its CoreML cache on first use.
            // Subsequent calls load from disk without re-downloading.
            await setDownloadState(.loading)
            let pipe = try await WhisperKit(
                model: size.modelIdentifier,
                verbose: false,
                logLevel: .none,
                prewarm: true,
                load: true,
                download: true
            )
            pipeline = pipe
            loadedSize = size
            await setDownloadState(.ready)
        } catch {
            let message = "Could not load Whisper model '\(size.rawValue)': \(error.localizedDescription)"
            await setDownloadState(.failed(message))
            throw ProcessingProviderError.localModelNotReady(message)
        }
    }

    /// Returns whether a given model size is currently loaded and ready.
    public var isReady: Bool { downloadState == .ready && pipeline != nil }

    // MARK: - Transcription

    /// Transcribes all eligible audio files from a recording session.
    public func transcribe(
        files: [CapturedAudioFile],
        modelSize: WhisperModelSize
    ) async throws -> Transcript {
        guard let pipeline, loadedSize == modelSize else {
            throw ProcessingProviderError.localModelNotReady(
                "Whisper model '\(modelSize.displayName)' is not loaded. Prepare it first."
            )
        }

        var segments: [TranscriptSegment] = []

        for file in files {
            guard AudioTranscriptionPolicy.decision(for: file).shouldTranscribe else { continue }
            guard let uploadURL = try? AudioLevelAnalyzer.trimmedSilence(url: file.url) else { continue }
            defer {
                if uploadURL != file.url {
                    try? FileManager.default.removeItem(at: uploadURL)
                }
            }

            do {
                let options = DecodingOptions(temperature: 0.0, usePrefillPrompt: true)
                let results = try await pipeline.transcribe(
                    audioPath: uploadURL.path,
                    decodeOptions: options
                )
                let text = results
                    .map(\.text)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !text.isEmpty {
                    segments.append(TranscriptSegment(speaker: file.source.rawValue, text: text))
                }
            } catch {
                // Log and continue — a failed file should not abort the whole session.
                segments.append(TranscriptSegment(
                    speaker: file.source.rawValue,
                    text: "[Transcription error: \(error.localizedDescription)]"
                ))
            }
        }

        return Transcript(segments: segments)
    }

    // MARK: - Private

    @MainActor
    private func setDownloadState(_ state: ModelDownloadState) {
        downloadState = state
    }
}
