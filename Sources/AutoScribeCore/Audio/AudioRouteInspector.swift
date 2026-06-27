import CoreAudio
import Foundation

public enum AudioRouteInspector {
    public struct Device: Equatable, Sendable {
        public let id: AudioDeviceID
        public let uid: String?
        public let name: String?
        public let transportType: UInt32?

        public init(
            id: AudioDeviceID,
            uid: String? = nil,
            name: String? = nil,
            transportType: UInt32? = nil
        ) {
            self.id = id
            self.uid = uid
            self.name = name
            self.transportType = transportType
        }

        public var usesBluetoothTransport: Bool {
            if transportType == kAudioDeviceTransportTypeBluetooth {
                return true
            }

            guard let name else {
                return false
            }

            let lowercased = name.lowercased()
            return lowercased.contains("airpods") || lowercased.contains("bluetooth")
        }

        public var diagnosticDescription: String {
            let name = name ?? "unknown"
            let uid = uid ?? "unknown"
            let transport = transportDescription(for: transportType)
            return "\(name) (uid: \(uid), transport: \(transport))"
        }

        private func transportDescription(for transportType: UInt32?) -> String {
            guard let transportType else {
                return "unknown"
            }

            switch transportType {
            case kAudioDeviceTransportTypeBuiltIn:
                return "built-in"
            case kAudioDeviceTransportTypeBluetooth:
                return "bluetooth"
            case kAudioDeviceTransportTypeUSB:
                return "usb"
            case kAudioDeviceTransportTypeAggregate:
                return "aggregate"
            default:
                return "\(transportType)"
            }
        }
    }

    public struct Route: Equatable, Sendable {
        public let input: Device?
        public let output: Device?

        public init(input: Device?, output: Device?) {
            self.input = input
            self.output = output
        }

        public var inputName: String? {
            input?.name
        }

        public var outputName: String? {
            output?.name
        }

        public var usesBluetoothInput: Bool {
            input?.usesBluetoothTransport ?? false
        }

        public var usesBluetoothOutput: Bool {
            output?.usesBluetoothTransport ?? false
        }

        public var containsTemporarilyUnsupportedBluetoothDevice: Bool {
            usesBluetoothInput || usesBluetoothOutput
        }

        public var description: String {
            "input: \(input?.diagnosticDescription ?? "unknown"), output: \(output?.diagnosticDescription ?? "unknown")"
        }
    }

    public static func currentRoute() -> Route {
        Route(
            input: device(for: defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)),
            output: device(for: defaultDeviceID(selector: kAudioHardwarePropertyDefaultSystemOutputDevice))
        )
    }

    private static func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            return nil
        }

        return deviceID
    }

    private static func device(for deviceID: AudioDeviceID?) -> Device? {
        guard let deviceID else {
            return nil
        }

        return Device(
            id: deviceID,
            uid: deviceUID(for: deviceID),
            name: deviceName(for: deviceID),
            transportType: transportType(for: deviceID)
        )
    }

    private static func deviceName(for deviceID: AudioDeviceID?) -> String? {
        guard let deviceID else {
            return nil
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)

        guard status == noErr else {
            return nil
        }

        return name as String
    }

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)

        guard status == noErr else {
            return nil
        }

        return uid as String
    }

    private static func transportType(for deviceID: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transportType)

        guard status == noErr else {
            return nil
        }

        return transportType
    }
}
