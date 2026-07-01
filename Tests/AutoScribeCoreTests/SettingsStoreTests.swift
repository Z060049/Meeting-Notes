import AutoScribeCore
import XCTest

final class SettingsStoreTests: XCTestCase {
    func testDefaultSettingsMatchMVPValidationDefaults() {
        let settings = AppSettings()

        XCTAssertEqual(settings.processingMode, .api)
        XCTAssertEqual(settings.outputDirectory.path, FileManager.default.defaultAutoScribeOutputDirectory.path)
        XCTAssertEqual(settings.inactivityTimeoutSeconds, 180)
        XCTAssertEqual(settings.summaryDepth, .standard)
        XCTAssertTrue(settings.shouldShowConsentReminder)
        XCTAssertFalse(settings.hasAcceptedConsentChecklist)
    }

    func testSaveAndLoadSettings() {
        let suiteName = "AutoScribeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        let expected = AppSettings(
            processingMode: .api,
            outputDirectory: URL(fileURLWithPath: "/tmp/autoscribe-output", isDirectory: true),
            inactivityTimeoutSeconds: 120,
            summaryDepth: .detailed,
            shouldShowConsentReminder: false,
            hasAcceptedConsentChecklist: true
        )

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }
}
