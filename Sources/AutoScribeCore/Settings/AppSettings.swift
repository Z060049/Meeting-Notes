import Foundation

public enum SummaryDepth: String, CaseIterable, Codable, Sendable {
    case brief
    case standard
    case detailed
}

public struct AppSettings: Equatable, Sendable {
    public var processingMode: ProcessingMode
    public var outputDirectory: URL
    public var inactivityTimeoutSeconds: TimeInterval
    public var summaryDepth: SummaryDepth
    public var shouldShowConsentReminder: Bool
    public var hasAcceptedConsentChecklist: Bool

    public init(
        processingMode: ProcessingMode = .api,
        outputDirectory: URL = FileManager.default.defaultAutoScribeOutputDirectory,
        inactivityTimeoutSeconds: TimeInterval = 180,
        summaryDepth: SummaryDepth = .standard,
        shouldShowConsentReminder: Bool = true,
        hasAcceptedConsentChecklist: Bool = false
    ) {
        self.processingMode = processingMode
        self.outputDirectory = outputDirectory
        self.inactivityTimeoutSeconds = inactivityTimeoutSeconds
        self.summaryDepth = summaryDepth
        self.shouldShowConsentReminder = shouldShowConsentReminder
        self.hasAcceptedConsentChecklist = hasAcceptedConsentChecklist
    }
}

public final class SettingsStore: @unchecked Sendable {
    private enum Key {
        static let processingMode = "processingMode"
        static let outputDirectory = "outputDirectory"
        static let inactivityTimeoutSeconds = "inactivityTimeoutSeconds"
        static let summaryDepth = "summaryDepth"
        static let shouldShowConsentReminder = "shouldShowConsentReminder"
        static let hasAcceptedConsentChecklist = "hasAcceptedConsentChecklist"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        var settings = AppSettings()

        if let rawMode = defaults.string(forKey: Key.processingMode),
           let mode = ProcessingMode(rawValue: rawMode) {
            settings.processingMode = mode
        }

        if let path = defaults.string(forKey: Key.outputDirectory), !path.isEmpty {
            settings.outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        }

        let timeout = defaults.double(forKey: Key.inactivityTimeoutSeconds)
        if timeout > 0 {
            settings.inactivityTimeoutSeconds = timeout
        }

        if let rawDepth = defaults.string(forKey: Key.summaryDepth),
           let depth = SummaryDepth(rawValue: rawDepth) {
            settings.summaryDepth = depth
        }

        if defaults.object(forKey: Key.shouldShowConsentReminder) != nil {
            settings.shouldShowConsentReminder = defaults.bool(forKey: Key.shouldShowConsentReminder)
        }

        settings.hasAcceptedConsentChecklist = defaults.bool(forKey: Key.hasAcceptedConsentChecklist)
        return settings
    }

    public func save(_ settings: AppSettings) {
        defaults.set(settings.processingMode.rawValue, forKey: Key.processingMode)
        defaults.set(settings.outputDirectory.path, forKey: Key.outputDirectory)
        defaults.set(settings.inactivityTimeoutSeconds, forKey: Key.inactivityTimeoutSeconds)
        defaults.set(settings.summaryDepth.rawValue, forKey: Key.summaryDepth)
        defaults.set(settings.shouldShowConsentReminder, forKey: Key.shouldShowConsentReminder)
        defaults.set(settings.hasAcceptedConsentChecklist, forKey: Key.hasAcceptedConsentChecklist)
    }
}
