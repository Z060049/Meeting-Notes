import MeetingNotesCore
import XCTest

final class EnvironmentConfigurationTests: XCTestCase {
    func testParsesSimpleAssignment() {
        let contents = "OPENAI_API_KEY=sk-test-123"
        XCTAssertEqual(
            EnvironmentConfiguration.value(forKey: "OPENAI_API_KEY", inEnvFileContents: contents),
            "sk-test-123"
        )
    }

    func testIgnoresCommentsAndBlankLinesAndOtherKeys() {
        let contents = """
        # comment line
        OTHER_KEY=ignored

        OPENAI_API_KEY=sk-real-key
        """
        XCTAssertEqual(
            EnvironmentConfiguration.value(forKey: "OPENAI_API_KEY", inEnvFileContents: contents),
            "sk-real-key"
        )
    }

    func testStripsSurroundingQuotesAndExportPrefix() {
        let contents = "export OPENAI_API_KEY = \"sk-quoted-key\""
        XCTAssertEqual(
            EnvironmentConfiguration.value(forKey: "OPENAI_API_KEY", inEnvFileContents: contents),
            "sk-quoted-key"
        )
    }

    func testReturnsNilWhenKeyMissingOrEmpty() {
        XCTAssertNil(EnvironmentConfiguration.value(forKey: "OPENAI_API_KEY", inEnvFileContents: "NOPE=1"))
        XCTAssertNil(EnvironmentConfiguration.value(forKey: "OPENAI_API_KEY", inEnvFileContents: "OPENAI_API_KEY="))
    }
}
