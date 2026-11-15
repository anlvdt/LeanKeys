import XCTest
@testable import LeanKeysKit

private func candidate(_ text: String, _ kind: PhraseKind) -> Candidate {
    Candidate(id: "id", text: text, kind: kind, count: 5)
}

private let noWords: (String) -> Bool = { _ in false }

final class AbbreviationTests: XCTestCase {
    func testKindDefaults() {
        XCTAssertEqual(Abbreviation.suggest(for: candidate("0901234567", .phone), existing: [], isRealWord: noWords), "sdt")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("0312345678", .taxCode), existing: [], isRealWord: noWords), "mst")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("12 Lê Lợi, Quận 1", .address), existing: [], isRealWord: noWords), "dc")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("an@example.com", .email), existing: [], isRealWord: noWords), "em")
    }

    /// The fixed names are the spec's own: "dc" scores as an English word (DC) but stays "dc".
    func testKindDefaultsWithVikey() {
        XCTAssertEqual(Abbreviation.suggest(for: candidate("0901234567", .phone), existing: []), "sdt")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("0312345678", .taxCode), existing: []), "mst")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("12 Lê Lợi, Quận 1", .address), existing: []), "dc")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("an@example.com", .email), existing: []), "eml")
    }

    /// Ruling R1: every word's first letter, unaccented and lowercase; đ is d. The ruling writes the example as
    /// "caacdqt", but its rule gives c(ảm) o(ơn) a(nh) c(hị) d(ã) q(uan) t(âm): "coacdqt".
    func testInitials() {
        XCTAssertEqual(Abbreviation.suggest(for: candidate("Cảm ơn anh chị đã quan tâm", .phrase), existing: [],
                                            isRealWord: noWords), "coacdqt")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("Đường Ưu Đãi", .phrase), existing: [], isRealWord: noWords), "dud")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("  “Xin chào”,  (bạn) ", .phrase), existing: [],
                                            isRealWord: noWords), "xcb")
    }

    func testNumbering() {
        XCTAssertEqual(Abbreviation.suggest(for: candidate("0901234567", .phone), existing: ["sdt"], isRealWord: noWords), "sdt2")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("0901234567", .phone), existing: ["sdt", "sdt2"],
                                            isRealWord: noWords), "sdt3")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("Cảm ơn anh chị đã quan tâm", .phrase), existing: ["coacdqt"],
                                            isRealWord: noWords), "coacdqt2")
    }

    func testAbbreviationSkipsRealWords() {
        let words: Set<String> = ["em", "cam", "cam2"]
        let isWord: (String) -> Bool = { words.contains($0) }
        XCTAssertEqual(Abbreviation.suggest(for: candidate("an@example.com", .email), existing: [], isRealWord: isWord), "eml")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("an@example.com", .email), existing: ["eml"], isRealWord: isWord), "eml2")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("Chúc anh mạnh", .phrase), existing: [], isRealWord: isWord), "cam3")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("Chúc anh may", .phrase), existing: ["cam3"], isRealWord: isWord), "cam4")
    }

    func testIsRealWordUsesVikey() {
        XCTAssertTrue(Abbreviation.isRealWord("the"))      // English
        XCTAssertTrue(Abbreviation.isRealWord("khong"))    // Vietnamese, unaccented
        XCTAssertTrue(Abbreviation.isRealWord("em"))
        XCTAssertTrue(Abbreviation.isRealWord("The"))
        XCTAssertFalse(Abbreviation.isRealWord("sdt"))
        XCTAssertFalse(Abbreviation.isRealWord("mst"))
        XCTAssertFalse(Abbreviation.isRealWord("eml"))
        XCTAssertFalse(Abbreviation.isRealWord("coacdqt"))
        XCTAssertFalse(Abbreviation.isRealWord("caacdqt"))
        XCTAssertFalse(Abbreviation.isRealWord(""))
        XCTAssertFalse(Abbreviation.isRealWord("sdt2"))
    }
}
