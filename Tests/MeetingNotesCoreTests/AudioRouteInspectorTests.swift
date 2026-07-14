import MeetingNotesCore
import CoreAudio
import XCTest

final class AudioRouteInspectorTests: XCTestCase {
    func testBluetoothRouteUsesTransportTypeForClassification() {
        let route = AudioRouteInspector.Route(
            input: AudioRouteInspector.Device(id: 1, name: "External Microphone", transportType: kAudioDeviceTransportTypeBluetooth),
            output: AudioRouteInspector.Device(id: 2, name: "MacBook Pro Speakers", transportType: kAudioDeviceTransportTypeBuiltIn)
        )

        XCTAssertTrue(route.usesBluetoothInput)
        XCTAssertFalse(route.usesBluetoothOutput)
        XCTAssertTrue(route.containsTemporarilyUnsupportedBluetoothDevice)
    }

    func testAirPodsNameFallsBackToBluetoothClassification() {
        let route = AudioRouteInspector.Route(
            input: AudioRouteInspector.Device(id: 1, name: "AirPods Pro Microphone"),
            output: AudioRouteInspector.Device(id: 2, name: "MacBook Pro Speakers", transportType: kAudioDeviceTransportTypeBuiltIn)
        )

        XCTAssertTrue(route.usesBluetoothInput)
        XCTAssertFalse(route.usesBluetoothOutput)
    }

    func testBuiltInRouteIsNotBluetooth() {
        let route = AudioRouteInspector.Route(
            input: AudioRouteInspector.Device(id: 1, name: "MacBook Pro Microphone", transportType: kAudioDeviceTransportTypeBuiltIn),
            output: AudioRouteInspector.Device(id: 2, name: "MacBook Pro Speakers", transportType: kAudioDeviceTransportTypeBuiltIn)
        )

        XCTAssertFalse(route.usesBluetoothInput)
        XCTAssertFalse(route.usesBluetoothOutput)
        XCTAssertFalse(route.containsTemporarilyUnsupportedBluetoothDevice)
    }
}
