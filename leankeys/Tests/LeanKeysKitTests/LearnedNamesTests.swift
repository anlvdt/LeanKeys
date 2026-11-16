import Foundation
import XCTest
@testable import LeanKeysKit

/// Keeps the plaintext the store is handed. Saves arrive on the names' private queue, hence the lock.
private final class InMemoryStore: LearnStore {
    private let lock = NSLock()
    private var data: Data?
    private(set) var saves = 0

    var saved: Data? { lock.withLock { data } }
    func load() throws -> Data? { lock.withLock { data } }
    func save(_ data: Data) throws { lock.withLock { self.data = data; saves += 1 } }
    func erase() throws { lock.withLock { data = nil } }
}

/// A clock that moves one second per reading, so every observation has its own `lastUsed`.
private final class Clock {
    private var t = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date {
        t = t.addingTimeInterval(1)
        return t
    }
}

final class LearnedNamesTests: XCTestCase {
    private static let titles: Set<String> = Set(ProperNounData.bundled.titles)
    private static let key = Data(repeating: 7, count: 32)
    private var clock: Clock!

    override func setUp() { clock = Clock() }

    /// The fake dictionary sees ASCII-folded letters ("hung", "store"); everything is a word except `nonWords`.
    private func names(_ store: LearnStore? = nil, nonWords: Set<String> = ["shopee"]) -> LearnedNames {
        LearnedNames(store: store, hmacKey: Self.key, titles: Self.titles,
                     isDictionaryWord: { !nonWords.contains($0) }, now: { [clock] in clock!.now() })
    }

    func testThresholdAfterTitle() {
        XCTAssertTrue(Self.titles.contains("anh"))
        let n = names()
        n.observe(word: "Hùng", previous: "anh")
        XCTAssertNil(n.name(after: "anh", word: "hùng"), "one observation is below the threshold")
        XCTAssertTrue(n.names.isEmpty)
        n.observe(word: "Hùng", previous: "anh")
        XCTAssertEqual(n.name(after: "anh", word: "hùng"), "Hùng")
        XCTAssertNil(n.name(after: "ăn", word: "hùng"), "a dictionary word is learned after a title only")
        XCTAssertNil(n.name(after: nil, word: "hùng"))
        XCTAssertEqual(n.names.map(\.form), ["Hùng"])
        XCTAssertEqual(n.names.first?.afterTitleOnly, true)
        XCTAssertEqual(n.names.first?.count, 2)
    }

    func testDictionaryWordOutsideTitleDoesNotCount() {
        let n = names()
        n.observe(word: "Hùng", previous: "anh")
        n.observe(word: "Hùng", previous: "ăn")
        XCTAssertNil(n.name(after: "anh", word: "hùng"), "only observations after a title count for a word")
    }

    func testAnywhereForNonDictionaryWords() {
        let n = names()
        n.observe(word: "Shopee", previous: "mua")
        n.observe(word: "Shopee", previous: nil)
        XCTAssertEqual(n.name(after: nil, word: "shopee"), "Shopee")
        XCTAssertEqual(n.name(after: "trên", word: "shopee"), "Shopee")
        XCTAssertEqual(n.name(after: "anh", word: "shopee"), "Shopee")
        XCTAssertEqual(n.names.first?.afterTitleOnly, false)
    }

    func testFoldsBeforeTheDictionaryCheck() {
        var seen: [String] = []
        let n = LearnedNames(store: nil, hmacKey: Self.key, titles: Self.titles,
                             isDictionaryWord: { seen.append($0); return true })
        n.observe(word: "Đường", previous: "anh")
        XCTAssertEqual(seen, ["duong"])
    }

    func testDictionaryWordNotAnywhere() {
        let n = names()
        n.observe(word: "Store", previous: "app")
        n.observe(word: "Store", previous: "app")
        XCTAssertNil(n.name(after: nil, word: "store"))
        XCTAssertNil(n.name(after: "app", word: "store"))
        XCTAssertTrue(n.names.isEmpty)
    }

    func testRejects() {
        let n = names(nonWords: ["fomo", "a", "shopee"])
        for _ in 0..<3 {
            n.observe(word: "FOMO", previous: "anh")
            n.observe(word: "A", previous: "anh")
            n.observe(word: "shopee", previous: "anh")
        }
        XCTAssertNil(n.name(after: "anh", word: "fomo"), "all caps")
        XCTAssertNil(n.name(after: "anh", word: "a"), "one letter")
        XCTAssertNil(n.name(after: "anh", word: "shopee"), "typed without a capital")
        XCTAssertTrue(n.names.isEmpty)
    }

    func testUndoneTwiceRemoves() {
        let n = names()
        n.undone(word: "shopee")
        n.observe(word: "Shopee", previous: nil)
        n.observe(word: "Shopee", previous: nil)
        XCTAssertEqual(n.name(after: nil, word: "shopee"), "Shopee", "an undo before learning does not count")
        n.undone(word: "shopee")
        XCTAssertEqual(n.name(after: nil, word: "shopee"), "Shopee", "one undo keeps the name")
        n.undone(word: "Shopee")
        XCTAssertNil(n.name(after: nil, word: "shopee"), "the second undo removes it")
        XCTAssertTrue(n.names.isEmpty)
        n.observe(word: "Shopee", previous: nil)
        XCTAssertNil(n.name(after: nil, word: "shopee"), "relearning starts from zero")
    }

    func testLRU() {
        let words = (0...LearnedNames.capacity).map { "Name\($0)" }
        let n2 = LearnedNames(store: nil, hmacKey: Self.key, titles: Self.titles,
                              isDictionaryWord: { _ in false }, now: { [clock] in clock!.now() })
        for word in words {
            n2.observe(word: word, previous: nil)
            n2.observe(word: word, previous: nil)
        }
        XCTAssertEqual(n2.names.count, 2_000)
        XCTAssertNil(n2.name(after: nil, word: "name0"), "the least recently used goes first")
        XCTAssertEqual(n2.name(after: nil, word: "name2000"), "Name2000")
        XCTAssertEqual(n2.names.first?.form, "Name2000", "most recent first")
    }

    func testLookupKeepsANameFresh() {
        let n = LearnedNames(store: nil, hmacKey: Self.key, titles: Self.titles,
                             isDictionaryWord: { _ in false }, now: { [clock] in clock!.now() })
        for word in (0..<LearnedNames.capacity).map({ "Name\($0)" }) {
            n.observe(word: word, previous: nil)
            n.observe(word: word, previous: nil)
        }
        XCTAssertEqual(n.name(after: nil, word: "name0"), "Name0")
        n.observe(word: "Extra", previous: nil)
        n.observe(word: "Extra", previous: nil)
        XCTAssertEqual(n.name(after: nil, word: "name0"), "Name0", "a lookup counts as use")
        XCTAssertNil(n.name(after: nil, word: "name1"))
    }

    func testBelowThresholdNotStoredInClear() throws {
        let store = InMemoryStore()
        let n = names(store)
        n.observe(word: "Hùng", previous: "anh")
        n.flush()
        XCTAssertGreaterThan(store.saves, 0)
        let saved = try XCTUnwrap(store.saved)
        for text in ["Hùng", "hùng", "hung", "Hung"] {
            XCTAssertNil(saved.range(of: Data(text.utf8)), "\(text) must not be saved in clear")
            XCTAssertNil(saved.range(of: Data(text.decomposedStringWithCanonicalMapping.utf8)))
        }
        n.observe(word: "Hùng", previous: "anh")
        n.flush()
        XCTAssertNotNil(store.saved?.range(of: Data("Hùng".utf8)), "a learned name is saved with its form")
    }

    func testDecomposedInputMatches() {
        let n = names()
        n.observe(word: "Hùng".decomposedStringWithCanonicalMapping, previous: "anh")
        n.observe(word: "Hùng", previous: "anh")
        XCTAssertEqual(n.name(after: "anh", word: "hùng".decomposedStringWithCanonicalMapping), "Hùng")
    }

    func testPersists() {
        let store = InMemoryStore()
        let first = names(store)
        first.observe(word: "Shopee", previous: nil)
        first.observe(word: "Shopee", previous: nil)
        first.observe(word: "Hùng", previous: "anh")
        first.undone(word: "shopee")
        first.flush()

        let second = names(store)
        XCTAssertEqual(second.names, first.names)
        XCTAssertEqual(second.name(after: nil, word: "shopee"), "Shopee")
        XCTAssertNil(second.name(after: "anh", word: "hùng"))
        second.observe(word: "Hùng", previous: "chị")
        XCTAssertEqual(second.name(after: "anh", word: "hùng"), "Hùng", "the hidden count survives a reload")
        second.undone(word: "shopee")
        XCTAssertNil(second.name(after: nil, word: "shopee"), "the undo count survives a reload")

        // A different HMAC key matches no saved digest.
        second.flush()
        let otherKey = LearnedNames(store: store, hmacKey: Data(repeating: 9, count: 32), titles: Self.titles,
                                    isDictionaryWord: { _ in true })
        otherKey.observe(word: "Lan", previous: "chị")
        XCTAssertNil(otherKey.name(after: "chị", word: "lan"))

        // Memory only.
        let none = names(nil)
        none.observe(word: "Shopee", previous: nil)
        none.observe(word: "Shopee", previous: nil)
        none.flush()
        XCTAssertTrue(names(nil).names.isEmpty)
    }

    func testRemoveAndRemoveAll() {
        let store = InMemoryStore()
        let n = names(store, nonWords: ["shopee", "tiki"])
        for word in ["Shopee", "Tiki"] {
            n.observe(word: word, previous: nil)
            n.observe(word: word, previous: nil)
        }
        n.observe(word: "Lan", previous: "chị")
        let shopee = try! XCTUnwrap(n.names.first { $0.form == "Shopee" })
        n.remove(shopee)
        XCTAssertNil(n.name(after: nil, word: "shopee"))
        XCTAssertEqual(n.names.map(\.form), ["Tiki"])
        n.removeAll()
        XCTAssertTrue(n.names.isEmpty)
        n.observe(word: "Lan", previous: "chị")
        XCTAssertNil(n.name(after: "chị", word: "lan"), "removeAll forgets hidden counts too")
        n.flush()
        XCTAssertTrue(names(store).names.isEmpty)
    }

    func testRealDictionaryCheck() {
        XCTAssertEqual(LearnedNames.asciiFolded("Đường"), "duong")
        XCTAssertTrue(LearnedNames.isDictionaryWord("store"))
        XCTAssertTrue(LearnedNames.isDictionaryWord(LearnedNames.asciiFolded("Hùng")))
        XCTAssertFalse(LearnedNames.isDictionaryWord("shopee"))
        XCTAssertFalse(LearnedNames.isDictionaryWord("chatgpt"))
    }

    func testOnChangeOnMainQueue() {
        let n = names()
        let changed = expectation(description: "onChange")
        changed.assertForOverFulfill = false
        n.onChange = {
            XCTAssertTrue(Thread.isMainThread)
            changed.fulfill()
        }
        DispatchQueue.global().async {
            n.observe(word: "Shopee", previous: nil)
            n.observe(word: "Shopee", previous: nil)
        }
        wait(for: [changed], timeout: 5)
    }
}
