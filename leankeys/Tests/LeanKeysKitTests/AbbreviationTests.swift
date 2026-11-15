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
        XCTAssertEqual(Abbreviation.suggest(for: candidate("12 Lê Lợi, Quận 1", .address), existing: [], isRealWord: noWords), "dchi")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("an@example.com", .email), existing: [], isRealWord: noWords), "em")
    }

    /// Ruling R18: the address name is "dchi" ("dc" is chat shorthand for "được"). Fixed names skip the real-word check.
    func testKindDefaultsWithVikey() {
        XCTAssertEqual(Abbreviation.suggest(for: candidate("0901234567", .phone), existing: []), "sdt")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("0312345678", .taxCode), existing: []), "mst")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("12 Lê Lợi, Quận 1", .address), existing: []), "dchi")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("an@example.com", .email), existing: []), "eml")
    }

    /// Ruling R1: every word's first letter, unaccented and lowercase; đ is d. The ruling writes the example as
    /// "caacdqt", but its rule gives c(ảm) o(ơn) a(nh) c(hị) d(ã) q(uan) t(âm): "coacdqt".
    func testInitials() {
        XCTAssertEqual(Abbreviation.suggest(for: candidate("Cảm ơn anh chị đã quan tâm", .phrase), existing: [],
                                            isRealWord: noWords), "coacdqt")
        XCTAssertEqual(Abbreviation.initials("Đường Ưu Đãi"), "dud")   // as a trigger, Telex types it đu (R15)
        XCTAssertEqual(Abbreviation.suggest(for: candidate("  “Xin chào”,  (bạn) ", .phrase), existing: [],
                                            isRealWord: noWords), "xcb")
    }

    func testNumbering() {
        XCTAssertEqual(Abbreviation.suggest(for: candidate("0901234567", .phone), existing: ["sdt"], isRealWord: noWords), "sdt2")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("0901234567", .phone), existing: ["sdt", "sdt2"],
                                            isRealWord: noWords), "sdt3")
        // R15 order: initials, initials without vowels, first two consonants, then a number on the initials.
        let thanks = candidate("Cảm ơn anh chị đã quan tâm", .phrase)
        XCTAssertEqual(Abbreviation.suggest(for: thanks, existing: ["coacdqt"], isRealWord: noWords), "ccdqt")
        XCTAssertEqual(Abbreviation.suggest(for: thanks, existing: ["coacdqt", "ccdqt"], isRealWord: noWords), "cm")
        XCTAssertEqual(Abbreviation.suggest(for: thanks, existing: ["coacdqt", "ccdqt", "cm"], isRealWord: noWords),
                       "coacdqt2")
    }

    func testAbbreviationSkipsRealWords() {
        let words: Set<String> = ["em", "cam", "cam2"]
        let isWord: (String) -> Bool = { words.contains($0) }
        XCTAssertEqual(Abbreviation.suggest(for: candidate("an@example.com", .email), existing: [], isRealWord: isWord), "eml")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("an@example.com", .email), existing: ["eml"], isRealWord: isWord), "eml2")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("Chúc anh mạnh", .phrase), existing: [], isRealWord: isWord), "cm")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("Chúc anh mạnh", .phrase), existing: ["cm", "ch"], isRealWord: isWord), "cam3")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("Chúc anh may", .phrase), existing: ["cm", "ch", "cam3"],
                                            isRealWord: isWord), "cam4")
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

    func testTypesAsIs() {
        XCTAssertTrue(Abbreviation.typesAsIs("sdt"))
        XCTAssertTrue(Abbreviation.typesAsIs("dchi"))
        XCTAssertTrue(Abbreviation.typesAsIs("eml"))
        XCTAssertFalse(Abbreviation.typesAsIs("dd"))   // đ
        XCTAssertFalse(Abbreviation.typesAsIs("as"))   // á
        XCTAssertFalse(Abbreviation.typesAsIs("es"))   // é
        XCTAssertFalse(Abbreviation.typesAsIs("w"))    // ư
        XCTAssertFalse(Abbreviation.typesAsIs("aa"))   // â
        XCTAssertFalse(Abbreviation.typesAsIs(""))
        XCTAssertFalse(Abbreviation.typesAsIs("sdt2"))
    }

    /// Ruling R15: every suggestion types as itself in Telex.
    func testSuggestionsTypeAsThemselves() {
        for (text, bad) in [("Đi đâu", "dd"), ("Anh sẽ", "as"), ("Em sẽ", "es")] {
            let name = Abbreviation.suggest(for: candidate(text, .phrase), existing: [], isRealWord: noWords)
            XCTAssertNotEqual(name, bad, text)
            XCTAssertTrue(Abbreviation.typesAsIs(String(name.prefix { $0.isLetter })), "\(text) gave \(name)")
        }
        let w = Abbreviation.suggest(for: candidate("Xin wifi nhé", .phrase), existing: [], isRealWord: noWords)
        XCTAssertFalse(w.contains("w"), w)
        XCTAssertTrue(Abbreviation.typesAsIs(String(w.prefix { $0.isLetter })), w)
        // Consonant-only initials come before numbering: "Anh sẽ tới" is ast (á), then st.
        XCTAssertEqual(Abbreviation.suggest(for: candidate("Anh sẽ tới", .phrase), existing: [], isRealWord: noWords), "st")
    }

    /// Ruling R17: at least two letters, also for a one-word phrase.
    func testOneWordPhrase() {
        let name = Abbreviation.suggest(for: candidate("Shopee", .phrase), existing: [], isRealWord: noWords)
        XCTAssertGreaterThanOrEqual(name.filter { $0.isLetter }.count, 2, name)
        XCTAssertTrue(Abbreviation.typesAsIs(String(name.prefix { $0.isLetter })), name)
        XCTAssertEqual(name, "sh")
        let real = Abbreviation.suggest(for: candidate("Shopee", .phrase), existing: [])
        XCTAssertGreaterThanOrEqual(real.filter { $0.isLetter }.count, 2, real)
    }
}
