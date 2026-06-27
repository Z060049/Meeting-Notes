import AutoScribeCore
import XCTest

final class SystemAudioRecorderFactoryTests: XCTestCase {
    func testPreferredBackendNamesIncludeAvailableBackendsInOrder() {
        let names = SystemAudioRecorderFactory.preferredBackendNames

        if #available(macOS 14.2, *) {
            XCTAssertEqual(names.first, SystemAudioBackend.coreAudioTap.rawValue)
            XCTAssertTrue(names.contains(SystemAudioBackend.screenCaptureKit.rawValue))
        } else if #available(macOS 13.0, *) {
            XCTAssertEqual(names, [SystemAudioBackend.screenCaptureKit.rawValue])
        } else {
            XCTAssertTrue(names.isEmpty)
        }
    }
}
