import AppKit
import XCTest
@testable import LeanKeysKit

/// QuickType as a second source (bench 2026-11-28: better next-word guesses than the built-in corpus).
final class QuickTypeMergeTests: XCTestCase {
    private func q(_ prev: [String], _ cur: String, afterSpace: Bool = false) -> PredictionQuery {
        PredictionQuery(previousWords: prev, currentWord: cur, followsNonSpaceBreak: false,
                        atWordStartAfterSpace: afterSpace, isVietnamese: true)
    }
    private func ours(_ text: String, typed: Int = 0, personal: Bool = false, kind: PredictionKind = .word) -> PredictionCandidate {
        PredictionCandidate(id: "o:\(text)", display: text, insertion: text + " ", deleteCount: typed, kind: kind,
                            score: 1, isPersonal: personal)
    }

    func testNextWordPutsLearnedPhrasesThenQuickTypeThenOurs() {
        let rows = PredictionEngine.merge(
            ours: [ours("bạn"), ours("báo cáo tiến độ nhé", personal: true, kind: .phrase)],
            quickType: ["anh", "bạn", "em"], phase: .next, query: q(["cảm", "ơn"], "", afterSpace: true))
        XCTAssertEqual(rows.map(\.display), ["báo cáo tiến độ nhé", "anh", "bạn"])
        XCTAssertEqual(rows[1].deleteCount, 0)
        XCTAssertEqual(rows[1].insertion, "anh ")
    }

    func testAheadGluesQuickTypesNextWordOntoTheTypedWord() {
        let rows = PredictionEngine.merge(ours: [ours("cảm ơn", typed: 3, kind: .phrase)], quickType: ["ơn", "thấy"],
                                          phase: .ahead, query: q([], "cảm"))
        XCTAssertEqual(rows.map(\.display), ["cảm ơn", "cảm thấy"])
        XCTAssertEqual(rows[1].deleteCount, 3)
        XCTAssertEqual(rows[1].insertion, "cảm thấy ")
    }

    func testShortWholeWordKeepsItsCompletionFirst() {
        // "đi" is a word and the start of "điện": its completion stays row 1, the look-ahead row comes second.
        let rows = PredictionEngine.merge(ours: [ours("điện", typed: 2), ours("đi làm", typed: 2, kind: .phrase)],
                                          quickType: ["học"], phase: .ahead, query: q([], "đi"))
        XCTAssertEqual(rows.map(\.display), ["điện", "đi học", "đi làm"])
    }

    func testMidWordAlternatesOursAndQuickTypeAndDropsTheTypedText() {
        let rows = PredictionEngine.merge(ours: [ours("Chương", typed: 3), ours("Chưa", typed: 3)],
                                          quickType: ["chư", "chương", "chứng"], phase: .mid, query: q([], "Chư"))
        XCTAssertEqual(rows.map(\.display), ["Chương", "Chứng", "Chưa"])
        XCTAssertEqual(rows[1].deleteCount, 3)
    }

    func testRequestTextPerPhase() {
        XCTAssertEqual(PredictionEngine.quickTypeText(for: q(["Em", "gửi"], "", afterSpace: true), phase: .next), "Em gửi ")
        XCTAssertEqual(PredictionEngine.quickTypeText(for: q(["Em"], "gửi"), phase: .ahead), "Em gửi ")
        XCTAssertEqual(PredictionEngine.quickTypeText(for: q(["Em"], "gử"), phase: .mid), "Em gử")
    }

    // MARK: - Controller: waits briefly for QuickType, merges a late answer, never asks for mid-URL text

    private final class FakeSource: AsyncPredictionSource {
        var requests: [String] = []
        var pending: [([String]) -> Void] = []
        func request(text: String, vietnamese: Bool, completion: @escaping ([String]) -> Void) {
            requests.append(text)
            pending.append(completion)
        }
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func setUp(_ source: FakeSource) -> (PredictionController, EngineRouter, () -> Void) {
        _ = NSApplication.shared
        let suite = "QuickTypeMergeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let c = PredictionController(defaults: defaults, personal: PersonalPredictionModel(store: nil),
                                     corpus: BuiltInPredictionCorpus(data: .bundled), dictionary: nil,
                                     onLearnerQueue: { $0() }, onMain: { $0() }, quickType: source)
        c.setEnabled(true)
        c.caretAnchor = { CaretLocator.CaretAnchor(rect: CGRect(x: 300, y: 400, width: 2, height: 18), isFieldFallback: false) }
        let router = EngineRouter(defaults: defaults, makeVikey: { nil })
        return (c, router, { c.hide(); defaults.removePersistentDomain(forName: suite) })
    }

    func testWordStartAsksNoQuickTypeAndShowsOnlyLearnedPhrases() {
        let source = FakeSource()
        let (c, router, done) = setUp(source)
        defer { done() }
        for ch in "cảm " { router.mirror.typed(ch) }
        c.refreshNow(router: router, bundleID: "com.apple.TextEdit", isVietnamese: true, atWordStartAfterSpace: true)
        spin(PredictionController.quickTypeWait + 0.03)
        XCTAssertTrue(source.requests.isEmpty, "next-word guesses are gated out, so QuickType is not asked")
        XCTAssertFalse(c.isVisible, "the built-in 'ơn' is a guess, not a learned phrase: silent at a word start")
    }

    func testMidWordWaitsForQuickTypeThenShowsGatedRows() {
        let source = FakeSource()
        let (c, router, done) = setUp(source)
        defer { done() }
        for ch in "anh đư" { router.mirror.typed(ch) }
        c.refreshNow(router: router, bundleID: "com.apple.TextEdit", isVietnamese: true, atWordStartAfterSpace: false)
        XCTAssertEqual(source.requests, ["anh đư"])
        spin(0.005)
        XCTAssertFalse(c.isVisible, "waits for QuickType (up to quickTypeWait) before the first show")
        source.pending[0](["đư", "được", "đứng"])
        spin(0.01)
        XCTAssertTrue(c.isVisible)
        XCTAssertLessThanOrEqual(c.currentCandidates.count, SuggestionGate.maxRows)
        XCTAssertTrue(c.currentCandidates.contains { $0.display == "được" })
    }

    func testLateQuickTypeAnswerIsDroppedNotRedrawn() {
        let source = FakeSource()
        let (c, router, done) = setUp(source)
        defer { done() }
        for ch in "anh đư" { router.mirror.typed(ch) }
        c.refreshNow(router: router, bundleID: "com.apple.TextEdit", isVietnamese: true, atWordStartAfterSpace: false)
        spin(PredictionController.quickTypeWait + 0.03)
        let before = c.currentCandidates.map(\.display)
        source.pending[0](["đưỡng"])
        spin(0.01)
        XCTAssertEqual(c.currentCandidates.map(\.display), before, "rows stay put once shown")
    }

    func testNoQuickTypeRequestMidURL() {
        let source = FakeSource()
        let (c, router, done) = setUp(source)
        defer { done() }
        for ch in "example.co" { router.mirror.typed(ch) }
        c.refreshNow(router: router, bundleID: "com.apple.TextEdit", isVietnamese: true, atWordStartAfterSpace: false)
        XCTAssertTrue(source.requests.isEmpty)
    }
}
