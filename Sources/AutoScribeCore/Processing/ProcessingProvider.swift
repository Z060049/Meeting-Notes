import Foundation

public protocol ProcessingProvider: Sendable {
    func process(capture: AudioCaptureResult, settings: AppSettings) async throws -> ProcessingResult
}

public enum ProcessingProviderError: Error, LocalizedError {
    case missingAPIKey
    case unsupportedLocalMode
    case invalidResponse
    case apiError(String)
    case quotaExceeded(String)
    case localModelNotReady(String)
    case localProcessingError(String)
    case localUnsupported(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Set OPENAI_API_KEY in a .env file (project root or ~/Documents/AutoScribe/.env) before processing recordings."
        case .unsupportedLocalMode:
            "Local processing is planned after the API-first MVP."
        case .invalidResponse:
            "The processing provider returned an invalid response that AutoScribe could not parse."
        case .apiError(let message):
            message
        case .quotaExceeded(let message):
            message
        case .localModelNotReady(let message):
            message
        case .localProcessingError(let message):
            message
        case .localUnsupported(let message):
            message
        }
    }
}
