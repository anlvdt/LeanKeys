import Foundation

/// Debug-log timing of the 4A+ path, one line per shown list. It records milliseconds only, never text, and only
/// while the debug log is on, which is off by default: privacy spec 2026-11-28, `DebugLog.maxAge`.
///
/// A line reads `[4A] tap→refresh=… predict=… ax=… show=… total=… dropped=…`, where:
/// - `tap→refresh` is the event tap to the start of `refreshNow` (injection and queue wait on main);
/// - `ax` is the caret lookup, or `cache`;
/// - `total` is the event tap to the list on screen;
/// - `dropped` is how many AX results were thrown away since the last shown list, because a newer key came first.
struct PredictionTrace {
    private static var onCache: (value: Bool, checkedAt: CFAbsoluteTime) = (false, 0)
    private static var isOn: Bool {
        let now = CFAbsoluteTimeGetCurrent()
        if now - onCache.checkedAt > 2 { onCache = (DebugLog.isOn, now) }
        return onCache.value
    }

    private var tapAt: CFAbsoluteTime = 0
    private var scheduledAt: CFAbsoluteTime = 0
    private var refreshAt: CFAbsoluteTime = 0
    private var predictMs: Double = 0
    private var ax = "?"
    private var dropped = 0

    mutating func keyEvent() {
        guard Self.isOn else { return }
        tapAt = CFAbsoluteTimeGetCurrent()
    }

    mutating func scheduled() { if Self.isOn { scheduledAt = CFAbsoluteTimeGetCurrent() } }
    mutating func refreshStarted() { if Self.isOn { refreshAt = CFAbsoluteTimeGetCurrent() } }
    mutating func predicted() { if Self.isOn { predictMs = (CFAbsoluteTimeGetCurrent() - refreshAt) * 1000 } }
    mutating func axCacheHit() { ax = "cache" }
    mutating func axResolved(ms: Double) { ax = String(format: "%.1f", ms) }
    mutating func axDropped() { dropped += 1 }

    mutating func shown(showMs: Double, rows: Int) {
        guard Self.isOn else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let start = tapAt > 0 ? tapAt : scheduledAt
        DebugLog.appendLine(String(format: "[4A] tap→refresh=%.1f predict=%.2f ax=%@ show=%.1f total=%.1f dropped=%d rows=%d\n",
                                   (refreshAt - start) * 1000, predictMs, ax, showMs, (now - start) * 1000, dropped, rows))
        dropped = 0
        ax = "?"
    }
}
