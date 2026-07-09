import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

#if arch(arm64)
import MLXLLM
import MLXLMCommon
#endif

// MARK: - Tier

/// Indicates which backend will perform summarization on this device.
public enum SummarizationTier: String, Sendable, Equatable {
    /// Apple Intelligence (FoundationModels framework), available on macOS 26+ Apple Silicon.
    case appleIntelligence = "Apple Intelligence"
    /// On-device model inference via MLX, available on Apple Silicon macOS 14+.
    case mlx = "On-device Model (MLX)"
    /// Neither tier is supported (Intel Mac without Apple Intelligence).
    case unavailable = "Unavailable"
}

// MARK: - Service

/// Produces a `MeetingSummary` from a `Transcript` using fully local inference.
///
/// Tier selection at runtime:
///   - **Tier 1 (macOS 26+ Apple Silicon):** Apple Intelligence via `FoundationModels`.
///     Zero downloads required; model is built into the OS.
///   - **Tier 2 (macOS 14–25, Apple Silicon):** MLX-based LLM downloaded once by the user.
///   - **Unavailable (Intel Mac):** Throws `localUnsupported`.
public final class LocalSummarizationService: ObservableObject, @unchecked Sendable {

    @Published public private(set) var mlxDownloadState: ModelDownloadState = .notDownloaded

    public let tier: SummarizationTier

    #if arch(arm64)
    private var mlxContainer: ModelContainer?
    private var loadedMLXModelID: String?
    #endif

    public init() {
        self.tier = Self.detectTier()
    }

    // MARK: - Tier detection

    public static func detectTier() -> SummarizationTier {
        #if arch(arm64)
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if Self.isAppleIntelligenceAvailable() {
                return .appleIntelligence
            }
        }
        #endif
        return .mlx
        #else
        return .unavailable
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    public static func isAppleIntelligenceAvailable() -> Bool {
        let model = SystemLanguageModel.default
        if case .available = model.availability {
            return true
        }
        return false
    }
    #endif

    // MARK: - MLX model management

    /// Downloads and loads the MLX language model, if not already loaded.
    /// No-op on Tier 1 (Apple Intelligence handles itself).
    public func prepareMLXModel(modelID: String) async throws {
        guard tier == .mlx else { return }

        #if arch(arm64)
        if loadedMLXModelID == modelID, mlxContainer != nil {
            await setMLXState(.ready)
            return
        }

        await setMLXState(.downloading(progress: 0.0))

        do {
            let config = ModelConfiguration(id: modelID)
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { [weak self] progress in
                Task { await self?.setMLXState(.downloading(progress: progress.fractionCompleted)) }
            }
            mlxContainer = container
            loadedMLXModelID = modelID
            await setMLXState(.ready)
        } catch {
            let message = "Could not load language model '\(modelID)': \(error.localizedDescription)"
            await setMLXState(.failed(message))
            throw ProcessingProviderError.localModelNotReady(message)
        }
        #endif
    }

    public var isMLXReady: Bool {
        mlxDownloadState == .ready
    }

    // MARK: - Summarization

    /// Summarises a transcript using whichever tier is active on this device.
    public func summarize(
        transcript: Transcript,
        depth: SummaryDepth,
        mlxModelID: String
    ) async throws -> MeetingSummary {
        switch tier {
        case .appleIntelligence:
            return try await summarizeWithAppleIntelligence(transcript: transcript, depth: depth)
        case .mlx:
            return try await summarizeWithMLX(transcript: transcript, depth: depth, modelID: mlxModelID)
        case .unavailable:
            throw ProcessingProviderError.localUnsupported(
                "Local processing requires Apple Silicon. Please switch to API mode or use an Apple Silicon Mac."
            )
        }
    }

    // MARK: - Apple Intelligence path

    private func summarizeWithAppleIntelligence(
        transcript: Transcript,
        depth: SummaryDepth
    ) async throws -> MeetingSummary {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let session = LanguageModelSession()
            let prompt = buildPrompt(transcript: transcript, depth: depth)
            do {
                let response = try await session.respond(to: prompt)
                return try parseSummaryFromText(response.content)
            } catch {
                throw ProcessingProviderError.localProcessingError(
                    "Apple Intelligence summarization failed: \(error.localizedDescription)"
                )
            }
        }
        #endif
        // Fallback if FoundationModels unavailable at runtime despite tier detection
        throw ProcessingProviderError.localUnsupported(
            "Apple Intelligence is not available on this system. Please switch to API mode."
        )
    }

    // MARK: - MLX path

    private func summarizeWithMLX(
        transcript: Transcript,
        depth: SummaryDepth,
        modelID: String
    ) async throws -> MeetingSummary {
        #if arch(arm64)
        if mlxContainer == nil || loadedMLXModelID != modelID {
            try await prepareMLXModel(modelID: modelID)
        }
        guard let container = mlxContainer else {
            throw ProcessingProviderError.localModelNotReady(
                "MLX language model is not loaded. Download it in Settings > Local Model."
            )
        }

        let prompt = buildPrompt(transcript: transcript, depth: depth)
        let messages: [[String: String]] = [["role": "user", "content": prompt]]

        do {
            let result = try await container.perform { context in
                let promptTokens = try context.tokenizer.applyChatTemplate(
                    messages: messages,
                    addGenerationPrompt: true
                )
                return try generate(
                    input: .tokens(promptTokens),
                    parameters: GenerateParameters(temperature: 0.3, maxTokens: 1024),
                    context: context
                ) { _ in .more }
            }
            return try parseSummaryFromText(result.output)
        } catch {
            throw ProcessingProviderError.localProcessingError(
                "MLX summarization failed: \(error.localizedDescription)"
            )
        }
        #else
        throw ProcessingProviderError.localUnsupported(
            "MLX requires Apple Silicon. Please switch to API mode."
        )
        #endif
    }

    // MARK: - Prompt building

    private func buildPrompt(transcript: Transcript, depth: SummaryDepth) -> String {
        let depthInstruction: String
        switch depth {
        case .brief:    depthInstruction = "Keep each list to 2-3 items maximum."
        case .standard: depthInstruction = "Keep each list to 4-6 items."
        case .detailed: depthInstruction = "Be thorough; include all significant details."
        }

        return """
        You are a meeting notes assistant. Create a \(depth.rawValue) meeting summary from the following transcript.

        Rules:
        - Return ONLY valid JSON — no markdown fences, no explanation, no preamble.
        - \(depthInstruction)
        - If a section has nothing to report, use an empty array [].

        Required JSON format:
        {
          "title": "Brief descriptive meeting title",
          "keyPoints": ["point 1", "point 2"],
          "decisions": ["decision 1"],
          "actionItems": ["action item 1"],
          "followUps": ["follow-up question 1"]
        }

        Transcript:
        \(transcript.plainText)
        """
    }

    // MARK: - JSON parsing

    private func parseSummaryFromText(_ text: String) throws -> MeetingSummary {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```JSON", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Extract first JSON object if the model added preamble
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw ProcessingProviderError.localProcessingError(
                "Local model returned non-UTF-8 text."
            )
        }

        do {
            return try JSONDecoder().decode(MeetingSummary.self, from: data)
        } catch {
            throw ProcessingProviderError.localProcessingError(
                "Local model did not return valid meeting-summary JSON: \(error.localizedDescription)\n\nRaw output: \(cleaned.prefix(500))"
            )
        }
    }

    // MARK: - Private helpers

    @MainActor
    private func setMLXState(_ state: ModelDownloadState) {
        mlxDownloadState = state
    }
}
