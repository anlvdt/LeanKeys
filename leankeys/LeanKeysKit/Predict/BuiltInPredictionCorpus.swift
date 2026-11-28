import Foundation

/// Raw JSON layout of `Resources/VietnamesePredictions.json`.
public struct PredictionCorpusData: Decodable {
    public let words: [String]
    public let bigrams: [String: [String]]
    public let phrases: [String: [String]]

    public init(words: [String] = [], bigrams: [String: [String]] = [:], phrases: [String: [String]] = [:]) {
        self.words = words
        self.bigrams = bigrams
        self.phrases = phrases
    }

    public static let bundled: PredictionCorpusData = {
        guard let url = Bundle.module.url(forResource: "VietnamesePredictions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(PredictionCorpusData.self, from: data)
        else {
            assertionFailure("VietnamesePredictions.json is missing or unreadable")
            return PredictionCorpusData()
        }
        return file
    }()
}

/// Fast, immutable lookup index over the bundled Vietnamese & bilingual prediction corpus.
/// Thread-safe (read-only after init).
public final class BuiltInPredictionCorpus {
    public struct WordEntry {
        public let text: String
        public let lower: String
        public let folded: String
        public let isCompound: Bool
        public let rank: Int
    }

    public static let shared = BuiltInPredictionCorpus(data: .bundled)

    private let words: [WordEntry]
    private let wordsByFirstChar: [Character: [WordEntry]]
    private let bigrams: [String: [String]]
    private let phrases: [String: [String]]
    private let maxPhraseTriggerWords: Int

    public init(data: PredictionCorpusData) {
        var allWords: [WordEntry] = []
        allWords.reserveCapacity(data.words.count)
        var byFirst: [Character: [WordEntry]] = [:]
        for (idx, raw) in data.words.enumerated() {
            let norm = raw.precomposedStringWithCanonicalMapping
            let entry = WordEntry(
                text: norm,
                lower: norm.lowercased(),
                folded: Self.foldDiacritics(norm),
                isCompound: norm.contains(" "),
                rank: idx
            )
            allWords.append(entry)
            if let first = entry.folded.first {
                byFirst[first, default: []].append(entry)
            }
        }
        self.words = allWords
        self.wordsByFirstChar = byFirst
        var bg: [String: [String]] = [:]
        bg.reserveCapacity(data.bigrams.count)
        for (k, v) in data.bigrams {
            let key = Self.normalizeTrigger(k)
            bg[key] = v.map { $0.precomposedStringWithCanonicalMapping }
        }
        self.bigrams = bg

        var ph: [String: [String]] = [:]
        ph.reserveCapacity(data.phrases.count)
        var maxWords = 1
        for (k, v) in data.phrases {
            let key = Self.normalizeTrigger(k)
            let count = key.split(separator: " ").count
            if count > maxWords { maxWords = count }
            ph[key] = v.map { $0.precomposedStringWithCanonicalMapping }
        }
        self.phrases = ph
        self.maxPhraseTriggerWords = min(maxWords, 4)
    }

    /// Lowercased, NFC-normalized single-space join of words.
    public static func normalizeTrigger(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Removes Vietnamese tone & vowel marks while turning đ/Đ into d/D so unaccented prefixes match accented words.
    public static func foldDiacritics(_ text: String) -> String {
        let mapped = text.precomposedStringWithCanonicalMapping
            .lowercased()
            .replacingOccurrences(of: "đ", with: "d")
        return mapped.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// Multi-word phrase & sentence continuations matching the longest suffix of `previousWords` first (up to 4 words).
    public func phraseContinuations(after previousWords: [String]) -> [(contextLen: Int, continuation: String, rankScore: Double)] {
        guard !previousWords.isEmpty else { return [] }
        let lower = previousWords.suffix(maxPhraseTriggerWords).map {
            $0.precomposedStringWithCanonicalMapping.lowercased()
        }
        var results: [(Int, String, Double)] = []
        let maxN = min(maxPhraseTriggerWords, lower.count)
        for n in stride(from: maxN, through: 1, by: -1) {
            let trigger = lower.suffix(n).joined(separator: " ")
            guard let list = phrases[trigger] else { continue }
            for (idx, cont) in list.enumerated() {
                // Longer context match outweighs shorter triggers; earlier order in corpus scores higher.
                let base = Double(n) * 100.0 + max(0.0, 20.0 - Double(idx) * 2.5)
                results.append((n, cont, base))
            }
        }
        return results
    }

    /// High-frequency single-word / short-pair continuations matching `previousWords.last`.
    public func bigramContinuations(after lastWord: String) -> [(word: String, rankScore: Double)] {
        let key = lastWord.precomposedStringWithCanonicalMapping.lowercased()
        guard let list = bigrams[key] else { return [] }
        return list.enumerated().map { idx, word in
            (word, 60.0 - Double(idx) * 3.0)
        }
    }

    /// Word/phrase prefix completions matching `prefix` (exact accented prefix outranks diacritic-folded prefix).
    public func wordCompletions(matching prefix: String, limit: Int = 6) -> [(word: String, score: Double)] {
        let normPrefix = prefix.precomposedStringWithCanonicalMapping.lowercased()
        let foldedPrefix = Self.foldDiacritics(prefix)
        guard let firstChar = foldedPrefix.first,
              let bucket = wordsByFirstChar[firstChar] else { return [] }
        let hasDiacritics = normPrefix != foldedPrefix
        var matches: [(String, Double)] = []
        matches.reserveCapacity(min(limit * 4, bucket.count))
        for entry in bucket {
            guard entry.lower != normPrefix else { continue }
            if entry.lower.hasPrefix(normPrefix) {
                let base = (entry.isCompound ? 42.0 : 50.0) - Double(entry.rank) * 0.02
                matches.append((entry.text, base))
            } else if !hasDiacritics, entry.folded.hasPrefix(foldedPrefix), entry.folded != foldedPrefix {
                let base = (entry.isCompound ? 26.0 : 32.0) - Double(entry.rank) * 0.02
                matches.append((entry.text, base))
            }
        }
        matches.sort { $0.1 > $1.1 }
        return Array(matches.prefix(limit))
    }
}
