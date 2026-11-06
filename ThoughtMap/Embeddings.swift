import Foundation
import NaturalLanguage

/// Apple's built-in, on-device sentence embeddings. Used to find thoughts that are
/// about similar things, and as a fallback when Apple Intelligence isn't available.
enum Embeddings {
    private static let model: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: .english)

    static func vector(for text: String) -> [Double] {
        model?.vector(for: text) ?? []
    }

    /// Cosine similarity, from -1 (opposite) to 1 (same meaning).
    static func similarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }

    /// How similar two thoughts must be to draw a dotted "related" line. Raise to show fewer links.
    static let relatedThreshold = 0.6
    /// How similar a thought must be to an existing one to borrow its cluster when the AI is off.
    static let fallbackThreshold = 0.55
}
