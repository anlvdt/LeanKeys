import XCTest
@testable import LeanKeysKit

private func c(_ text: String, _ kind: PhraseKind = .phrase, count: Int = 5, days: Int = 3,
               id: String? = nil) -> Candidate {
    Candidate(id: id ?? text, text: text, kind: kind, count: count, days: days)
}

final class SuggestionRankingTests: XCTestCase {
    /// Telex keys: a letter is one key, đ two (dd), â ê ô ă ơ ư one more, a tone mark one more.
    func testTelexKeys() {
        XCTAssertEqual(SuggestionRanking.telexKeys("an"), 2)
        XCTAssertEqual(SuggestionRanking.telexKeys("ầ"), 3)        // a a f
        XCTAssertEqual(SuggestionRanking.telexKeys("đ"), 2)        // d d
        XCTAssertEqual(SuggestionRanking.telexKeys("ơ"), 2)        // o w
        XCTAssertEqual(SuggestionRanking.telexKeys("Ạ"), 2)        // a j, case ignored
        XCTAssertEqual(SuggestionRanking.telexKeys("dạ vâng ạ"), 12)
        XCTAssertEqual(SuggestionRanking.telexKeys("0912 345"), 8)
    }

    /// N2: short chat replies save a few keys a use; they are not worth a gõ tắt.
    func testShortPhrasesAreDropped() {
        let ranked = SuggestionRanking.rank([c("dạ vâng ạ"), c("ok em nhé"), c("em cảm ơn"),
                                             c("để em kiểm tra lại rồi báo anh sau")])
        XCTAssertEqual(ranked.map(\.text), ["để em kiểm tra lại rồi báo anh sau"])
        // 12, 13 and 14 keys a use: below the 15 the user chose.
        XCTAssertEqual(SuggestionRanking.rank([c("đúng rồi anh"), c("haha đúng rồi"), c("để em check lại")]), [])
    }

    /// N7: a phrase typed on one day only (a burst) is not suggested yet; numbers and emails keep the old rule.
    func testPhraseNeedsTwoDays() {
        let ranked = SuggestionRanking.rank([c("để em kiểm tra lại rồi báo anh sau", days: 1),
                                             c("0912 345 678", .phone, days: 1),
                                             c("an@vidu.vn", .email, days: 1)])
        XCTAssertEqual(Set(ranked.map(\.text)), ["0912 345 678", "an@vidu.vn"])
    }

    /// N3: most keys saved first, not most seen.
    func testRankedByKeysSaved() {
        let ranked = SuggestionRanking.rank([
            c("anh xem giúp em với nhé", count: 12),
            c("Mọi thắc mắc xin liên hệ phòng kế toán công ty", count: 6),
        ])
        XCTAssertEqual(ranked.map(\.text), ["mọi thắc mắc xin liên hệ phòng kế toán công ty", "anh xem giúp em với nhé"])
    }

    /// N1/N6: of overlapping candidates (one holds the other's words) one shows: a recognised piece before a phrase
    /// holding it, else the best. The rest stay counted.
    func testOverlapsHidden() {
        let ranked = SuggestionRanking.rank([
            c("an.nguyen@congty.vn", .email, count: 6),
            c("Email của em là an.nguyen@congty.vn", count: 6),
            c("Cảm ơn anh chị đã quan tâm", count: 20),
            c("dạ em cảm ơn anh chị đã quan tâm ạ", count: 7),
            c("Hẹn gặp lại anh chị vào tuần sau", count: 4),
        ])
        // The email wins over the sentence holding it, though the sentence scores higher; the order stays by score.
        XCTAssertEqual(ranked.map(\.text), ["cảm ơn anh chị đã quan tâm", "hẹn gặp lại anh chị vào tuần sau",
                                            "an.nguyen@congty.vn"])
    }

    /// Words, not letters: "anh" does not hold "an".
    func testOverlapIsByWholeWords() {
        let ranked = SuggestionRanking.rank([c("anh gửi lại file báo cáo giúp em"), c("an gửi lại file báo cáo giúp em")])
        XCTAssertEqual(ranked.count, 2)
    }

    /// A capital that only starts the sentence is dropped: the gõ tắt keeps the case of what is typed (both engines
    /// capitalise the result after a capitalised trigger). Names keep theirs.
    func testSentenceCapitalDropped() {
        XCTAssertEqual(SuggestionRanking.sentenceCaseStripped("Em gửi anh báo cáo tuần này"), "em gửi anh báo cáo tuần này")
        XCTAssertEqual(SuggestionRanking.sentenceCaseStripped("Trân trọng, Nguyễn Văn An"), "trân trọng, Nguyễn Văn An")
        XCTAssertEqual(SuggestionRanking.sentenceCaseStripped("Nguyễn Văn An"), "Nguyễn Văn An")
        XCTAssertEqual(SuggestionRanking.sentenceCaseStripped("OK anh nhé"), "OK anh nhé")
        XCTAssertEqual(SuggestionRanking.rank([c("0912 345 678", .phone)]).first?.text, "0912 345 678")
    }

    /// Ranking keeps the learner's id, so Thêm and Bỏ qua still reach the right entry.
    func testKeepsIDs() {
        let ranked = SuggestionRanking.rank([c("Em gửi anh báo cáo tuần này nhé", id: "abc")])
        XCTAssertEqual(ranked.first?.id, "abc")
    }
}
