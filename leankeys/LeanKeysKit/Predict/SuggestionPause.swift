import Foundation

/// Pause gate for the suggestion list (2026-11-28): the list shows only once the typist stops for `delay`.
///
/// Mid-flow a list costs a glance (~760 ms to pick, Li & Feit) that a fast typist never earns back; a stop is when
/// they are unsure and a row can help. On the developer's own debug log (3,386 letter-to-letter gaps) the median gap
/// was 138 ms, p75 212 ms, p90 393 ms, and 13.6 % of gaps reached 300 ms. Hence twice the typist's recent median gap,
/// clamped to 250–500 ms: about 280 ms for that rhythm, longer for a slower typist so a normal key gap is not a stop.
///
/// Predictions still run on every key; only the display waits. Rows the user made themselves (Gõ Tắt, learned
/// phrases) skip the wait. `defaults write io.github.anlvdt.leankeys LeanKeys.predict.pauseMs -int N` fixes the
/// delay at N ms (0 turns the gate off) for the "always / gated / off" typing-speed experiment.
public struct SuggestionPause {
    public static let overrideKey = "LeanKeys.predict.pauseMs"
    public static let minDelay: TimeInterval = 0.25
    public static let maxDelay: TimeInterval = 0.5
    /// Until `minSamples` gaps are known (fresh launch).
    public static let defaultDelay: TimeInterval = 0.3
    public static let minSamples = 8
    /// Recent gaps kept for the median.
    public static let window = 32
    /// Longer gaps are stops, not rhythm: they never count toward the median.
    public static let maxInterval: TimeInterval = 1.0
    static let factor = 2.0

    public private(set) var lastKeyAt: CFAbsoluteTime?
    private var intervals: [TimeInterval] = []
    private var nextSlot = 0
    /// Set from `overrideKey`; nil follows the rhythm.
    public var fixedDelay: TimeInterval?

    public init() {}

    public mutating func keyPressed(at t: CFAbsoluteTime) {
        if let last = lastKeyAt {
            let gap = t - last
            if gap > 0, gap <= Self.maxInterval {
                if intervals.count < Self.window {
                    intervals.append(gap)
                } else {
                    intervals[nextSlot] = gap
                    nextSlot = (nextSlot + 1) % Self.window
                }
            }
        }
        lastKeyAt = t
    }

    public var delay: TimeInterval {
        if let fixedDelay { return fixedDelay }
        guard intervals.count >= Self.minSamples else { return Self.defaultDelay }
        let sorted = intervals.sorted()
        let n = sorted.count
        let median = n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
        return min(Self.maxDelay, max(Self.minDelay, Self.factor * median))
    }

    /// When the list may show for the last key; nil when no key was seen.
    public var due: CFAbsoluteTime? { lastKeyAt.map { $0 + delay } }

    /// The override from `defaults`: nil when unset or negative, otherwise seconds.
    public static func fixedDelay(from defaults: UserDefaults) -> TimeInterval? {
        guard let ms = defaults.object(forKey: overrideKey) as? Int, ms >= 0 else { return nil }
        return TimeInterval(ms) / 1000
    }

    /// Rows the user made themselves show without waiting.
    public static func showsAtOnce(_ rows: [PredictionCandidate]) -> Bool {
        rows.contains { $0.kind == .shortcut || SuggestionGate.isLearnedPhrase($0) }
    }
}
