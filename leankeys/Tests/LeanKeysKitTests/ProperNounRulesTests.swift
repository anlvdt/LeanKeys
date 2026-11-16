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
        XCTAssertEqual(data.sureSurnames.sorted(), ["huỳnh", "nguyễn", "quách", "trịnh"])
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
        XCTAssertEqual(cap(["Lê", "thuỷ"]), expect(2, ["Lê", "Thuỷ"]))
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
        XCTAssertEqual(cap(["trần", "thị"]), expect(2, ["Trần", "Thị"]))
        // A given name follows only a surname already capitalised on screen, or an always-capitalised one.
        XCTAssertNil(cap(["lê", "hùng"]))
        XCTAssertEqual(cap(["Lê", "hùng"]), expect(2, ["Lê", "Hùng"]))
        XCTAssertEqual(cap(["nguyễn", "an"]), expect(2, ["Nguyễn", "An"]))
        XCTAssertEqual(cap(["Trần", "Văn", "an"]), expect(1, ["An"]))
        XCTAssertNil(cap(["Nguyễn", "đi"]))
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
