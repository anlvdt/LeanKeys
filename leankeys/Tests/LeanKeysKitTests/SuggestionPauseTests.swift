import AppKit
import XCTest
@testable import LeanKeysKit

final class SuggestionPauseTests: XCTestCase {
    // MARK: - Delay from the typist's own rhythm

    private func typed(every interval: TimeInterval, count: Int, from start: CFAbsoluteTime = 1000) -> SuggestionPause {
        var p = SuggestionPause()
        for i in 0 ..< count { p.keyPressed(at: start + Double(i) * interval) }
        return p
    }

    func testNoKeyYetMeansNoWait() {
        XCTAssertNil(SuggestionPause().due, "no key seen (a click, a test, a chained refresh): show at once")
    }

    func testDefaultDelayUntilEnoughSamples() {
        let p = typed(every: 0.14, count: SuggestionPause.minSamples)
        XCTAssertEqual(p.delay, SuggestionPause.defaultDelay, accuracy: 1e-9)
    }

    func testDelayIsTwiceTheMedianInterval() {
        let p = typed(every: 0.14, count: 20)
        XCTAssertEqual(p.delay, 0.28, accuracy: 1e-6)
        XCTAssertEqual(p.due ?? 0, 1000 + 19 * 0.14 + 0.28, accuracy: 1e-6)
    }

    func testDelayIsClamped() {
        XCTAssertEqual(typed(every: 0.06, count: 20).delay, SuggestionPause.minDelay, accuracy: 1e-9)
        XCTAssertEqual(typed(every: 0.40, count: 20).delay, SuggestionPause.maxDelay, accuracy: 1e-9)
    }

    func testLongGapsAreHesitationNotRhythm() {
        var p = typed(every: 0.14, count: 20)
        for i in 1 ... 10 { p.keyPressed(at: 2000 + Double(i) * 5) }
        XCTAssertEqual(p.delay, 0.28, accuracy: 1e-6, "gaps over maxInterval are pauses, so they do not slow the gate")
    }

    func testOnlyRecentRhythmCounts() {
        var p = typed(every: 0.40, count: 40)
        for i in 1 ... SuggestionPause.window { p.keyPressed(at: 2000 + Double(i) * 0.14) }
        XCTAssertEqual(p.delay, 0.28, accuracy: 1e-6)
    }

    func testFixedDelayOverridesTheRhythm() {
        var p = typed(every: 0.14, count: 20)
        p.fixedDelay = 0.6
        XCTAssertEqual(p.delay, 0.6, accuracy: 1e-9)
        p.fixedDelay = 0
        XCTAssertEqual(p.delay, 0, "0 ms turns the gate off")
    }

    func testFixedDelayFromDefaults() {
        let suite = "SuggestionPauseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(SuggestionPause.fixedDelay(from: defaults))
        defaults.set(450, forKey: SuggestionPause.overrideKey)
        XCTAssertEqual(SuggestionPause.fixedDelay(from: defaults) ?? -1, 0.45, accuracy: 1e-9)
        defaults.set(0, forKey: SuggestionPause.overrideKey)
        XCTAssertEqual(SuggestionPause.fixedDelay(from: defaults), 0)
        defaults.set(-5, forKey: SuggestionPause.overrideKey)
        XCTAssertNil(SuggestionPause.fixedDelay(from: defaults), "a negative value is ignored")
    }

    // MARK: - Rows that skip the wait

    private func row(_ text: String, kind: PredictionKind, personal: Bool = false) -> PredictionCandidate {
        PredictionCandidate(id: text, display: text, insertion: text + " ", deleteCount: 0, kind: kind, score: 1,
                            isPersonal: personal)
    }

    func testShortcutsAndLearnedPhrasesShowAtOnce() {
        XCTAssertTrue(SuggestionPause.showsAtOnce([row("ko → không", kind: .shortcut)]))
        XCTAssertTrue(SuggestionPause.showsAtOnce([row("được", kind: .word), row("cảm ơn bạn", kind: .phrase, personal: true)]))
        XCTAssertFalse(SuggestionPause.showsAtOnce([row("được", kind: .word), row("đứng", kind: .word, personal: true)]),
                       "a learned single word is still a guess at a completion")
        XCTAssertFalse(SuggestionPause.showsAtOnce([row("cảm ơn nhiều", kind: .phrase)]), "a built-in phrase waits")
    }

    // MARK: - Controller: the list waits for the pause

    private final class FakeSource: AsyncPredictionSource {
        var pending: [([String]) -> Void] = []
        func request(text: String, vietnamese: Bool, completion: @escaping ([String]) -> Void) {
            pending.append(completion)
            completion(["được", "đứng"])
        }
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func setUp(pauseMs: Int?) -> (PredictionController, EngineRouter, () -> Void) {
        _ = NSApplication.shared
        let suite = "SuggestionPauseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        if let pauseMs { defaults.set(pauseMs, forKey: SuggestionPause.overrideKey) }
        let c = PredictionController(defaults: defaults, personal: PersonalPredictionModel(store: nil),
                                     corpus: BuiltInPredictionCorpus(data: .bundled), dictionary: nil,
                                     onLearnerQueue: { $0() }, onMain: { $0() }, quickType: FakeSource())
        c.setEnabled(true)
        c.caretAnchor = { CaretLocator.CaretAnchor(rect: CGRect(x: 300, y: 400, width: 2, height: 18), isFieldFallback: false) }
        let router = EngineRouter(defaults: defaults, makeVikey: { nil })
        return (c, router, { c.hide(); defaults.removePersistentDomain(forName: suite) })
    }

    private func key(_ c: PredictionController, _ router: EngineRouter) {
        c.noteKeyEvent()
        c.refreshNow(router: router, bundleID: "com.apple.TextEdit", isVietnamese: true, atWordStartAfterSpace: false)
    }

    /// Polls the run loop until `c.isVisible == visible` or `timeout` passes; returns when it happened.
    /// Timing asserts below only check "not before the pause" and "eventually": a loaded machine (the pre-push hook
    /// runs the suite beside other work) may delay a show, never bring it forward.
    @discardableResult
    private func waitUntil(_ c: PredictionController, visible: Bool, timeout: TimeInterval = 3) -> CFAbsoluteTime? {
        let end = CFAbsoluteTimeGetCurrent() + timeout
        while CFAbsoluteTimeGetCurrent() < end {
            if c.isVisible == visible { return CFAbsoluteTimeGetCurrent() }
            spin(0.002)
        }
        return nil
    }

    func testListWaitsForThePauseThenShows() {
        let (c, router, done) = setUp(pauseMs: 300)
        defer { done() }
        for ch in "anh đư" { router.mirror.typed(ch) }
        let keyAt = CFAbsoluteTimeGetCurrent()
        key(c, router)
        let shownAt = waitUntil(c, visible: true)
        XCTAssertNotNil(shownAt, "the typist stopped: the list shows")
        XCTAssertGreaterThanOrEqual((shownAt ?? 0) - keyAt, 0.29, "not before the pause: a fast typist sees nothing")
        XCTAssertTrue(c.currentCandidates.contains { $0.display == "được" })
    }

    func testANewKeyRestartsThePause() throws {
        let (c, router, done) = setUp(pauseMs: 300)
        defer { done() }
        for ch in "anh đư" { router.mirror.typed(ch) }
        let firstAt = CFAbsoluteTimeGetCurrent()
        key(c, router)
        spin(0.15)
        try XCTSkipIf(CFAbsoluteTimeGetCurrent() - firstAt > 0.25, "run loop overslept: the second key would land after the first pause")
        XCTAssertFalse(c.isVisible)
        router.mirror.typed("ơ")
        let secondAt = CFAbsoluteTimeGetCurrent()
        key(c, router)
        let shownAt = waitUntil(c, visible: true)
        XCTAssertNotNil(shownAt)
        XCTAssertGreaterThanOrEqual((shownAt ?? 0) - secondAt, 0.29,
                                    "the first key's show (due 150 ms after the second key) was cancelled")
    }

    func testVisibleListHidesWhileTheNextKeyWaits() {
        let (c, router, done) = setUp(pauseMs: 1000)
        defer { done() }
        for ch in "anh đư" { router.mirror.typed(ch) }
        key(c, router)
        XCTAssertNotNil(waitUntil(c, visible: true))
        router.mirror.typed("ơ")
        let secondAt = CFAbsoluteTimeGetCurrent()
        key(c, router)
        let hiddenAt = waitUntil(c, visible: false)
        XCTAssertNotNil(hiddenAt, "the old rows are stale once a key lands: hidden until the next pause")
        XCTAssertLessThan((hiddenAt ?? .infinity) - secondAt, 0.9, "hidden well before the next pause ends")
    }

    func testZeroMsTurnsTheGateOff() {
        let (c, router, done) = setUp(pauseMs: 0)
        defer { done() }
        for ch in "anh đư" { router.mirror.typed(ch) }
        let keyAt = CFAbsoluteTimeGetCurrent()
        key(c, router)
        let shownAt = waitUntil(c, visible: true)
        XCTAssertNotNil(shownAt)
        XCTAssertLessThan((shownAt ?? .infinity) - keyAt, 0.5, "no pause: shows as soon as QuickType and the caret are in")
    }
}
