import AutoScribeCore
import CoreAudio
import XCTest

final class SystemAudioRecorderFactoryTests: XCTestCase {
    func testPreferredBackendNamesIncludeAvailableBackendsInOrder() {
        let route = AudioRouteInspector.Route(
            input: AudioRouteInspector.Device(id: 1, name: "MacBook Pro Microphone", transportType: kAudioDeviceTransportTypeBuiltIn),
            output: AudioRouteInspector.Device(id: 2, name: "MacBook Pro Speakers", transportType: kAudioDeviceTransportTypeBuiltIn)
        )
        let names = SystemAudioRecorderFactory.preferredBackendNames(route: route)

        if #available(macOS 14.2, *) {
            XCTAssertEqual(names.first, SystemAudioBackend.coreAudioTap.rawValue)
            XCTAssertTrue(names.contains(SystemAudioBackend.screenCaptureKit.rawValue))
        } else if #available(macOS 13.0, *) {
            XCTAssertEqual(names, [SystemAudioBackend.screenCaptureKit.rawValue])
        } else {
            XCTAssertTrue(names.isEmpty)
        }
    }

    func testBluetoothOutputPrefersScreenCaptureKitBeforeCoreAudioTap() {
        let route = AudioRouteInspector.Route(
            input: AudioRouteInspector.Device(id: 1, name: "AirPods Microphone", transportType: kAudioDeviceTransportTypeBluetooth),
            output: AudioRouteInspector.Device(id: 2, name: "AirPods", transportType: kAudioDeviceTransportTypeBluetooth)
        )
        let names = SystemAudioRecorderFactory.preferredBackendNames(route: route)

        if #available(macOS 14.2, *) {
            XCTAssertEqual(
                names,
                [SystemAudioBackend.screenCaptureKit.rawValue, SystemAudioBackend.coreAudioTap.rawValue]
            )
        } else if #available(macOS 13.0, *) {
            XCTAssertEqual(names, [SystemAudioBackend.screenCaptureKit.rawValue])
        } else {
            XCTAssertTrue(names.isEmpty)
        }
    }
}
