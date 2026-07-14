import MeetingNotesCore
import XCTest

final class MarkdownExporterTests: XCTestCase {
    func testRenderIncludesMetadataSummaryAndTranscript() {
        let session = RecordingSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_600),
            audioSources: [.microphone, .systemAudio],
            processingMode: .api,
            outputDirectory: URL(fileURLWithPath: "/tmp/meetingnotes"),
            temporaryDirectory: URL(fileURLWithPath: "/tmp/meetingnotes-temp")
        )

        let result = ProcessingResult(
            transcript: Transcript(segments: [
                TranscriptSegment(speaker: "Microphone", startTime: 0, text: "Hello"),
                TranscriptSegment(speaker: "System Audio", startTime: 2, text: "Hi there")
            ]),
            summary: MeetingSummary(
                title: "Weekly Sync",
                keyPoints: ["Discussed launch plan"],
                decisions: ["Ship the MVP first"],
                actionItems: ["Draft release checklist"],
                followUps: ["Confirm API costs"]
            )
        )

        let document = MarkdownExporter().render(result: result, session: session)

        XCTAssertTrue(document.filename.hasSuffix("_weekly-sync.md"))
        XCTAssertTrue(document.contents.contains("processing_mode: API"))
        XCTAssertTrue(document.contents.contains("audio_sources: Microphone, System Audio"))
        XCTAssertTrue(document.contents.contains("- Discussed launch plan"))
        XCTAssertTrue(document.contents.contains("### Microphone"))
        XCTAssertTrue(document.contents.contains("[00:00] Hello"))
        XCTAssertTrue(document.contents.contains("### System Audio"))
        XCTAssertTrue(document.contents.contains("[00:02] Hi there"))
    }

    func testRenderUsesEmptySectionFallbacks() {
        let session = RecordingSession(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_030),
            audioSources: [.microphone],
            processingMode: .api,
            outputDirectory: URL(fileURLWithPath: "/tmp/meetingnotes"),
            temporaryDirectory: URL(fileURLWithPath: "/tmp/meetingnotes-temp")
        )

        let result = ProcessingResult(
            transcript: Transcript(segments: [
                TranscriptSegment(speaker: "Microphone", text: "Short test")
            ]),
            summary: MeetingSummary(
                title: "Short Test",
                keyPoints: [],
                decisions: [],
                actionItems: [],
                followUps: []
            )
        )

        let document = MarkdownExporter().render(result: result, session: session)

        XCTAssertTrue(document.contents.contains("- No key points identified."))
        XCTAssertTrue(document.contents.contains("- No decisions identified."))
        XCTAssertTrue(document.contents.contains("- No action items identified."))
        XCTAssertTrue(document.contents.contains("- No follow-ups identified."))
    }

    func testRenderSanitizesFilenameTitle() {
        let session = RecordingSession(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_030),
            outputDirectory: URL(fileURLWithPath: "/tmp/meetingnotes"),
            temporaryDirectory: URL(fileURLWithPath: "/tmp/meetingnotes-temp")
        )

        let result = ProcessingResult(
            transcript: Transcript(segments: []),
            summary: MeetingSummary(
                title: "Weekly Sync: Q&A",
                keyPoints: [],
                decisions: [],
                actionItems: [],
                followUps: []
            )
        )

        let document = MarkdownExporter().render(result: result, session: session)

        XCTAssertTrue(document.filename.hasSuffix("_weekly-sync--q-a.md"))
    }

    func testRenderShowsNotCapturedForMissingSystemAudio() {
        let session = RecordingSession(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_030),
            audioSources: [.microphone],
            processingMode: .api,
            outputDirectory: URL(fileURLWithPath: "/tmp/meetingnotes"),
            temporaryDirectory: URL(fileURLWithPath: "/tmp/meetingnotes-temp")
        )

        let result = ProcessingResult(
            transcript: Transcript(segments: [
                TranscriptSegment(speaker: "Microphone", text: "Only the microphone was captured.")
            ]),
            summary: MeetingSummary(
                title: "Mic Only",
                keyPoints: [],
                decisions: [],
                actionItems: [],
                followUps: []
            )
        )

        let document = MarkdownExporter().render(result: result, session: session)

        XCTAssertTrue(document.contents.contains("### Microphone"))
        XCTAssertTrue(document.contents.contains("Only the microphone was captured."))
        XCTAssertTrue(document.contents.contains("### System Audio"))
        XCTAssertTrue(document.contents.contains("Not captured for this recording."))
    }
}
