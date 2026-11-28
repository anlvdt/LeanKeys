import Foundation

/// Personal n-gram, vocabulary, and phrase/sentence memory for 4A+ predictions.
///
/// Privacy (spec 2026-11-28-privacy-opt-in & 2026-11-28-prediction-4a):
/// - Off by default (`enabled == false`).
/// - Never creates files or reads/writes keys until enabled AND observing valid non-sensitive input.
/// - Excludes Secure Input, secure text fields, nil bundle IDs, excluded apps (including CodeApps/terminals and
///   password managers), texts holding sensitive numbers (card/OTP), and secret-shaped tokens.
/// - Phrases/sentences and personal vocabulary require at least `phraseThreshold` (2) sightings before surfacing.
/// - Thread-safe: mutations run on the learner queue while main-thread prediction reads lock-guarded in-memory maps.
public final class PersonalPredictionModel {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LeanKeys/prediction.bin")
    }

    public static let phraseThreshold = 2
    public static let vocabThreshold = 2
    public static let maxBigramKeys = 2_000
    public static let maxTrigramKeys = 2_000
    public static let maxPhrases = 500
    public static let maxVocab = 2_000
    public static let maxContinuationsPerKey = 12
    public static let maxObservedWords = 18

    public struct Stats: Equatable {
        public let bigramCount: Int
        public let trigramCount: Int
        public let phraseCount: Int
        public let vocabCount: Int
    }

    struct Entry: Codable {
        var display: String
        var count: Int
        var lastSeen: TimeInterval
        enum CodingKeys: String, CodingKey { case display = "w", count = "c", lastSeen = "t" }
    }

    struct PhraseEntry: Codable {
        var text: String
        var words: [String]
        var count: Int
        var lastSeen: TimeInterval
        enum CodingKeys: String, CodingKey { case text = "x", words = "w", count = "c", lastSeen = "t" }
    }

    struct VocabEntry: Codable {
        var display: String
        var folded: String
        var count: Int
        var lastSeen: TimeInterval
        enum CodingKeys: String, CodingKey { case display = "d", folded = "f", count = "c", lastSeen = "t" }
    }

    private struct DiskSnapshot: Codable {
        var v = 1
        var bigrams: [String: [Entry]] = [:]
        var trigrams: [String: [Entry]] = [:]
        var phrases: [String: PhraseEntry] = [:]
        var vocab: [String: VocabEntry] = [:]
    }

    private struct IndexedVocab {
        let display: String
        let lower: String
        let folded: String
        let count: Int
    }

    private struct ReadIndex {
        var bigrams: [String: [Entry]] = [:]
        var trigrams: [String: [Entry]] = [:]
        var phrases: [PhraseEntry] = []
        var vocabByFirstChar: [Character: [IndexedVocab]] = [:]
    }

    private let store: LearnStore?
    private let lock = NSLock()
    private var loaded = false
    private var data = DiskSnapshot()
    private var index = ReadIndex()

    public var excludedBundleIDs: Set<String> = Exclusions.defaultBundleIDs

    private var _enabled = false
    public var enabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _enabled }
        set {
            lock.lock()
            _enabled = newValue
            lock.unlock()
            if newValue { _ = loadIfNeeded() }
        }
    }

    public init(store: LearnStore?) {
        self.store = store
    }

    public var stats: Stats {
        _ = loadIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        let bg = data.bigrams.values.reduce(0) { $0 + $1.count }
        let tg = data.trigrams.values.reduce(0) { $0 + $1.count }
        let ph = data.phrases.values.filter { $0.count >= Self.phraseThreshold }.count
        let vb = data.vocab.values.filter { $0.count >= Self.vocabThreshold }.count
        return Stats(bigramCount: bg, trigramCount: tg, phraseCount: ph, vocabCount: vb)
    }

    public func observe(_ phrase: CommittedPhrase, context: LearnContext) {
        guard enabled, !context.secureInput, !context.secureField,
              let bundleID = context.bundleID,
              !excludedBundleIDs.contains(bundleID),
              !Exclusions.isExcludedByDefault(bundleID) else { return }

        let display = PhraseDetector.normalizedDisplay(phrase.text)
        guard !display.isEmpty, !Exclusions.containsSensitiveNumber(display) else { return }

        let rawTokens = display.split(whereSeparator: \.isWhitespace).map(String.init)
        guard rawTokens.count >= 2, rawTokens.count <= Self.maxObservedWords else { return }
        // Never learn a phrase containing secret-shaped tokens, embedded 4+ digit codes (OTP/PIN/ID), emails, or URLs.
        for token in rawTokens {
            if Exclusions.looksLikeSecret(token) { return }
            if Exclusions.trimmedWord(token).range(of: #"\d{4,}"#, options: .regularExpression) != nil { return }
            if token.contains("@") || token.contains("://") || token.contains("/") || token.contains("\\") { return }
        }

        let words = TextMirror.words(in: display)
        guard words.count >= 2 else { return }
        guard loadIfNeeded() else { return }

        let ts = context.now.timeIntervalSince1970
        let lowerWords = words.map { $0.precomposedStringWithCanonicalMapping.lowercased() }

        lock.lock()
        // Bigrams
        for i in 0..<(words.count - 1) {
            let key = lowerWords[i]
            let nextDisplay = words[i + 1].precomposedStringWithCanonicalMapping
            recordNGram(&data.bigrams, key: key, nextDisplay: nextDisplay, ts: ts, cap: Self.maxBigramKeys)
        }
        // Trigrams
        if words.count >= 3 {
            for i in 0..<(words.count - 2) {
                let key = lowerWords[i] + " " + lowerWords[i + 1]
                let nextDisplay = words[i + 2].precomposedStringWithCanonicalMapping
                recordNGram(&data.trigrams, key: key, nextDisplay: nextDisplay, ts: ts, cap: Self.maxTrigramKeys)
            }
        }
        // Phrases / sentences (require threshold before suggesting)
        let phraseKey = lowerWords.joined(separator: " ")
        var pEntry = data.phrases[phraseKey] ?? PhraseEntry(text: display, words: lowerWords, count: 0, lastSeen: ts)
        pEntry.text = display
        pEntry.words = lowerWords
        pEntry.count += 1
        pEntry.lastSeen = ts
        data.phrases[phraseKey] = pEntry
        pruneDict(&data.phrases, cap: Self.maxPhrases, valueLastSeen: \.lastSeen)

        // Personal vocabulary
        for (idx, w) in words.enumerated() where w.count >= 2 {
            let key = lowerWords[idx]
            let cased = w.precomposedStringWithCanonicalMapping
            var vEntry = data.vocab[key] ?? VocabEntry(
                display: cased,
                folded: BuiltInPredictionCorpus.foldDiacritics(cased),
                count: 0,
                lastSeen: ts
            )
            // Prefer lowercase form for ordinary words unless repeatedly capitalized.
            if cased == key || vEntry.count == 0 {
                vEntry.display = cased
            }
            vEntry.count += 1
            vEntry.lastSeen = ts
            data.vocab[key] = vEntry
        }
        pruneDict(&data.vocab, cap: Self.maxVocab, valueLastSeen: \.lastSeen)

        rebuildReadIndexLocked()
        let snapshot = data
        lock.unlock()

        saveSnapshot(snapshot)
    }

    /// Queries learned phrases/sentences whose prefix matches the tail of `previousWords` (1–3 words).
    public func phraseContinuations(after previousWords: [String], now: TimeInterval = Date().timeIntervalSince1970)
        -> [(contextLen: Int, continuation: String, score: Double)]
    {
        guard !previousWords.isEmpty else { return [] }
        let lowerPrev = previousWords.suffix(3).map { $0.precomposedStringWithCanonicalMapping.lowercased() }
        lock.lock()
        // Learned data surfaces only while learning is on (spec 2026-11-28-privacy-opt-in), like `GatedLearnedNames`.
        let currentPhrases = _enabled ? index.phrases : []
        lock.unlock()

        var results: [(Int, String, Double)] = []
        for phrase in currentPhrases {
            let maxMatch = min(3, min(lowerPrev.count, phrase.words.count - 1))
            guard maxMatch >= 1 else { continue }
            for n in stride(from: maxMatch, through: 1, by: -1) {
                let tail = Array(lowerPrev.suffix(n))
                if Array(phrase.words.prefix(n)) == tail {
                    let displayWords = phrase.text.split(whereSeparator: \.isWhitespace).map(String.init)
                    guard displayWords.count > n else { break }
                    let cont = displayWords.dropFirst(n).joined(separator: " ")
                    let ageDays = max(0.0, (now - phrase.lastSeen) / 86_400.0)
                    let recencyBoost = 1.0 / (1.0 + ageDays / 14.0)
                    let score = 200.0 + Double(n) * 90.0 + Double(min(phrase.count, 20)) * 6.0 + recencyBoost * 15.0
                    results.append((n, cont, score))
                    break
                }
            }
        }
        return results
    }

    /// Queries personal trigrams (`alpha = 1.0`) and bigrams (`Stupid Backoff alpha = 0.4`).
    public func nextWordContinuations(after previousWords: [String], now: TimeInterval = Date().timeIntervalSince1970)
        -> [(word: String, score: Double)]
    {
        guard let last = previousWords.last?.precomposedStringWithCanonicalMapping.lowercased() else { return [] }
        let triKey: String? = previousWords.count >= 2
            ? previousWords[previousWords.count - 2].precomposedStringWithCanonicalMapping.lowercased() + " " + last
            : nil

        lock.lock()
        let on = _enabled
        let triEntries = on ? triKey.flatMap { index.trigrams[$0] } ?? [] : []
        let biEntries = on ? index.bigrams[last] ?? [] : []
        lock.unlock()

        var merged: [String: (display: String, score: Double)] = [:]
        for e in triEntries {
            let k = e.display.lowercased()
            let ageDays = max(0.0, (now - e.lastSeen) / 86_400.0)
            let recency = 1.0 / (1.0 + ageDays / 14.0)
            let s = 140.0 + Double(min(e.count, 30)) * 4.5 + recency * 12.0
            merged[k] = (e.display, s)
        }
        for e in biEntries {
            let k = e.display.lowercased()
            let ageDays = max(0.0, (now - e.lastSeen) / 86_400.0)
            let recency = 1.0 / (1.0 + ageDays / 14.0)
            // Stupid Backoff (0.4 weight vs trigram frequency scale) + personal boost over built-in defaults.
            let s = 75.0 + 0.4 * Double(min(e.count, 40)) * 3.5 + recency * 8.0
            if let existing = merged[k] {
                merged[k] = (existing.display, existing.score + s * 0.25)
            } else {
                merged[k] = (e.display, s)
            }
        }
        return merged.values.sorted { $0.score > $1.score }.map { ($0.display, $0.score) }
    }

    /// Personal vocabulary completions matching `prefix`.
    public func wordCompletions(matching prefix: String, limit: Int = 6) -> [(word: String, score: Double)] {
        let normPrefix = prefix.precomposedStringWithCanonicalMapping.lowercased()
        let foldedPrefix = BuiltInPredictionCorpus.foldDiacritics(prefix)
        guard let firstChar = foldedPrefix.first else { return [] }
        let hasDiacritics = normPrefix != foldedPrefix

        lock.lock()
        let entries = _enabled ? index.vocabByFirstChar[firstChar] ?? [] : []
        lock.unlock()
        guard !entries.isEmpty else { return [] }

        var out: [(String, Double)] = []
        for e in entries {
            guard e.lower != normPrefix else { continue }
            if e.lower.hasPrefix(normPrefix) {
                out.append((e.display, 65.0 + Double(min(e.count, 25)) * 1.5))
            } else if !hasDiacritics, e.folded.hasPrefix(foldedPrefix), e.folded != foldedPrefix {
                out.append((e.display, 45.0 + Double(min(e.count, 25)) * 1.5))
            }
        }
        out.sort { $0.1 > $1.1 }
        return Array(out.prefix(limit))
    }

    public func eraseAll() {
        lock.lock()
        data = DiskSnapshot()
        index = ReadIndex()
        loaded = true
        lock.unlock()
        try? store?.erase()
    }

    // MARK: - Private helpers

    private func recordNGram(_ dict: inout [String: [Entry]], key: String, nextDisplay: String, ts: TimeInterval, cap: Int) {
        var list = dict[key] ?? []
        let nextLower = nextDisplay.lowercased()
        if let idx = list.firstIndex(where: { $0.display.lowercased() == nextLower }) {
            list[idx].count += 1
            list[idx].lastSeen = ts
            if nextDisplay == nextLower { list[idx].display = nextDisplay }
        } else {
            list.append(Entry(display: nextDisplay, count: 1, lastSeen: ts))
        }
        list.sort { ($0.count != $1.count) ? ($0.count > $1.count) : ($0.lastSeen > $1.lastSeen) }
        if list.count > Self.maxContinuationsPerKey {
            list = Array(list.prefix(Self.maxContinuationsPerKey))
        }
        dict[key] = list

        if dict.count > cap {
            let evictKey = dict.min { a, b in
                let maxA = a.value.map(\.lastSeen).max() ?? 0
                let maxB = b.value.map(\.lastSeen).max() ?? 0
                return maxA < maxB
            }?.key
            if let evictKey { dict[evictKey] = nil }
        }
    }

    private func pruneDict<V>(_ dict: inout [String: V], cap: Int, valueLastSeen: KeyPath<V, TimeInterval>) {
        while dict.count > cap {
            guard let oldest = dict.min(by: { $0.value[keyPath: valueLastSeen] < $1.value[keyPath: valueLastSeen] })?.key
            else { break }
            dict[oldest] = nil
        }
    }

    private func rebuildReadIndexLocked() {
        index.bigrams = data.bigrams
        index.trigrams = data.trigrams
        index.phrases = data.phrases.values
            .filter { $0.count >= Self.phraseThreshold }
            .sorted { $0.count > $1.count }
        var grouped: [Character: [IndexedVocab]] = [:]
        for v in data.vocab.values where v.count >= Self.vocabThreshold {
            let item = IndexedVocab(
                display: v.display,
                lower: v.display.lowercased(),
                folded: v.folded,
                count: v.count
            )
            if let first = v.folded.first {
                grouped[first, default: []].append(item)
            }
        }
        for key in grouped.keys {
            grouped[key]?.sort { $0.count > $1.count }
        }
        index.vocabByFirstChar = grouped
    }

    private func loadIfNeeded() -> Bool {
        lock.lock()
        let already = loaded
        lock.unlock()
        if already { return true }
        guard let store else {
            lock.lock(); loaded = true; lock.unlock()
            return true
        }
        do {
            if let raw = try store.load(),
               let decoded = try? JSONDecoder().decode(DiskSnapshot.self, from: raw) {
                lock.lock()
                data = decoded
                rebuildReadIndexLocked()
                loaded = true
                lock.unlock()
                return true
            }
        } catch {
            return false
        }
        lock.lock()
        loaded = true
        lock.unlock()
        return true
    }

    private func saveSnapshot(_ snapshot: DiskSnapshot) {
        guard let store, let raw = try? JSONEncoder().encode(snapshot) else { return }
        try? store.save(raw)
    }
}
