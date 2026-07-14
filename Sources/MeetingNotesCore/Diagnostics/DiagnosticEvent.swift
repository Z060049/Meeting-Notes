import Foundation

public struct DiagnosticEvent: Identifiable, Equatable, Sendable {
    public enum Level: String, Sendable {
        case info = "Info"
        case warning = "Warning"
        case error = "Error"
    }

    public let id: UUID
    public let date: Date
    public let level: Level
    public let message: String

    public init(id: UUID = UUID(), date: Date = Date(), level: Level, message: String) {
        self.id = id
        self.date = date
        self.level = level
        self.message = message
    }

    public var formatted: String {
        "[\(Self.formatter.string(from: date))] \(level.rawValue): \(message)"
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
