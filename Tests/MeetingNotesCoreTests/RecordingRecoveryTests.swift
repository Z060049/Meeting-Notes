import MeetingNotesCore
import XCTest

final class RecordingRecoveryTests: XCTestCase {
    func testRecordingWorkspaceUsesStableApplicationSupportDirectory() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!

        let workspace = FileManager.default.meetingNotesRecordingWorkspace(for: id)

        XCTAssertTrue(workspace.path.contains("Library/Application Support/MeetingNotes/Recording Recovery"))
        XCTAssertEqual(workspace.lastPathComponent, id.uuidString)
    }
}
