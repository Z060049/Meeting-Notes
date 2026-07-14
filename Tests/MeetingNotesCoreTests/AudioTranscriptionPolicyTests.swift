import MeetingNotesCore
import XCTest

final class AudioTranscriptionPolicyTests: XCTestCase {
    func testContentTypesForSupportedAudioExtensions() {
        XCTAssertEqual(AudioTranscriptionPolicy.contentType(for: URL(fileURLWithPath: "/tmp/mic.wav")), "audio/wav")
        XCTAssertEqual(AudioTranscriptionPolicy.contentType(for: URL(fileURLWithPath: "/tmp/system-audio.wav")), "audio/wav")
        XCTAssertEqual(AudioTranscriptionPolicy.contentType(for: URL(fileURLWithPath: "/tmp/system.m4a")), "audio/mp4")
        XCTAssertEqual(AudioTranscriptionPolicy.contentType(for: URL(fileURLWithPath: "/tmp/audio.mp3")), "audio/mpeg")
        XCTAssertEqual(AudioTranscriptionPolicy.contentType(for: URL(fileURLWithPath: "/tmp/audio.flac")), "audio/flac")
    }

    func testMicrophoneFilesAreAlwaysTranscribed() throws {
        let url = try makeTempFile(byteCount: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let decision = AudioTranscriptionPolicy.decision(
            for: CapturedAudioFile(source: .microphone, url: url)
        )

        XCTAssertTrue(decision.shouldTranscribe)
        XCTAssertEqual(decision.fileSizeBytes, 1)
    }

    func testTinySystemAudioFilesAreSkipped() throws {
        let url = try makeTempFile(byteCount: AudioTranscriptionPolicy.minimumSystemAudioBytes - 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let decision = AudioTranscriptionPolicy.decision(
            for: CapturedAudioFile(source: .systemAudio, url: url)
        )

        XCTAssertFalse(decision.shouldTranscribe)
        XCTAssertEqual(decision.fileSizeBytes, AudioTranscriptionPolicy.minimumSystemAudioBytes - 1)
        XCTAssertTrue(decision.reason.contains("below"))
    }

    func testMeaningfulSystemAudioFilesAreTranscribed() throws {
        let url = try makeTempFile(byteCount: AudioTranscriptionPolicy.minimumSystemAudioBytes)
        defer { try? FileManager.default.removeItem(at: url) }

        let decision = AudioTranscriptionPolicy.decision(
            for: CapturedAudioFile(source: .systemAudio, url: url)
        )

        XCTAssertTrue(decision.shouldTranscribe)
        XCTAssertEqual(decision.fileSizeBytes, AudioTranscriptionPolicy.minimumSystemAudioBytes)
        XCTAssertTrue(decision.reason.contains("above"))
    }

    private func makeTempFile(byteCount: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingNotesPolicyTests-\(UUID().uuidString)")

        let data = Data(repeating: 0, count: byteCount)
        try data.write(to: url)
        return url
    }
}
