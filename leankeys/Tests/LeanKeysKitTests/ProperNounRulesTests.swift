import XCTest
@testable import LeanKeysKit

/// Answers only "Hùng" after "anh", like a learned "after a title" name.
private struct FakeLookup: LearnedNameLookup {
    func name(after previous: String?, word: String) -> String? {
        previous == "anh" && word == "hùng" ? "Hùng" : nil
    }
}

final class ProperNounRulesTests: XCTestCase {
    private let rules = ProperNounRules()

    private func cap(_ words: [String]) -> Capitalization? { rules.capitalization(for: words) }
    private func expect(_ count: Int, _ words: [String]) -> Capitalization {
        Capitalization(wordCount: count, words: words)
    }

    func testBundledDataLoads() {
        let data = ProperNounData.bundled
        XCTAssertTrue(data.places.contains("Hà Nội"))
        XCTAssertTrue(data.places.contains("Thừa Thiên Huế"))
        XCTAssertFalse(data.singleWords.contains("Tết"), "the corpus writes it lowercase too (spec 17.1.1)")
        XCTAssertTrue(data.surnames.contains("nguyễn"))
        XCTAssertTrue(data.givenNames.contains("hùng"))
        XCTAssertTrue(data.ambiguousPlaces.contains("hòa bình"))
        XCTAssertTrue(data.placeCues.contains("thành phố"))
        XCTAssertEqual(data.sureSurnames, ["nguyễn"], "ruling R11: quách, trịnh, huỳnh are ordinary words too")
        XCTAssertTrue(data.surnames.contains("quách"))
        XCTAssertFalse(data.placeCues.contains("về"), "ruling R11: \"bàn về hòa bình\"")
        XCTAssertEqual(data.placeNotAfter["nhật bản"], ["cập"])
        XCTAssertEqual(Set(data.placeCues), ["tỉnh", "thành phố", "tp", "ở", "tại", "quê", "người"],
                       "ruling R15: strong cues only, no motion verbs")
        XCTAssertEqual(data.givenNameNotAfter["quốc"], ["vương"])
    }

    func testPlaces() {
        XCTAssertEqual(cap(["tôi", "ở", "hà", "nội"]), expect(2, ["Hà", "Nội"]))
        XCTAssertEqual(cap(["thừa", "thiên", "huế"]), expect(3, ["Thừa", "Thiên", "Huế"]))
        XCTAssertEqual(cap(["huế"]), expect(1, ["Huế"]))
        XCTAssertNil(cap(["ăn", "tết"]))
        XCTAssertEqual(cap(["hồ", "chí", "minh"]), expect(3, ["Hồ", "Chí", "Minh"]))
    }

    /// Either tone placement matches; the result keeps the user's own placement.
    func testTonePlacementIgnored() {
        XCTAssertEqual(cap(["khánh", "hoà"]), expect(2, ["Khánh", "Hoà"]))
        XCTAssertEqual(cap(["khánh", "hòa"]), expect(2, ["Khánh", "Hòa"]))
        XCTAssertEqual(cap(["biên", "hoà"]), expect(2, ["Biên", "Hoà"]))
        // "thanh hóa" is an ambiguous place, so it needs a cue in either spelling.
        XCTAssertEqual(cap(["ở", "thanh", "hoá"]), expect(2, ["Thanh", "Hoá"]))
        XCTAssertEqual(cap(["ở", "thanh", "hóa"]), expect(2, ["Thanh", "Hóa"]))
        XCTAssertNil(cap(["thanh", "hoá"]))
        XCTAssertNil(cap(["thanh", "hóa"]))
        // Names too: "thuỷ" is the given name "thủy".
        XCTAssertEqual(cap(["gặp", "Lê", "thuỷ"]), expect(2, ["Lê", "Thuỷ"]))
    }

    func testAmbiguousNeedsCue() {
        XCTAssertNil(cap(["hòa", "bình"]))
        XCTAssertEqual(cap(["ở", "hòa", "bình"]), expect(2, ["Hòa", "Bình"]))
        XCTAssertEqual(cap(["thành", "phố", "hòa", "bình"]), expect(2, ["Hòa", "Bình"]))
    }

    func testNames() {
        XCTAssertEqual(cap(["nguyễn"]), expect(1, ["Nguyễn"]))
        XCTAssertEqual(cap(["Nguyễn", "văn"]), expect(2, ["Nguyễn", "Văn"]))
        XCTAssertEqual(cap(["Nguyễn", "Văn", "tèo"]), expect(1, ["Tèo"]))
        XCTAssertEqual(cap(["gặp", "Trần", "thị"]), expect(2, ["Trần", "Thị"]))
        // A given name follows only a surname already capitalised on screen, or an always-capitalised one.
        XCTAssertNil(cap(["lê", "hùng"]))
        XCTAssertEqual(cap(["gặp", "Lê", "hùng"]), expect(2, ["Lê", "Hùng"]))
        XCTAssertEqual(cap(["nguyễn", "an"]), expect(2, ["Nguyễn", "An"]))
        XCTAssertEqual(cap(["Trần", "Văn", "an"]), expect(1, ["An"]))
        XCTAssertNil(cap(["Nguyễn", "đi"]))
    }

    /// Ruling R11 (a): the phrase's first word is capitalised as sentence case, so its capital is no name cue;
    /// a sure surname still is.
    func testPhraseInitialCapitalIsNoCue() {
        XCTAssertNil(cap(["Mai", "anh"]))
        XCTAssertNil(cap(["Lương", "tâm"]))
        XCTAssertNil(cap(["Thái", "bình"]))
        XCTAssertNil(cap(["Vương", "quốc"]))
        XCTAssertNil(cap(["Cao", "minh"]))
        XCTAssertNil(cap(["Lê", "Văn", "Hùng", "đi"]))
        // Not the phrase's first word (after a comma, say): the user's capital is a cue.
        XCTAssertEqual(rules.capitalization(for: ["Mai", "anh"], firstWordStartsPhrase: false),
                       expect(2, ["Mai", "Anh"]))
        XCTAssertEqual(cap(["gặp", "Mai", "anh"]), expect(2, ["Mai", "Anh"]))
        // A sure surname is a name wherever it stands.
        XCTAssertEqual(cap(["Nguyễn", "Anh", "tuấn"]), expect(1, ["Tuấn"]))
        XCTAssertEqual(cap(["Nguyễn", "an"]), expect(2, ["Nguyễn", "An"]))
    }

    /// Ruling R11 (b): a middle name follows only a sure surname or a capitalised (not phrase-initial) surname.
    func testMiddleNameNeedsSureSurnameOrCapital() {
        XCTAssertNil(cap(["lưu", "văn"]))
        XCTAssertNil(cap(["lưu", "văn", "bản"]))
        XCTAssertNil(cap(["Lưu", "văn"]))
        XCTAssertNil(cap(["trần", "thị"]))
        XCTAssertEqual(cap(["nguyễn", "văn"]), expect(2, ["Nguyễn", "Văn"]))
        XCTAssertEqual(cap(["gặp", "Lưu", "văn"]), expect(2, ["Lưu", "Văn"]))
    }

    /// Ruling R11 (c), (d), (e).
    func testOrdinaryPhrasesStayLowercase() {
        let sentences: [[String]] = [
            ["bỏ", "quách", "đi"], ["xong", "quách"], ["rất", "trịnh", "trọng"], ["đèn", "huỳnh", "quang"],
            ["cập", "nhật", "bản", "mới"], ["hiệp", "hội", "an", "ninh"], ["xã", "hội", "an", "toàn"],
            ["đại", "hội", "an", "toàn"], ["quốc", "hội", "an", "tâm"], ["đoàn", "hội", "an"], ["học", "hội", "an"],
            ["nội", "hội", "an"], ["lễ", "hội", "an", "toàn"], ["cơ", "hội", "an", "cư"], ["bàn", "về", "hòa", "bình"],
        ]
        for words in sentences {
            for n in 1...words.count {
                XCTAssertNil(cap(Array(words.prefix(n))), "\(words.prefix(n))")
            }
        }
        // The same places keep their capitals elsewhere.
        XCTAssertEqual(cap(["sang", "nhật", "bản"]), expect(2, ["Nhật", "Bản"]))
        XCTAssertEqual(cap(["đi", "hội", "an"]), expect(2, ["Hội", "An"]))
        XCTAssertEqual(cap(["ở", "hòa", "bình"]), expect(2, ["Hòa", "Bình"]))
        XCTAssertEqual(cap(["gặp", "Quách", "tuấn"]), expect(2, ["Quách", "Tuấn"]), "a capitalised surname still")
    }

    /// Ruling R15: an ambiguous place takes a strong cue only, never a motion verb; "vương quốc" is a common noun.
    func testStrongCuesAndVuongQuoc() {
        for verb in ["đến", "đi", "từ", "ra", "vào", "về"] {
            XCTAssertNil(cap([verb, "hòa", "bình"]), verb)
            XCTAssertNil(cap(["đi", verb, "thái", "bình"]), verb)
        }
        for cue in [["tỉnh"], ["thành", "phố"], ["tp"], ["ở"], ["tại"], ["quê"], ["người"]] {
            XCTAssertEqual(cap(cue + ["thái", "bình"]), expect(2, ["Thái", "Bình"]), "\(cue)")
        }
        // Unambiguous places still follow anything.
        XCTAssertEqual(cap(["đi", "đến", "hà", "nội"]), expect(2, ["Hà", "Nội"]))
        XCTAssertNil(cap(["sống", "ở", "Vương", "quốc"]))
        XCTAssertNil(cap(["sống", "ở", "vương", "quốc"]))
        XCTAssertNil(cap(["sống", "ở", "Vương", "quốc", "Anh", "hùng"]))
        XCTAssertEqual(cap(["gặp", "Vương", "an"]), expect(2, ["Vương", "An"]), "other given names still follow")
    }

    /// Ruling R14 (M4): only the last few words are read, so a long run answers as a short one.
    func testLongRunReadsOnlyItsTail() {
        let filler = Array(repeating: "và", count: 300)
        XCTAssertEqual(cap(filler + ["thành", "phố", "hòa", "bình"]), expect(2, ["Hòa", "Bình"]))
        XCTAssertEqual(cap(filler + ["ở", "thừa", "thiên", "huế"]), expect(3, ["Thừa", "Thiên", "Huế"]))
        XCTAssertEqual(cap(filler + ["Trần", "Văn", "an"]), expect(1, ["An"]))
        XCTAssertNil(cap(filler + ["hòa", "bình"]))
        XCTAssertNil(cap(filler + ["cập", "nhật", "bản"]))
        // Cut to its tail, a long run's first word is no longer the phrase's first: "Mai" here is mid-phrase.
        XCTAssertEqual(cap(filler + ["Mai", "anh"]), expect(2, ["Mai", "Anh"]))
    }

    func testStaysLowercase() {
        XCTAssertNil(cap(["vi", "phạm"]))
        XCTAssertNil(cap(["khai", "trương"]))
        let peace = ["hòa", "bình", "thế", "giới"]
        for n in 1...peace.count {
            XCTAssertNil(cap(Array(peace.prefix(n))), "at word \(n)")
        }
        XCTAssertNil(cap(["anh", "hùng"]))
    }

    func testKeepsUserCapitals() {
        XCTAssertEqual(cap(["Hà", "nội"]), expect(2, ["Hà", "Nội"]))
        XCTAssertNil(cap(["Hà", "Nội"]))
        XCTAssertNil(cap(["iphone"]))
        XCTAssertNil(cap(["iPhone"]))
        XCTAssertNil(cap(["NGUYỄN"]))
    }

    func testLearnedLookupUsed() {
        let learned = ProperNounRules(learned: FakeLookup())
        XCTAssertEqual(learned.capitalization(for: ["anh", "hùng"]), expect(1, ["Hùng"]))
        XCTAssertNil(learned.capitalization(for: ["ăn", "hùng"]))
    }
}

/// Ruling R11 through `AutoCapitalizer`: whole sentences as people type them, sentence-initial capital included,
/// committed word by word as the router commits them.
final class AutoCapitalizerSentenceTests: XCTestCase {
    private let capitalizer = AutoCapitalizer(learned: nil)

    /// Types `sentence` word by word; after each word (before the break after it) applies any capitalisation.
    private func retype(_ sentence: String) -> String {
        var text = ""
        for ch in sentence {
            if !TextMirror.isWordCharacter(ch), let last = text.last, TextMirror.isWordCharacter(last),
               let made = capitalizer.replacement(phraseText: text, keepsLowercase: { _, _ in false }) {
                XCTAssertTrue(text.hasSuffix(made.original))
                text = String(text.dropLast(made.original.count)) + made.capitalized
            }
            text.append(ch)
        }
        return text
    }

    func testOrdinarySentencesGetNoCapitals() {
        for sentence in [
            "Mai anh đi đâu thế?", "Lương tâm không cho phép.", "Vương quốc Anh rời liên minh.",
            "Thái bình thì ai cũng mong.", "Em vừa cập nhật bản mới.", "Nhớ lưu văn bản nhé.", "Thôi bỏ quách đi.",
            "Anh ấy rất trịnh trọng.", "Phòng dùng đèn huỳnh quang.", "Ông ấy ở hiệp hội an ninh mạng.",
            "Ai cũng muốn một xã hội an toàn.", "Chúng ta bàn về hòa bình.", "Anh ấy là anh hùng.",
            "Ừ, mai anh qua.", "Đi đến hòa bình cần kiên nhẫn.", "Tôi từng sống ở Vương quốc Anh vài năm.",
            "Họ đi từ vương quốc Anh sang.",
        ] {
            XCTAssertEqual(retype(sentence), sentence)
        }
    }

    func testNamesAndPlacesStillCapitalised() {
        XCTAssertEqual(retype("Hôm qua gặp nguyễn văn an ở hà nội."), "Hôm qua gặp Nguyễn Văn An ở Hà Nội.")
        XCTAssertEqual(retype("Gặp Trần thị lan chưa?"), "Gặp Trần Thị Lan chưa?")
        XCTAssertEqual(retype("Nguyễn anh tuấn đến rồi."), "Nguyễn Anh Tuấn đến rồi.")
        XCTAssertEqual(retype("Sang nhật bản chơi."), "Sang Nhật Bản chơi.")
        XCTAssertEqual(retype("Đi hội an không?"), "Đi Hội An không?")
    }
}
