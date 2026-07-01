import Foundation

/// Removes microphone sentences that echo the system-audio transcript.
///
/// When a user records with speakers, the speaker output bleeds into the
/// microphone, producing near-identical sentences in both streams. This keeps
/// the system-audio transcript as the source of truth and drops the duplicated
/// sentences from the microphone transcript.
public enum TranscriptDeduplicator {
    public static let defaultThreshold = 0.95

    public static func deduplicate(_ transcript: Transcript, threshold: Double = defaultThreshold) -> Transcript {
        let referenceSentences = transcript.segments
            .filter { $0.speaker == AudioSource.systemAudio.rawValue }
            .flatMap { sentences(in: $0.text) }
            .map { normalize($0) }
            .filter { !$0.isEmpty }

        guard !referenceSentences.isEmpty else {
            return transcript
        }

        var deduplicatedSegments: [TranscriptSegment] = []

        for segment in transcript.segments {
            guard segment.speaker == AudioSource.microphone.rawValue else {
                deduplicatedSegments.append(segment)
                continue
            }

            let originalSentences = sentences(in: segment.text)
            let keptSentences = originalSentences.filter { sentence in
                let normalized = normalize(sentence)
                if normalized.isEmpty {
                    return false
                }
                return !referenceSentences.contains { reference in
                    similarity(normalized, reference) >= threshold
                }
            }

            let rejoined = keptSentences.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rejoined.isEmpty else {
                continue
            }

            deduplicatedSegments.append(
                TranscriptSegment(speaker: segment.speaker, startTime: segment.startTime, text: rejoined)
            )
        }

        return Transcript(segments: deduplicatedSegments)
    }

    static func sentences(in text: String) -> [String] {
        var results: [String] = []
        var current = ""

        for character in text {
            if character == "\n" || character == "\r" {
                appendIfNotEmpty(current, to: &results)
                current = ""
                continue
            }

            current.append(character)
            if character == "." || character == "!" || character == "?" {
                appendIfNotEmpty(current, to: &results)
                current = ""
            }
        }

        appendIfNotEmpty(current, to: &results)
        return results
    }

    private static func appendIfNotEmpty(_ value: String, to results: inout [String]) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            results.append(trimmed)
        }
    }

    static func normalize(_ sentence: String) -> String {
        let lowercased = sentence.lowercased()
        let scalars = lowercased.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == " " {
                return Character(scalar)
            }
            return " "
        }
        return String(scalars)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs {
            return 1
        }

        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        let maxLength = max(lhsChars.count, rhsChars.count)
        guard maxLength > 0 else {
            return 1
        }

        // Length pre-filter: if lengths differ too much, similarity cannot
        // reach a high threshold, so skip the expensive edit-distance work.
        let minLength = min(lhsChars.count, rhsChars.count)
        if Double(maxLength - minLength) / Double(maxLength) > 0.05 {
            return 0
        }

        let distance = levenshtein(lhsChars, rhsChars)
        return 1 - Double(distance) / Double(maxLength)
    }

    private static func levenshtein(_ lhs: [Character], _ rhs: [Character]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)

        for i in 1...lhs.count {
            current[0] = i
            for j in 1...rhs.count {
                let cost = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                current[j] = Swift.min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            swap(&previous, &current)
        }

        return previous[rhs.count]
    }
}
