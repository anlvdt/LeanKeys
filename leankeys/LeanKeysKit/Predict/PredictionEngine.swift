import Foundation
import VikeyShim

/// Context passed into `PredictionEngine` for ranking top candidates.
public struct PredictionQuery {
    /// Words in the current phrase strictly before `currentWord`.
    public let previousWords: [String]
    /// Partial word currently being typed (`""` immediately after Space or break).
    public let currentWord: String
    /// Whether the word is preceded by punctuation/symbol rather than whitespace (skip prediction mid-URL/identifier).
    public let followsNonSpaceBreak: Bool
    /// True when Space was just typed (or after accepting a prediction): allows next-word/phrase/sentence suggestions.
    public let atWordStartAfterSpace: Bool
    /// Whether Vietnamese mode is active.
    public let isVietnamese: Bool
    /// Enabled Gõ Tắt items.
    public let shortcuts: [(trigger: String, replacement: String)]

    public init(previousWords: [String], currentWord: String, followsNonSpaceBreak: Bool,
                atWordStartAfterSpace: Bool, isVietnamese: Bool,
                shortcuts: [(trigger: String, replacement: String)] = []) {
        self.previousWords = previousWords
        self.currentWord = currentWord
        self.followsNonSpaceBreak = followsNonSpaceBreak
        self.atWordStartAfterSpace = atWordStartAfterSpace
        self.isVietnamese = isVietnamese
        self.shortcuts = shortcuts
    }
}

/// Abstracts Vikey's C dictionary completion & Telex rendering so unit tests can run deterministically or against Vikey.
public protocol DictionaryCompleting {
    func completions(vietnamese: Bool, asciiPrefix: String, maxOut: Int) -> [(text: String, score: Int)]
}

public final class VikeyDictionaryCompleter: DictionaryCompleting {
    public static let shared = VikeyDictionaryCompleter()
    private init() {}

    public func completions(vietnamese: Bool, asciiPrefix: String, maxOut: Int) -> [(text: String, score: Int)] {
        guard asciiPrefix.allSatisfy(\.isASCII), !asciiPrefix.isEmpty, maxOut > 0 else { return [] }
        let cap = min(maxOut, 16)
        // `char out[16][32]` laid out contiguously in memory.
        var buffer = [CChar](repeating: 0, count: 16 * 32)
        var scores = [Int32](repeating: 0, count: 16)
        let count: Int32 = asciiPrefix.withCString { prefixPtr in
            buffer.withUnsafeMutableBufferPointer { bufPtr in
                scores.withUnsafeMutableBufferPointer { scorePtr in
                    bufPtr.baseAddress!.withMemoryRebound(to: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                                                               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                                                               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                                                               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar).self,
                                                          capacity: 16) { tuplePtr in
                        lk_vikey_completions(vietnamese ? 1 : 0, prefixPtr, tuplePtr, scorePtr.baseAddress, Int32(cap))
                    }
                }
            }
        }
        guard count > 0 else { return [] }
        var out: [(String, Int)] = []
        var unitBuf = [UInt16](repeating: 0, count: 64)
        for i in 0..<Int(count) {
            let offset = i * 32
            let raw = buffer[offset..<(offset + 32)].withUnsafeBufferPointer { slice -> String in
                String(cString: slice.baseAddress!)
            }
            guard !raw.isEmpty else { continue }
            if vietnamese {
                let len = raw.withCString { ptr in
                    unitBuf.withUnsafeMutableBufferPointer { uPtr in
                        lk_vikey_render_telex(ptr, uPtr.baseAddress, Int32(uPtr.count))
                    }
                }
                if len > 0 {
                    let rendered = String(decoding: unitBuf.prefix(Int(len)), as: UTF16.self)
                    out.append((rendered, Int(scores[i])))
                }
            } else {
                out.append((raw, Int(scores[i])))
            }
        }
        return out
    }
}

/// Multi-tier Laban Key-style prediction & completion ranker (word, phrase, sentence, shortcut).
public final class PredictionEngine {
    public static let maxCandidates = 3
    public static let minPrefixLength = 2

    /// How word rows grow into Google-style phrase rows (spec 2026-11-28-prediction-dropdown).
    public enum PhraseExtension: Equatable {
        /// Word rows stay words (v1.14).
        case off
        /// Replace a word row by "word + continuation" when a phrase continues `previous + word`.
        case replace
        /// Put "word + continuation" first and keep the bare word as the next row.
        case both
    }

    /// Longest continuation glued onto a word row.
    public static let maxExtensionWords = 5

    private let corpus: BuiltInPredictionCorpus
    private let personal: PersonalPredictionModel?
    private let dictionary: DictionaryCompleting?
    public var phraseExtension: PhraseExtension
    /// Shortest context (in words, the completed word included) a continuation must match to be glued on.
    public var minExtensionContext: Int
    /// Stay one word ahead (spec 2026-11-28-prediction-dropdown): once the typed word is a whole word, offer
    /// "word + next word" rows, and suggest from the first letter instead of hiding until the second.
    public var lookAhead: Bool
    /// Whether `word` is a whole corpus word (look-ahead may start).
    public func isWholeWord(_ word: String) -> Bool { corpus.isWord(word) }

    /// Shortest typed prefix that gets suggestions (`minPrefixLength`, or 1 with `lookAhead`).
    public var minPrefix: Int { lookAhead ? 1 : Self.minPrefixLength }

    /// Glue only phrases the user typed again and again (the learned model), never the built-in table: on the
    /// chat bench, rows glued from the built-in table were right past their first word 1–2 % of the time.
    public var personalExtensionOnly: Bool

    public init(corpus: BuiltInPredictionCorpus = .shared,
                personal: PersonalPredictionModel? = nil,
                dictionary: DictionaryCompleting? = VikeyDictionaryCompleter.shared,
                phraseExtension: PhraseExtension = .off,
                minExtensionContext: Int = 2,
                personalExtensionOnly: Bool = true,
                lookAhead: Bool = false) {
        self.corpus = corpus
        self.personal = personal
        self.dictionary = dictionary
        self.phraseExtension = phraseExtension
        self.minExtensionContext = minExtensionContext
        self.personalExtensionOnly = personalExtensionOnly
        self.lookAhead = lookAhead
    }

    /// Whether `query` may get suggestions at all (the same gates as `predict`): not mid-URL, a word start after
    /// Space with words before it, or a prefix of letters at least `minPrefix` long.
    public func accepts(_ query: PredictionQuery) -> Bool {
        guard !query.followsNonSpaceBreak else { return false }
        if query.currentWord.isEmpty { return query.atWordStartAfterSpace && !query.previousWords.isEmpty }
        let current = query.currentWord.precomposedStringWithCanonicalMapping
        return current.count >= minPrefix && current.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    public func predict(_ query: PredictionQuery) -> [PredictionCandidate] {
        guard !query.followsNonSpaceBreak else { return [] }

        if query.currentWord.isEmpty {
            guard query.atWordStartAfterSpace, !query.previousWords.isEmpty else { return [] }
            return extendWithPhrases(nextPredictions(after: query.previousWords, maxCount: Self.maxCandidates),
                                     previousWords: query.previousWords)
        }

        let current = query.currentWord.precomposedStringWithCanonicalMapping
        guard current.count >= minPrefix,
              current.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            return []
        }
        return extendWithPhrases(prefixCompletions(query: query, current: current, maxCount: Self.maxCandidates),
                                 previousWords: query.previousWords)
    }

    // MARK: - Google-style phrase rows

    /// Best continuation after `words` (personal first, then the built-in phrase table), matching at least
    /// `minExtensionContext` trailing words, trimmed to `maxExtensionWords`.
    func continuation(after words: [String]) -> String? {
        var best: (text: String, ctx: Int, score: Double)?
        func consider(_ text: String, _ ctx: Int, _ score: Double) {
            guard ctx >= minExtensionContext, !text.isEmpty else { return }
            if best == nil || ctx > best!.ctx || (ctx == best!.ctx && score > best!.score) { best = (text, ctx, score) }
        }
        if let personal {
            for c in personal.phraseContinuations(after: words) { consider(c.continuation, c.contextLen, c.score + 1000) }
        }
        if !personalExtensionOnly {
            for c in corpus.phraseContinuations(after: words) { consider(c.continuation, c.contextLen, c.rankScore) }
        }
        guard let best else { return nil }
        let parts = best.text.split(whereSeparator: \.isWhitespace)
        return parts.prefix(Self.maxExtensionWords).joined(separator: " ")
    }

    func extendWithPhrases(_ rows: [PredictionCandidate], previousWords: [String]) -> [PredictionCandidate] {
        guard phraseExtension != .off, !rows.isEmpty else { return rows }
        var out: [PredictionCandidate] = []
        var seen = Set<String>()
        func add(_ c: PredictionCandidate) {
            let key = BuiltInPredictionCorpus.normalizeTrigger(c.display)
            guard out.count < Self.maxCandidates, !seen.contains(key) else { return }
            seen.insert(key)
            out.append(c)
        }
        for row in rows {
            guard row.kind != .shortcut, !Self.endsWithSentencePunctuation(row.display),
                  let cont = continuation(after: previousWords + row.display.split(whereSeparator: \.isWhitespace).map(String.init))
            else {
                add(row)
                continue
            }
            let text = row.display + " " + cont
            let insertion = text + (Self.endsWithSentencePunctuation(text) ? "" : " ")
            let words = text.split(whereSeparator: \.isWhitespace).count
            add(PredictionCandidate(id: row.id + "+", display: text, insertion: insertion, deleteCount: row.deleteCount,
                                    kind: words >= 4 ? .sentence : .phrase, score: row.score,
                                    isPersonal: row.isPersonal || personalExtensionOnly))
            if phraseExtension == .both { add(row) }
        }
        return out
    }

    // MARK: - Mode A: Next word / phrase / sentence after Space

    private func nextPredictions(after previousWords: [String], maxCount: Int) -> [PredictionCandidate] {
        var pool: [PredictionCandidate] = []

        if let personal {
            for item in personal.phraseContinuations(after: previousWords) {
                let kind = Self.classifyContinuation(item.continuation)
                pool.append(makeNextCandidate(text: item.continuation, kind: kind, score: item.score, isPersonal: true))
            }
            for item in personal.nextWordContinuations(after: previousWords) {
                pool.append(makeNextCandidate(text: item.word, kind: .word, score: item.score, isPersonal: true))
            }
        }

        for item in corpus.phraseContinuations(after: previousWords) {
            let kind = Self.classifyContinuation(item.continuation)
            pool.append(makeNextCandidate(text: item.continuation, kind: kind, score: item.rankScore, isPersonal: false))
        }

        if let lastWord = previousWords.last {
            for item in corpus.bigramContinuations(after: lastWord) {
                let kind: PredictionKind = item.word.contains(" ") ? .phrase : .word
                pool.append(makeNextCandidate(text: item.word, kind: kind, score: item.rankScore, isPersonal: false))
            }
        }

        return Self.selectDiverseTop(pool, maxCount: maxCount)
    }

    // MARK: - Mode B: Mid-word & context-filtered completions

    private func prefixCompletions(query: PredictionQuery, current: String, maxCount: Int) -> [PredictionCandidate] {
        var pool: [PredictionCandidate] = []
        let lowerCurrent = current.lowercased()
        let foldedCurrent = BuiltInPredictionCorpus.foldDiacritics(current)
        let hasDiacritics = lowerCurrent != foldedCurrent
        let deleteCount = current.count

        // 1. User Gõ Tắt prefix matches
        for sc in query.shortcuts {
            let trig = sc.trigger.precomposedStringWithCanonicalMapping
            let trigLower = trig.lowercased()
            if trigLower.hasPrefix(lowerCurrent), !sc.replacement.isEmpty {
                let exact = trigLower == lowerCurrent
                let score = exact ? 260.0 : 120.0 - Double(trig.count)
                let rep = sc.replacement.precomposedStringWithCanonicalMapping
                let insertion = rep + (Self.endsWithSentencePunctuation(rep) ? "" : " ")
                let display = "\(trig) → \(rep)"
                pool.append(PredictionCandidate(
                    id: "sc:\(trigLower)",
                    display: display,
                    insertion: insertion,
                    deleteCount: deleteCount,
                    kind: .shortcut,
                    score: score,
                    isPersonal: true
                ))
            }
        }

        // 2. Context continuations matching the prefix the user started typing
        if !query.previousWords.isEmpty {
            let contextPool = nextPredictions(after: query.previousWords, maxCount: 10)
            for item in contextPool {
                let text = item.display
                let textLower = text.lowercased()
                let textFolded = BuiltInPredictionCorpus.foldDiacritics(text)
                let matchedExact = textLower.hasPrefix(lowerCurrent) && textLower != lowerCurrent
                let matchedFolded = !hasDiacritics && textFolded.hasPrefix(foldedCurrent) && textFolded != foldedCurrent
                guard matchedExact || matchedFolded else { continue }
                let cased = Self.applyCase(of: current, to: text)
                let bonus = matchedExact ? 80.0 : 45.0
                let insertion = cased + (Self.endsWithSentencePunctuation(cased) ? "" : " ")
                pool.append(PredictionCandidate(
                    id: "ctx:\(cased.lowercased())",
                    display: cased,
                    insertion: insertion,
                    deleteCount: deleteCount,
                    kind: item.kind,
                    score: item.score + bonus,
                    isPersonal: item.isPersonal
                ))
            }
        }

        // 3. Personal vocabulary
        if let personal {
            for item in personal.wordCompletions(matching: current, limit: 5) {
                let cased = Self.applyCase(of: current, to: item.word)
                pool.append(PredictionCandidate(
                    id: "pv:\(cased.lowercased())",
                    display: cased,
                    insertion: cased + " ",
                    deleteCount: deleteCount,
                    kind: cased.contains(" ") ? .phrase : .word,
                    score: item.score,
                    isPersonal: true
                ))
            }
        }

        // 4. Built-in Vietnamese & bilingual syllables/compounds
        for item in corpus.wordCompletions(matching: current, limit: 6) {
            let cased = Self.applyCase(of: current, to: item.word)
            pool.append(PredictionCandidate(
                id: "bw:\(cased.lowercased())",
                display: cased,
                insertion: cased + " ",
                deleteCount: deleteCount,
                kind: cased.contains(" ") ? .phrase : .word,
                score: item.score,
                isPersonal: false
            ))
        }

        // 4b. One word ahead: the typed word is whole, so offer it plus the words that usually follow.
        if lookAhead, corpus.isWord(current) {
            for next in nextPredictions(after: query.previousWords + [current], maxCount: Self.maxCandidates) {
                let text = current + " " + next.display
                pool.append(PredictionCandidate(
                    id: "ahead:\(text.lowercased())",
                    display: text,
                    insertion: text + (Self.endsWithSentencePunctuation(text) ? "" : " "),
                    deleteCount: deleteCount,
                    kind: next.kind == .word ? .phrase : .sentence,
                    // Below the word's own completions: many prefixes are words too ("đi" of "điện").
                    score: next.score - 1000,
                    isPersonal: next.isPersonal
                ))
            }
        }

        // 5. Vikey dictionary completions (English directly or pure-ASCII Telex Vietnamese)
        if let dictionary, current.allSatisfy(\.isASCII), current.count < 28 {
            // In English mode search English dictionary; in Vietnamese mode try English if word looks non-VN or search both.
            if !query.isVietnamese {
                for (text, rawScore) in dictionary.completions(vietnamese: false, asciiPrefix: lowerCurrent, maxOut: 5) {
                    guard text.lowercased() != lowerCurrent else { continue }
                    let cased = Self.applyCase(of: current, to: text)
                    let score = 48.0 + Double(rawScore) * 0.5
                    pool.append(PredictionCandidate(
                        id: "en:\(cased.lowercased())",
                        display: cased,
                        insertion: cased + " ",
                        deleteCount: deleteCount,
                        kind: .word,
                        score: score,
                        isPersonal: false
                    ))
                }
            } else {
                for (text, rawScore) in dictionary.completions(vietnamese: true, asciiPrefix: lowerCurrent, maxOut: 4) {
                    guard text.lowercased() != lowerCurrent else { continue }
                    let cased = Self.applyCase(of: current, to: text)
                    let score = 38.0 + Double(rawScore) * 0.4
                    pool.append(PredictionCandidate(
                        id: "vn:\(cased.lowercased())",
                        display: cased,
                        insertion: cased + " ",
                        deleteCount: deleteCount,
                        kind: .word,
                        score: score,
                        isPersonal: false
                    ))
                }
            }
        }

        return Self.selectDiverseTop(pool, maxCount: maxCount)
    }

    // MARK: - Helpers

    private func makeNextCandidate(text: String, kind: PredictionKind, score: Double, isPersonal: Bool) -> PredictionCandidate {
        let insertion = text + (Self.endsWithSentencePunctuation(text) ? "" : " ")
        return PredictionCandidate(
            id: "\(isPersonal ? "p" : "b"):\(text.lowercased())",
            display: text,
            insertion: insertion,
            deleteCount: 0,
            kind: kind,
            score: score,
            isPersonal: isPersonal
        )
    }

    private static func classifyContinuation(_ text: String) -> PredictionKind {
        let count = text.split(whereSeparator: \.isWhitespace).count
        if count >= 4 { return .sentence }
        if count >= 2 { return .phrase }
        return .word
    }

    static func endsWithSentencePunctuation(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return [".", "!", "?", ",", ";", ":"].contains(last)
    }

    /// Preserves `prefix` casing ("Chươ" -> "Chương", "CHƯƠ" -> "CHƯƠNG", "chươ" -> "chương").
    static func applyCase(of prefix: String, to candidate: String) -> String {
        let letters = prefix.filter(\.isLetter)
        guard !letters.isEmpty else { return candidate }
        if letters.count >= 2 && letters.allSatisfy(\.isUppercase) {
            return candidate.uppercased()
        }
        if let first = prefix.first, first.isUppercase, !candidate.isEmpty {
            return candidate.prefix(1).uppercased() + candidate.dropFirst()
        }
        return candidate
    }

    /// Deduplicates normalized keys and keeps top `maxCount` candidates sorted by score.
    private static func selectDiverseTop(_ pool: [PredictionCandidate], maxCount: Int) -> [PredictionCandidate] {
        var bestByKey: [String: PredictionCandidate] = [:]
        for cand in pool {
            let key = cand.kind == .shortcut
                ? cand.id
                : BuiltInPredictionCorpus.normalizeTrigger(cand.display)
            if let existing = bestByKey[key] {
                if cand.score > existing.score { bestByKey[key] = cand }
            } else {
                bestByKey[key] = cand
            }
        }
        let sorted = bestByKey.values.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.display.count < $1.display.count
        }
        return Array(sorted.prefix(maxCount))
    }
}
