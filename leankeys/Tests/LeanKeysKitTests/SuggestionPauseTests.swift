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

    func testListWaitsForThePauseThenShows() {
        let (c, router, done) = setUp(pauseMs: 200)
        defer { done() }
        for ch in "anh đư" { router.mirror.typed(ch) }
        key(c, router)
        spin(0.08)
        XCTAssertFalse(c.isVisible, "still inside the pause: a fast typist sees nothing")
        spin(0.2)
        XCTAssertTrue(c.isVisible, "the typist stopped: the list shows")
        XCTAssertTrue(c.currentCandidates.contains { $0.display == "được" })
    }

    func testANewKeyRestartsThePause() {
        let (c, router, done) = setUp(pauseMs: 200)
        defer { done() }
        for ch in "anh đư" { router.mirror.typed(ch) }
        key(c, router)
        spin(0.12)
        router.mirror.typed("ơ")
        key(c, router)
        spin(0.13) // 250 ms after the first key, 130 ms after the second
        XCTAssertFalse(c.isVisible, "the first key's show was cancelled by the second key")
        spin(0.15)
        XCTAssertTrue(c.isVisible)
    }

    func testVisibleListHidesWhileTheNextKeyWaits() {
        let (c, router, done) = setUp(pauseMs: 150)
        defer { done() }
        for ch in "anh đư" { router.mirror.typed(ch) }
        key(c, router)
        spin(0.25)
        XCTAssertTrue(c.isVisible)
        router.mirror.typed("ơ")
        key(c, router)
        spin(0.06)
        XCTAssertFalse(c.isVisible, "the old rows are stale once a key lands: hidden until the next pause")
    }

    func testZeroMsTurnsTheGateOff() {
        let (c, router, done) = setUp(pauseMs: 0)
        defer { done() }
        for ch in "anh đư" { router.mirror.typed(ch) }
        key(c, router)
        spin(PredictionController.quickTypeWait + 0.03)
        XCTAssertTrue(c.isVisible)
    }
}
