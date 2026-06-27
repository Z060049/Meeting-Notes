import Foundation

public final class OpenAIProcessingProvider: ProcessingProvider, @unchecked Sendable {
    private let apiKeyProvider: @Sendable () throws -> String?
    private let session: URLSession
    private let transcriptionModel: String
    private let summaryModel: String

    public init(
        apiKeyProvider: @escaping @Sendable () throws -> String?,
        session: URLSession = .shared,
        transcriptionModel: String = "whisper-1",
        summaryModel: String = "gpt-4o-mini"
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.session = session
        self.transcriptionModel = transcriptionModel
        self.summaryModel = summaryModel
    }

    public func process(capture: AudioCaptureResult, settings: AppSettings) async throws -> ProcessingResult {
        guard settings.processingMode == .api else {
            throw ProcessingProviderError.unsupportedLocalMode
        }

        guard let apiKey = try apiKeyProvider(), !apiKey.isEmpty else {
            throw ProcessingProviderError.missingAPIKey
        }

        let transcript = try await transcribe(capture: capture, apiKey: apiKey)
        let summary = try await summarize(transcript: transcript, depth: settings.summaryDepth, apiKey: apiKey)
        return ProcessingResult(transcript: transcript, summary: summary)
    }

    private func transcribe(capture: AudioCaptureResult, apiKey: String) async throws -> Transcript {
        var segments: [TranscriptSegment] = []

        for file in capture.files {
            guard AudioTranscriptionPolicy.decision(for: file).shouldTranscribe else {
                continue
            }
            let response = try await transcribe(fileURL: file.url, source: file.source, apiKey: apiKey)
            segments.append(TranscriptSegment(speaker: file.source.rawValue, text: response.text))
        }

        return Transcript(segments: segments)
    }

    private func transcribe(fileURL: URL, source: AudioSource, apiKey: String) async throws -> TranscriptionResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = try MultipartFormData(boundary: boundary)
            .addingField(named: "model", value: transcriptionModel)
            .addingField(named: "response_format", value: "json")
            .addingField(named: "prompt", value: "Transcribe this \(source.rawValue.lowercased()) stream from a meeting.")
            .addingFile(named: "file", fileURL: fileURL, contentType: AudioTranscriptionPolicy.contentType(for: fileURL))
            .data()

        let (data, response) = try await session.upload(for: request, from: body)
        try validate(response: response, data: data)

        do {
            return try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        } catch {
            throw ProcessingProviderError.invalidResponse
        }
    }

    private func summarize(transcript: Transcript, depth: SummaryDepth, apiKey: String) async throws -> MeetingSummary {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = SummaryRequest(
            model: summaryModel,
            input: """
            Create a \(depth.rawValue) meeting summary from this transcript.
            Return only JSON matching the requested schema. Do not wrap the JSON in markdown.

            Transcript:
            \(transcript.plainText)
            """,
            text: SummaryTextOptions(
                format: SummaryJSONSchema(
                    type: "json_schema",
                    name: "meeting_summary",
                    strict: true,
                    schema: SummarySchema.object
                )
            )
        )

        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        guard let text = try ResponsesAPITextExtractor.extractText(from: data) else {
            throw ProcessingProviderError.apiError("OpenAI summary response did not contain output text.")
        }

        let cleanedText = Self.cleanJSONText(text)
        guard let jsonData = cleanedText.data(using: .utf8) else {
            throw ProcessingProviderError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(MeetingSummary.self, from: jsonData)
        } catch {
            throw ProcessingProviderError.apiError("OpenAI summary response was not valid meeting-summary JSON: \(error.localizedDescription)")
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProcessingProviderError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "OpenAI request failed."
            throw ProcessingProviderError.apiError(message)
        }
    }

    private static func cleanJSONText(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```JSON", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }
}

private struct TranscriptionResponse: Decodable {
    let text: String
}

private struct SummaryRequest: Encodable {
    let model: String
    let input: String
    let text: SummaryTextOptions
}

private struct SummaryTextOptions: Encodable {
    let format: SummaryJSONSchema
}

private struct SummaryJSONSchema: Encodable {
    let type: String
    let name: String
    let strict: Bool
    let schema: SummarySchema
}

private struct SummarySchema: Encodable {
    let type: String
    let additionalProperties: Bool
    let required: [String]
    let properties: [String: SummarySchemaProperty]

    static let object = SummarySchema(
        type: "object",
        additionalProperties: false,
        required: ["title", "keyPoints", "decisions", "actionItems", "followUps"],
        properties: [
            "title": SummarySchemaProperty.string,
            "keyPoints": SummarySchemaProperty.stringArray,
            "decisions": SummarySchemaProperty.stringArray,
            "actionItems": SummarySchemaProperty.stringArray,
            "followUps": SummarySchemaProperty.stringArray
        ]
    )
}

private enum SummarySchemaProperty: Encodable {
    case string
    case stringArray

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string:
            try container.encode("string", forKey: .type)
        case .stringArray:
            try container.encode("array", forKey: .type)
            try container.encode(StringItemSchema(type: "string"), forKey: .items)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case items
    }
}

private struct StringItemSchema: Encodable {
    let type: String
}

private struct ResponsesAPITextExtractor {
    static func extractText(from data: Data) throws -> String? {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            return nil
        }

        if let outputText = dictionary["output_text"] as? String {
            return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let output = dictionary["output"] as? [[String: Any]] else {
            return nil
        }

        for item in output {
            guard let content = item["content"] as? [[String: Any]] else {
                continue
            }

            for contentItem in content {
                if let text = contentItem["text"] as? String {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let text = contentItem["output_text"] as? String {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        return nil
    }
}

private struct MultipartFormData {
    private let boundary: String
    private var parts: [Data] = []

    init(boundary: String) {
        self.boundary = boundary
    }

    func addingField(named name: String, value: String) -> MultipartFormData {
        var copy = self
        var data = Data()
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        data.append("\(value)\r\n")
        copy.parts.append(data)
        return copy
    }

    func addingFile(named name: String, fileURL: URL, contentType: String) throws -> MultipartFormData {
        var copy = self
        var data = Data()
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        data.append("Content-Type: \(contentType)\r\n\r\n")
        data.append(try Data(contentsOf: fileURL))
        data.append("\r\n")
        copy.parts.append(data)
        return copy
    }

    func data() -> Data {
        var data = Data()
        parts.forEach { data.append($0) }
        data.append("--\(boundary)--\r\n")
        return data
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
