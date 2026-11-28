import AppKit
import XCTest
@testable import LeanKeysKit

/// Google Search–style list keys (spec 2026-11-28-prediction-dropdown).
final class SuggestionListNavigatorTests: XCTestCase {
    private func nav(count: Int = 3, changedAt: CFAbsoluteTime = 0) -> SuggestionListNavigator {
        var n = SuggestionListNavigator()
        n.listChanged(count: count, at: changedAt)
        return n
    }

    func testDownEntersListThenMovesAndStopsAtLastRow() {
        var n = nav()
        XCTAssertNil(n.selectedIndex)
        XCTAssertEqual(n.handle(.down, now: 0.01), .swallow)
        XCTAssertEqual(n.selectedIndex, 0)
        XCTAssertEqual(n.handle(.down, now: 0.02), .swallow)
        XCTAssertEqual(n.handle(.down, now: 0.03), .swallow)
        XCTAssertEqual(n.handle(.down, now: 0.04), .swallow)
        XCTAssertEqual(n.selectedIndex, 2)
    }

    func testUpLeavesListFromFirstRowAndPassesWhenNothingSelected() {
        var n = nav()
        XCTAssertEqual(n.handle(.up, now: 0.01), .passAndHide)
        _ = n.handle(.down, now: 0.02)
        _ = n.handle(.down, now: 0.03)
        XCTAssertEqual(n.handle(.up, now: 0.04), .swallow)
        XCTAssertEqual(n.selectedIndex, 0)
        XCTAssertEqual(n.handle(.up, now: 0.05), .swallow)
        XCTAssertNil(n.selectedIndex)
    }

    func testTabAcceptsSelectedRow() {
        var n = nav()
        _ = n.handle(.down, now: 0.01)
        _ = n.handle(.down, now: 0.02)
        XCTAssertEqual(n.handle(.tab, now: 0.03), .accept(1))
    }

    func testTabAcceptsFirstRowOnlyOnceListHasSettled() {
        var n = nav(changedAt: 10)
        XCTAssertEqual(n.handle(.tab, now: 10 + SuggestionListNavigator.tabSettle - 0.01), .passAndHide,
                       "a fast Tab while the list is still changing must stay a Tab")
        n = nav(changedAt: 10)
        XCTAssertEqual(n.handle(.tab, now: 10 + SuggestionListNavigator.tabSettle), .accept(0))
    }

    func testEnterAcceptsOnlyWhenARowIsSelected() {
        var n = nav()
        XCTAssertEqual(n.handle(.enter, now: 5), .passAndHide)
        n = nav()
        _ = n.handle(.down, now: 0.01)
        XCTAssertEqual(n.handle(.enter, now: 0.02), .accept(0))
    }

    func testEscapeDismisses() {
        var n = nav()
        XCTAssertEqual(n.handle(.escape, now: 1), .dismiss)
        _ = n.handle(.down, now: 1)
        XCTAssertEqual(n.handle(.escape, now: 1), .dismiss)
    }

    func testTypingOrNewListClearsSelection() {
        var n = nav()
        _ = n.handle(.down, now: 0.01)
        n.typing()
        XCTAssertNil(n.selectedIndex)
        _ = n.handle(.down, now: 0.02)
        n.listChanged(count: 2, at: 0.03)
        XCTAssertNil(n.selectedIndex)
    }

    func testEmptyListPassesEverything() {
        var n = nav(count: 0)
        XCTAssertEqual(n.handle(.down, now: 1), .pass)
        XCTAssertEqual(n.handle(.tab, now: 1), .pass)
        XCTAssertEqual(n.handle(.enter, now: 1), .pass)
    }

    // MARK: - Controller + panel

    private func controller() -> (PredictionController, EngineRouter, UserDefaults, String) {
        let suite = "SuggestionListTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let c = PredictionController(defaults: defaults, personal: PersonalPredictionModel(store: nil),
                                     corpus: BuiltInPredictionCorpus(data: .bundled), dictionary: nil,
                                     onLearnerQueue: { $0() }, onMain: { $0() })
        c.setEnabled(true)
        return (c, EngineRouter(defaults: defaults, makeVikey: { nil }), defaults, suite)
    }

    private let anchor = CaretLocator.CaretAnchor(rect: CGRect(x: 300, y: 400, width: 2, height: 18), isFieldFallback: false)
    private func cand(_ text: String, typed: Int = 0) -> PredictionCandidate {
        PredictionCandidate(id: text, display: text, insertion: text + " ", deleteCount: typed, kind: .word, score: 1)
    }

    func testControllerDownThenEnterTakesSecondRow() {
        _ = NSApplication.shared
        let (c, router, defaults, suite) = controller()
        defer { c.hide(); defaults.removePersistentDomain(forName: suite) }
        var t: CFAbsoluteTime = 100
        c.presentForTesting([cand("báo cáo", typed: 2), cand("bạn", typed: 2), cand("bài", typed: 2)],
                            anchor: anchor, clock: { t })
        XCTAssertTrue(c.isVisible)
        XCTAssertEqual(c.handleListKey(.down), .swallow)
        XCTAssertEqual(c.handleListKey(.down), .swallow)
        XCTAssertEqual(c.selectedIndex, 1)
        guard case .accept(let i) = c.handleListKey(.enter) else { return XCTFail("Enter should accept") }
        let edit = c.acceptCandidate(at: i, router: router, isVietnamese: true)
        XCTAssertEqual(edit?.0, 2)
        XCTAssertEqual(edit.map { String($0.1) }, "bạn ")
        XCTAssertFalse(c.isVisible)
        t += 1
    }

    func testControllerFastTabStaysATabAndHides() {
        _ = NSApplication.shared
        let (c, _, defaults, suite) = controller()
        defer { c.hide(); defaults.removePersistentDomain(forName: suite) }
        var t: CFAbsoluteTime = 50
        c.presentForTesting([cand("ơn")], anchor: anchor, clock: { t })
        t += 0.05
        XCTAssertEqual(c.handleListKey(.tab), .passAndHide)
        XCTAssertFalse(c.isVisible)

        c.presentForTesting([cand("ơn")], anchor: anchor, clock: { t })
        t += SuggestionListNavigator.tabSettle
        XCTAssertEqual(c.handleListKey(.tab), .accept(0))
    }

    func testSameListKeepsSelectionAndSettleClock() {
        _ = NSApplication.shared
        let (c, _, defaults, suite) = controller()
        defer { c.hide(); defaults.removePersistentDomain(forName: suite) }
        var t: CFAbsoluteTime = 10
        c.presentForTesting([cand("một"), cand("mới")], anchor: anchor, clock: { t })
        t += 0.2
        c.presentForTesting([cand("một"), cand("mới")], anchor: anchor, clock: { t })
        t += 0.06
        XCTAssertEqual(c.handleListKey(.tab), .accept(0), "an unchanged refresh must not restart the settle time")
    }

    func testRowBoldsOnlyWhatTheSuggestionAdds() {
        let row = CandidatePanelController.attributedRow(cand("chương trình", typed: 4))
        XCTAssertEqual(row.string, "chương trình")
        let regular = row.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let bold = row.attribute(.font, at: 4, effectiveRange: nil) as? NSFont
        XCTAssertFalse(regular?.fontDescriptor.symbolicTraits.contains(.bold) ?? true)
        XCTAssertNotEqual(regular, bold)
        let after = CandidatePanelController.attributedRow(cand("bạn nhiều"))
        XCTAssertEqual(after.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, bold)
    }

    func testAnyOtherKeyVoidsTheRowPickedBeforeIt() {
        _ = NSApplication.shared
        let (c, _, defaults, suite) = controller()
        defer { c.hide(); defaults.removePersistentDomain(forName: suite) }
        c.presentForTesting([cand("một"), cand("mới")], anchor: anchor, clock: { 0 })
        _ = c.handleListKey(.down)
        XCTAssertEqual(c.selectedIndex, 0)
        c.clearSelection() // e.g. ⌫ or ⌃⌫ restore reached the tap
        XCTAssertNil(c.selectedIndex)
        XCTAssertEqual(c.handleListKey(.enter), .passAndHide, "Enter after an edit must stay an Enter")
    }

    func testListKeyCodesMatchTheKeysTheTapMaps() {
        XCTAssertEqual(PredictionController.listKeyCodes, [0x7D, 0x7E, 0x30, 0x24, 0x4C, 0x35])
    }
}
