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

    /// Ruling R1 as amended 2026-11-24: the first letters of the first words, unaccented and lowercase (đ is d),
    /// at most five of them. "Cảm ơn anh chị đã quan tâm" is coacd, not the seven-letter coacdqt.
    func testInitials() {
        XCTAssertEqual(Abbreviation.suggest(for: candidate("Cảm ơn anh chị đã quan tâm", .phrase), existing: [],
                                            isRealWord: noWords), "coacd")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("để em kiểm tra lại rồi báo anh sau", .phrase), existing: [],
                                            isRealWord: noWords), "dektl")
        XCTAssertEqual(Abbreviation.initials("Đường Ưu Đãi"), "dud")   // as a trigger, Telex types it đu (R15)
        XCTAssertEqual(Abbreviation.suggest(for: candidate("  “Xin chào”,  (bạn) ", .phrase), existing: [],
                                            isRealWord: noWords), "xcb")
        // Filler words are left out first.
        XCTAssertEqual(Abbreviation.suggest(for: candidate("Dạ em cảm ơn anh chị đã quan tâm ạ", .phrase), existing: [],
                                            isRealWord: noWords), "ecoac")
    }

    /// Initials that Telex would change ("ax" is ã) start one word later, still first letters of the phrase's words.
    func testTelexClashStartsLater() {
        XCTAssertEqual(Abbreviation.suggest(for: candidate("anh xem giúp em với", .phrase), existing: [],
                                            isRealWord: noWords), "xgev")
    }

    /// Ruling R17 as amended 2026-11-24: a phrase's trigger has at least three letters.
    func testPhraseTriggerHasThreeLetters() {
        let name = Abbreviation.suggest(for: candidate("Chúc anh", .phrase), existing: [], isRealWord: noWords)
        XCTAssertEqual(name, "cha")
    }

    /// A real word moves on to the next name, built from the phrase's own letters, before any number.
    func testAbbreviationSkipsRealWords() {
        let words: Set<String> = ["em", "eco", "cam"]
        let isWord: (String) -> Bool = { words.contains($0) }
        XCTAssertEqual(Abbreviation.suggest(for: candidate("an@example.com", .email), existing: [], isRealWord: isWord), "eml")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("an@example.com", .email), existing: ["eml"], isRealWord: isWord), "eml2")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("em cảm ơn", .phrase), existing: [], isRealWord: isWord), "emco")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("Chúc anh mạnh", .phrase), existing: [], isRealWord: isWord), "cham")
    }

    /// Teencode and rude words the user types themselves would expand every time: never offered.
    func testBlockedWords() {
        XCTAssertTrue(Abbreviation.isBlocked("ntn"))
        XCTAssertTrue(Abbreviation.isBlocked("cl"))
        XCTAssertTrue(Abbreviation.isBlocked("VCL"))
        XCTAssertFalse(Abbreviation.isBlocked("coacd"))
        XCTAssertEqual(Abbreviation.suggest(for: candidate("như thế nào", .phrase), existing: [], isRealWord: noWords), "nhtn")
    }

    /// A number goes on only once every name is taken; never letters that start no word of the phrase.
    func testNumbering() {
        XCTAssertEqual(Abbreviation.suggest(for: candidate("0901234567", .phone), existing: ["sdt"], isRealWord: noWords), "sdt2")
        XCTAssertEqual(Abbreviation.suggest(for: candidate("0901234567", .phone), existing: ["sdt", "sdt2"],
                                            isRealWord: noWords), "sdt3")
        let text = "Cảm ơn anh chị đã quan tâm"
        let thanks = candidate(text, .phrase)
        let names = Abbreviation.phraseNames(text)
        XCTAssertEqual(Array(names.prefix(3)), ["coacd", "coac", "coa"])
        XCTAssertTrue(names.allSatisfy { $0.count >= 3 && $0.count <= 6 }, "\(names)")
        XCTAssertEqual(Abbreviation.suggest(for: thanks, existing: ["coacd"], isRealWord: noWords), "coac")
        XCTAssertEqual(Abbreviation.suggest(for: thanks, existing: Set(names), isRealWord: noWords), "coacd2")
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
        // "Anh sẽ tới" is ast (á): the name moves to the phrase's own letters, at least three, never a vowel-less
        // two-letter name.
        let ast = Abbreviation.suggest(for: candidate("Anh sẽ tới", .phrase), existing: [], isRealWord: noWords)
        XCTAssertNotEqual(ast, "ast")
        XCTAssertGreaterThanOrEqual(ast.count, 3, ast)
        XCTAssertTrue(Abbreviation.typesAsIs(ast), ast)
    }

    /// Ruling R17 (amended 2026-11-24): at least three letters, also for a one-word phrase.
    func testOneWordPhrase() {
        let name = Abbreviation.suggest(for: candidate("Shopee", .phrase), existing: [], isRealWord: noWords)
        XCTAssertTrue(Abbreviation.typesAsIs(String(name.prefix { $0.isLetter })), name)
        XCTAssertEqual(name, "sho")
        let real = Abbreviation.suggest(for: candidate("Shopee", .phrase), existing: [])
        XCTAssertGreaterThanOrEqual(real.filter { $0.isLetter }.count, 3, real)
    }
}
