import Foundation

public enum AudioTranscriptionPolicy {
    public static let minimumSystemAudioBytes = 16_384

    public struct Decision: Equatable, Sendable {
        public let shouldTranscribe: Bool
        public let reason: String
        public let fileSizeBytes: Int?

        public init(shouldTranscribe: Bool, reason: String, fileSizeBytes: Int?) {
            self.shouldTranscribe = shouldTranscribe
            self.reason = reason
            self.fileSizeBytes = fileSizeBytes
        }
    }

    public static func contentType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "wav":
            "audio/wav"
        case "m4a":
            "audio/mp4"
        case "mp3", "mpeg", "mpga":
            "audio/mpeg"
        case "ogg", "oga":
            "audio/ogg"
        case "flac":
            "audio/flac"
        case "webm":
            "audio/webm"
        default:
            "application/octet-stream"
        }
    }

    public static func decision(for file: CapturedAudioFile) -> Decision {
        let fileSize = fileSizeBytes(for: file.url)

        guard file.source == .systemAudio else {
            return Decision(
                shouldTranscribe: true,
                reason: "microphone streams are always sent to transcription",
                fileSizeBytes: fileSize
            )
        }

        guard let fileSize else {
            return Decision(
                shouldTranscribe: false,
                reason: "system-audio file size could not be read",
                fileSizeBytes: nil
            )
        }

        guard fileSize >= minimumSystemAudioBytes else {
            return Decision(
                shouldTranscribe: false,
                reason: "system-audio file is below \(minimumSystemAudioBytes) byte silence threshold",
                fileSizeBytes: fileSize
            )
        }

        return Decision(
            shouldTranscribe: true,
            reason: "system-audio file is above silence threshold",
            fileSizeBytes: fileSize
        )
    }

    public static func fileSizeBytes(for url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }
}
