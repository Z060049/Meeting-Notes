import MeetingNotesCore
import XCTest

final class SystemAudioRecorderFactoryTests: XCTestCase {
    func testCoreAudioTapIsPreferredBeforeScreenCaptureKit() {
        let names = SystemAudioRecorderFactory.preferredBackendNames

        if #available(macOS 14.2, *) {
            XCTAssertEqual(names.first, SystemAudioBackend.coreAudioTap.rawValue)
            XCTAssertEqual(
                names,
                [SystemAudioBackend.coreAudioTap.rawValue, SystemAudioBackend.screenCaptureKit.rawValue]
            )
        } else if #available(macOS 13.0, *) {
            XCTAssertEqual(names, [SystemAudioBackend.screenCaptureKit.rawValue])
        } else {
            XCTAssertTrue(names.isEmpty)
        }
    }
}
