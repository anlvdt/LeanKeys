import XCTest
@testable import LeanKeysKit

/// Display rules from the research report (2026-11-28): show only rows likely to pay back a glance.
final class SuggestionGateTests: XCTestCase {
    private func q(_ prev: [String], _ cur: String) -> PredictionQuery {
        PredictionQuery(previousWords: prev, currentWord: cur, followsNonSpaceBreak: false,
                        atWordStartAfterSpace: cur.isEmpty, isVietnamese: true)
    }
    private func row(_ text: String, typed: Int, personal: Bool = false, kind: PredictionKind = .word) -> PredictionCandidate {
        PredictionCandidate(id: text, display: text, insertion: text + " ", deleteCount: typed, kind: kind, score: 1,
                            isPersonal: personal)
    }

    func testTelexKeyCounts() {
        XCTAssertEqual(SuggestionGate.telexKeys("được"), 7) // d d u o w j c
        XCTAssertEqual(SuggestionGate.telexKeys("cảm ơn"), 8) // c a m r ␣ o w n
        XCTAssertEqual(SuggestionGate.telexKeys("thư"), 4) // t h u w
    }

    func testKeysSavedCountsTelexKeysLeftMinusTab() {
        // "đa" typed, "đang " left = n g space: 3 keys, minus Tab = 2; "đan " left = n space: 1.
        XCTAssertEqual(SuggestionGate.keysSaved(row("đang", typed: 2), typed: "đa"), 2)
        XCTAssertEqual(SuggestionGate.keysSaved(row("đan", typed: 2), typed: "đa"), 1)
        XCTAssertGreaterThanOrEqual(SuggestionGate.keysSaved(row("được", typed: 2), typed: "đư"), 3)
    }

    func testWordStartKeepsOnlyLearnedPhrases() {
        let rows = SuggestionGate.apply([row("ơn", typed: 0), row("báo cáo tiến độ nhé", typed: 0, personal: true, kind: .phrase),
                                         row("bạn", typed: 0, personal: true)],
                                        phase: .next, query: q(["em", "gửi"], ""))
        XCTAssertEqual(rows.map(\.display), ["báo cáo tiến độ nhé"])
    }

    func testLookAheadRowsNeedToBeLearned() {
        let rows = SuggestionGate.apply([row("cảm ơn", typed: 3, kind: .phrase), row("cảm ơn anh chị nhiều", typed: 3, personal: true, kind: .sentence),
                                         row("cảnh báo", typed: 3, kind: .phrase)],
                                        phase: .ahead, query: q([], "cảm"))
        XCTAssertEqual(rows.map(\.display), ["cảm ơn anh chị nhiều", "cảnh báo"])
    }

    func testShortSavingsDroppedAndAtMostTwoRows() {
        let rows = SuggestionGate.apply([row("đưa", typed: 2), row("được", typed: 2), row("đường", typed: 2), row("điện thoại", typed: 2, kind: .phrase)],
                                        phase: .mid, query: q([], "đư"))
        XCTAssertFalse(rows.contains { $0.display == "đưa" }, "đưa saves 1 key (a, space, minus Tab)")
        XCTAssertEqual(rows.count, SuggestionGate.maxRows)
    }

    func testOneLetterShowsOnlyLearnedPhrases() {
        let rows = SuggestionGate.apply([row("được", typed: 1), row("đi làm về muộn", typed: 1, personal: true, kind: .sentence)],
                                        phase: .mid, query: q([], "đ"))
        XCTAssertEqual(rows.map(\.display), ["đi làm về muộn"])
    }

    func testShortcutsAlwaysPass() {
        let sc = PredictionCandidate(id: "sc:ko", display: "ko → không", insertion: "không ", deleteCount: 2, kind: .shortcut, score: 260)
        XCTAssertEqual(SuggestionGate.apply([sc], phase: .mid, query: q([], "ko")).count, 1)
    }
}
