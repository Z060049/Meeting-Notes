import Foundation

public protocol SystemAudioRecording: AnyObject, Sendable {
    var backendName: String { get }
    var diagnosticSummary: String? { get }
    var onAudioLevel: ((Float) -> Void)? { get set }

    func start(in directory: URL) async throws -> URL
    func stop() async throws -> URL
}

public extension SystemAudioRecording {
    var diagnosticSummary: String? {
        nil
    }
}

public enum SystemAudioBackend: String, CaseIterable, Sendable {
    case coreAudioTap = "Core Audio Tap"
    case screenCaptureKit = "ScreenCaptureKit"
}

public enum SystemAudioRecorderFactory {
    public static func makePreferredRecorders(route: AudioRouteInspector.Route = AudioRouteInspector.currentRoute()) -> [SystemAudioRecording] {
        var recorders: [SystemAudioRecording] = []

        if route.usesBluetoothOutput, #available(macOS 13.0, *) {
            recorders.append(SystemAudioRecorder())
        }

        if #available(macOS 14.2, *) {
            recorders.append(CoreAudioTapSystemAudioRecorder())
        }

        if !route.usesBluetoothOutput, #available(macOS 13.0, *) {
            recorders.append(SystemAudioRecorder())
        }

        return recorders
    }

    public static func preferredBackendNames(route: AudioRouteInspector.Route = AudioRouteInspector.currentRoute()) -> [String] {
        var names: [String] = []

        if route.usesBluetoothOutput, #available(macOS 13.0, *) {
            names.append(SystemAudioBackend.screenCaptureKit.rawValue)
        }

        if #available(macOS 14.2, *) {
            names.append(SystemAudioBackend.coreAudioTap.rawValue)
        }

        if !route.usesBluetoothOutput, #available(macOS 13.0, *) {
            names.append(SystemAudioBackend.screenCaptureKit.rawValue)
        }

        return names
    }

    public static var preferredBackendNames: [String] {
        preferredBackendNames()
    }
}
