import AppKit

/// Where the typed word stands when 4A+ asks for suggestions.
public enum PredictionPhase: Equatable {
    /// Right after Space: guess the next word.
    case next
    /// The typed word is whole, Space not yet: guess the word after it (look-ahead).
    case ahead
    /// Halfway through a word: complete it.
    case mid
}

/// A second suggestion source, asked asynchronously. `completion` may run on any thread.
public protocol AsyncPredictionSource: AnyObject {
    func request(text: String, vietnamese: Bool, completion: @escaping ([String]) -> Void)
}

/// macOS's own on-device QuickType model (`NSSpellChecker.requestCandidates`, the Touch Bar candidates). It has
/// Vietnamese. On the chat bench (2026-11-28) it guesses the next word better than the built-in corpus: 10.8 % /
/// 20.3 % (row 1 / top 3) against 7.0 % / 13.3 %, p95 8.7 ms. The text goes to the system spell service on this
/// Mac, never off it; secure fields and excluded apps never reach here (`PredictionController.refreshNow`).
public final class QuickTypeSource: AsyncPredictionSource {
    public static let shared = QuickTypeSource()

    private let checker = NSSpellChecker.shared
    private lazy var tag = NSSpellChecker.uniqueSpellDocumentTag()
    private let viOrthography = NSOrthography(dominantScript: "Latn", languageMap: ["Latn": ["vi", "en"]])
    private let enOrthography = NSOrthography(dominantScript: "Latn", languageMap: ["Latn": ["en"]])

    public init() {}

    public func request(text: String, vietnamese: Bool, completion: @escaping ([String]) -> Void) {
        let range = NSRange(location: (text as NSString).length, length: 0)
        _ = checker.requestCandidates(forSelectedRange: range, in: text, types: NSTextCheckingAllSystemTypes,
                                      options: [.orthography: vietnamese ? viOrthography : enOrthography],
                                      inSpellDocumentWithTag: tag) { _, results in
            completion(results.compactMap { $0.replacementString?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty })
        }
    }
}

extension PredictionEngine {
    /// The QuickType request text for `query` in `phase`: the phrase so far, with the trailing space a next-word
    /// guess needs.
    static func quickTypeText(for query: PredictionQuery, phase: PredictionPhase) -> String {
        let prev = query.previousWords.joined(separator: " ")
        switch phase {
        case .next: return prev + " "
        case .ahead: return (prev.isEmpty ? "" : prev + " ") + query.currentWord + " "
        case .mid: return (prev.isEmpty ? "" : prev + " ") + query.currentWord
        }
    }

    public func phase(of query: PredictionQuery) -> PredictionPhase {
        if query.currentWord.isEmpty { return .next }
        return lookAhead && isWholeWord(query.currentWord) ? .ahead : .mid
    }

    /// Merges QuickType's words into our rows, by what the bench found best for each phase
    /// (`PredictionLatencyBenchTests.testOursVersusQuickType`):
    /// - `.next`: learned phrases (typed twice or more) first, then QuickType, then ours;
    /// - `.ahead`: learned phrases, then "word + QuickType's next word", then ours;
    /// - `.mid`: ours and QuickType alternating (row 1 ours).
    /// From this many letters, a whole typed word shows "word + next word" before its own completions.
    static var aheadFirstMinLength = 3

    static func merge(ours: [PredictionCandidate], quickType: [String], phase: PredictionPhase,
                      query: PredictionQuery) -> [PredictionCandidate] {
        let current = query.currentWord.precomposedStringWithCanonicalMapping
        func row(_ text: String, deleteCount: Int, tag: String) -> PredictionCandidate {
            let kind: PredictionKind = text.contains(" ") ? .phrase : .word
            let insertion = text + (endsWithSentencePunctuation(text) ? "" : " ")
            return PredictionCandidate(id: "qt\(tag):\(text.lowercased())", display: text, insertion: insertion,
                                       deleteCount: deleteCount, kind: kind, score: 0)
        }
        let typedLower = current.lowercased()
        let qtWords = quickType.map { $0.precomposedStringWithCanonicalMapping }
            .filter { !$0.isEmpty && $0.lowercased() != typedLower }
        let learned = ours.filter { $0.isPersonal && $0.kind != .word }
        let rest = ours.filter { c in !learned.contains(where: { $0.id == c.id }) }

        var ordered: [PredictionCandidate] = []
        switch phase {
        case .next:
            ordered = learned + qtWords.map { row($0, deleteCount: 0, tag: "n") } + rest
        case .ahead:
            // The typed word may be whole ("cảm") or a prefix that is also a word ("đi" of "điện"): alternate the
            // word's completions with "word + next word" rows, completions first while the word is short.
            func isAhead(_ c: PredictionCandidate) -> Bool {
                let parts = c.display.split(whereSeparator: \.isWhitespace)
                return parts.count >= 2 && parts[0].lowercased() == typedLower
            }
            let completions = rest.filter { !isAhead($0) }
            let aheadRows = learned
                + qtWords.filter { !$0.contains(" ") }.map { row(current + " " + $0, deleteCount: current.count, tag: "a") }
                + rest.filter(isAhead)
            let (first, second) = current.count >= aheadFirstMinLength ? (aheadRows, completions) : (completions, aheadRows)
            for i in 0..<max(first.count, second.count) {
                if i < first.count { ordered.append(first[i]) }
                if i < second.count { ordered.append(second[i]) }
            }
        case .mid:
            let oursKeys = Set(ours.map { BuiltInPredictionCorpus.normalizeTrigger($0.display) })
            let qtRows = qtWords.map { row(applyCase(of: current, to: $0), deleteCount: current.count, tag: "m") }
                .filter { !oursKeys.contains(BuiltInPredictionCorpus.normalizeTrigger($0.display)) }
            for i in 0..<max(ours.count, qtRows.count) {
                if i < ours.count { ordered.append(ours[i]) }
                if i < qtRows.count { ordered.append(qtRows[i]) }
            }
        }
        var seen = Set<String>()
        var out: [PredictionCandidate] = []
        for c in ordered where out.count < maxCandidates {
            let key = BuiltInPredictionCorpus.normalizeTrigger(c.display)
            if seen.insert(key).inserted { out.append(c) }
        }
        return out
    }
}
