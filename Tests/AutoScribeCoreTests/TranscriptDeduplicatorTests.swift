import AutoScribeCore
import XCTest

final class TranscriptDeduplicatorTests: XCTestCase {
    private func micText(in transcript: Transcript) -> String? {
        transcript.segments.first { $0.speaker == AudioSource.microphone.rawValue }?.text
    }

    func testRemovesNearIdenticalMicrophoneSentence() {
        let transcript = Transcript(segments: [
            TranscriptSegment(
                speaker: AudioSource.microphone.rawValue,
                text: "Let's talk about the roadmap. The idea is good, we can make it go viral."
            ),
            TranscriptSegment(
                speaker: AudioSource.systemAudio.rawValue,
                text: "The idea is good, we can make it go viral!"
            )
        ])

        let result = TranscriptDeduplicator.deduplicate(transcript)

        let mic = micText(in: result)
        XCTAssertNotNil(mic)
        XCTAssertTrue(mic!.contains("Let's talk about the roadmap"))
        XCTAssertFalse(mic!.lowercased().contains("go viral"))
    }

    func testKeepsDistinctMicrophoneSentences() {
        let transcript = Transcript(segments: [
            TranscriptSegment(
                speaker: AudioSource.microphone.rawValue,
                text: "What do you think about the budget? I have my own opinion here."
            ),
            TranscriptSegment(
                speaker: AudioSource.systemAudio.rawValue,
                text: "The weather today is completely unrelated to anything."
            )
        ])

        let result = TranscriptDeduplicator.deduplicate(transcript)

        let mic = micText(in: result)
        XCTAssertEqual(mic, "What do you think about the budget? I have my own opinion here.")
    }

    func testMicrophoneOnlyTranscriptIsUnchanged() {
        let transcript = Transcript(segments: [
            TranscriptSegment(
                speaker: AudioSource.microphone.rawValue,
                text: "This is the only stream we captured today."
            )
        ])

        let result = TranscriptDeduplicator.deduplicate(transcript)

        XCTAssertEqual(result, transcript)
    }

    func testFullyDuplicatedMicrophoneSegmentIsDropped() {
        let transcript = Transcript(segments: [
            TranscriptSegment(
                speaker: AudioSource.microphone.rawValue,
                text: "Go viral if the idea is good. Just add story and a twist."
            ),
            TranscriptSegment(
                speaker: AudioSource.systemAudio.rawValue,
                text: "Go viral if the idea is good. Just add story and a twist."
            )
        ])

        let result = TranscriptDeduplicator.deduplicate(transcript)

        XCTAssertNil(micText(in: result))
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments.first?.speaker, AudioSource.systemAudio.rawValue)
    }
}
