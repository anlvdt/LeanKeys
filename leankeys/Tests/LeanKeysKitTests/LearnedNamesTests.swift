import Foundation
import XCTest
@testable import LeanKeysKit

/// Keeps the plaintext the store is handed. Saves arrive on the names' private queue, hence the lock.
private final class InMemoryStore: LearnStore {
    private let lock = NSLock()
    private var data: Data?
    private var _saves = 0, _erased = 0

    init(_ data: Data? = nil) { self.data = data }

    var saved: Data? { lock.withLock { data } }
    var saves: Int { lock.withLock { _saves } }
    var erased: Int { lock.withLock { _erased } }
    func load() throws -> Data? { lock.withLock { data } }
    func save(_ data: Data) throws { lock.withLock { self.data = data; _saves += 1 } }
    func erase() throws { lock.withLock { data = nil; _erased += 1 } }
}

/// A clock that moves one second per reading, so every observation has its own `lastUsed`.
private final class Clock {
    private var t = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date {
        t = t.addingTimeInterval(1)
        return t
    }
}

/// "Name" plus `i` spelled in letters (0 → a … 9 → j): names carry no digits (fix round 1, R9).
private func letterName(_ i: Int) -> String {
    "Name" + String(String(i).map { Character(UnicodeScalar(UInt8(97) + UInt8(String($0))!)) })
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

    /// Audit item 4: the dictionary check (key thread, ruling R4) runs when the sighting is made; recording it later,
    /// on another queue, runs no check.
    func testSightingThenRecord() throws {
        var checks = 0
        let n = LearnedNames(store: nil, hmacKey: Self.key, titles: Self.titles,
                             isDictionaryWord: { _ in checks += 1; return false })
        XCTAssertNil(n.sighting(word: "FOMO", previous: nil), "not name-shaped")
        XCTAssertEqual(checks, 0)
        let sighting = try XCTUnwrap(n.sighting(word: "Shopee", previous: nil))
        XCTAssertEqual(checks, 1)
        XCTAssertTrue(n.names.isEmpty, "a sighting counts nothing by itself")
        n.record(sighting)
        n.record(sighting)
        XCTAssertEqual(checks, 1)
        XCTAssertEqual(n.name(after: nil, word: "shopee"), "Shopee")
        let dictionary = LearnedNames(store: nil, hmacKey: Self.key, titles: Self.titles, isDictionaryWord: { _ in true })
        XCTAssertNil(dictionary.sighting(word: "Store", previous: "app"), "a dictionary word away from a title")
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

    /// Fix round 1 (R9): a word with a digit or a symbol, or shaped like a secret, is never counted, not even
    /// hidden; a hyphenated name still is.
    func testSecretShapedWordsNeverLearned() {
        let store = InMemoryStore()
        let n = names(store, nonWords: ["matkhau2024", "abc@xyz", "ede", "ab-", "ab--cd"])
        for _ in 0..<3 {
            for word in ["Matkhau2024", "Abc@xyz", "Ab-", "Ab--cd", "-Ab"] {
                n.observe(word: word, previous: nil)
                n.observe(word: word, previous: "anh")
            }
        }
        n.flush()
        XCTAssertEqual(store.saves, 0, "nothing counted, not even a digest")
        XCTAssertNil(store.saved)
        for word in ["matkhau2024", "abc@xyz", "ab-", "ab--cd", "-ab"] {
            XCTAssertNil(n.name(after: nil, word: word), word)
            XCTAssertNil(n.name(after: "anh", word: word), word)
        }
        XCTAssertTrue(n.names.isEmpty)

        n.observe(word: "Ê-đê", previous: nil)
        n.observe(word: "Ê-đê", previous: nil)
        XCTAssertEqual(n.name(after: nil, word: "ê-đê"), "Ê-đê", "a hyphenated name is still learned")
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
        let words = (0...LearnedNames.capacity).map(letterName)
        let n2 = LearnedNames(store: nil, hmacKey: Self.key, titles: Self.titles,
                              isDictionaryWord: { _ in false }, now: { [clock] in clock!.now() })
        for word in words {
            n2.observe(word: word, previous: nil)
            n2.observe(word: word, previous: nil)
        }
        XCTAssertEqual(n2.names.count, 2_000)
        XCTAssertNil(n2.name(after: nil, word: "namea"), "the least recently used goes first")
        XCTAssertEqual(n2.name(after: nil, word: "namecaaa"), "Namecaaa")
        XCTAssertEqual(n2.names.first?.form, "Namecaaa", "most recent first")
    }

    func testLookupKeepsANameFresh() {
        let n = LearnedNames(store: nil, hmacKey: Self.key, titles: Self.titles,
                             isDictionaryWord: { _ in false }, now: { [clock] in clock!.now() })
        for word in (0..<LearnedNames.capacity).map(letterName) {
            n.observe(word: word, previous: nil)
            n.observe(word: word, previous: nil)
        }
        XCTAssertEqual(n.name(after: nil, word: "namea"), "Namea")
        n.markUsed(word: "namea")
        n.observe(word: "Extra", previous: nil)
        n.observe(word: "Extra", previous: nil)
        XCTAssertEqual(n.name(after: nil, word: "namea"), "Namea", "a capitalisation made with it counts as use")
        XCTAssertNil(n.name(after: nil, word: "nameb"))
    }

    /// Review M3: a lookup alone (which the rules or a cap: rule may still reject) does not count as use.
    func testLookupAloneIsNoUse() {
        let n = LearnedNames(store: nil, hmacKey: Self.key, titles: Self.titles,
                             isDictionaryWord: { _ in false }, now: { [clock] in clock!.now() })
        for word in ["Tiki", "Lazada"] {
            n.observe(word: word, previous: nil)
            n.observe(word: word, previous: nil)
        }
        XCTAssertEqual(n.names.map(\.form), ["Lazada", "Tiki"])
        XCTAssertEqual(n.name(after: nil, word: "tiki"), "Tiki")
        XCTAssertEqual(n.names.map(\.form), ["Lazada", "Tiki"], "unchanged by the lookup")
        n.markUsed(word: "tiki")
        XCTAssertEqual(n.names.map(\.form), ["Tiki", "Lazada"])
    }

    /// Review M2: after "Xoá tất cả" erased an unreadable file (and the store's HMAC key with it), hidden counts are
    /// digested with the store's new key, so they still match after a restart.
    func testRemoveAllTakesTheStoresNewKey() {
        final class KeyedStore: LearnStore, LearnKeyProvider {
            private let lock = NSLock()
            private var data: Data? = Data("not json".utf8)
            private var keyByte: UInt8 = 1
            func load() throws -> Data? { lock.withLock { data } }
            func save(_ data: Data) throws { lock.withLock { self.data = data } }
            func erase() throws { lock.withLock { data = nil; keyByte += 1 } }
            func hmacKey() throws -> Data { lock.withLock { Data(repeating: keyByte, count: 32) } }
        }
        let store = KeyedStore()
        let first = LearnedNames(store: store, hmacKey: try? store.hmacKey(), titles: Self.titles,
                                 isDictionaryWord: { _ in false })
        first.removeAll()
        first.flush()
        first.observe(word: "Shopee", previous: nil)
        first.flush()
        let second = LearnedNames(store: store, hmacKey: try? store.hmacKey(), titles: Self.titles,
                                  isDictionaryWord: { _ in false })
        second.observe(word: "Shopee", previous: nil)
        XCTAssertEqual(second.name(after: nil, word: "shopee"), "Shopee", "the hidden count matched after a restart")
    }

    /// An unreadable store whose erase waits for the test, then deletes the file and the HMAC key.
    private final class GatedStore: LearnStore, LearnKeyProvider {
        let gate = DispatchSemaphore(value: 0)
        var failNextErase = false
        private let lock = NSLock()
        private var data: Data? = Data("not json".utf8)
        private var keyByte: UInt8 = 1
        private var _erases = 0
        var erases: Int { lock.withLock { _erases } }
        var saved: Data? { lock.withLock { data } }
        func load() throws -> Data? { lock.withLock { data } }
        func save(_ data: Data) throws { lock.withLock { self.data = data } }
        func erase() throws {
            gate.wait()
            try lock.withLock {
                _erases += 1
                if failNextErase {
                    failNextErase = false
                    throw CocoaError(.fileWriteUnknown)
                }
                data = nil
                keyByte += 1
            }
        }
        func hmacKey() throws -> Data { lock.withLock { Data(repeating: keyByte, count: 32) } }
    }

    /// The hidden counts in the store's last save.
    private func savedPending(_ store: GatedStore) throws -> [String: Any] {
        let saved = try XCTUnwrap(store.saved)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        return try XCTUnwrap(json["pending"] as? [String: Any])
    }

    /// Re-review Minor 2: a hidden count recorded between "Xoá tất cả" and the erase finishing is digested with the
    /// key the erase deletes, so it is dropped when the new key is taken; and a second "Xoá tất cả" in that window
    /// queues no second erase (which would delete the new key as well).
    func testRemoveAllWhileErasingDropsOldKeyCountsAndErasesOnce() throws {
        let store = GatedStore()
        let n = LearnedNames(store: store, hmacKey: try? store.hmacKey(), titles: Self.titles,
                             isDictionaryWord: { _ in false })
        n.removeAll()
        n.removeAll()
        n.observe(word: "Shopee", previous: nil)
        store.gate.signal()
        store.gate.signal()
        n.flush()
        XCTAssertEqual(store.erases, 1, "one erase for both")
        XCTAssertEqual(try store.hmacKey(), Data(repeating: 2, count: 32))
        n.observe(word: "Lazada", previous: nil)
        n.flush()
        XCTAssertEqual(try savedPending(store).count, 1, "only the count made under the new key")
        // The new key's counts still add up.
        n.observe(word: "Lazada", previous: nil)
        XCTAssertEqual(n.names.map(\.form), ["Lazada"])
    }

    /// A failed erase can be tried again by the next "Xoá tất cả".
    func testFailedEraseIsRetried() {
        let store = GatedStore()
        store.failNextErase = true
        let n = LearnedNames(store: store, hmacKey: try? store.hmacKey(), titles: Self.titles,
                             isDictionaryWord: { _ in false })
        store.gate.signal()
        n.removeAll()
        n.flush()
        XCTAssertEqual(store.erases, 1)
        store.gate.signal()
        n.removeAll()
        n.flush()
        XCTAssertEqual(store.erases, 2)
        XCTAssertEqual(try store.hmacKey(), Data(repeating: 2, count: 32))
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

        // Memory only: learned while it runs, and nothing reaches the store.
        otherKey.flush()
        let savesBefore = store.saves
        let none = names(nil)
        none.observe(word: "Shopee", previous: nil)
        none.observe(word: "Shopee", previous: nil)
        none.flush()
        XCTAssertEqual(none.names.map(\.form), ["Shopee"])
        XCTAssertEqual(store.saves, savesBefore)
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
        n.flush()
        // The saved snapshot has no hidden count left: one more sighting after a reload is still below the threshold.
        let reloaded = names(store)
        XCTAssertTrue(reloaded.names.isEmpty)
        reloaded.observe(word: "Lan", previous: "chị")
        XCTAssertNil(reloaded.name(after: "chị", word: "lan"), "removeAll forgot the hidden counts on disk too")
        n.observe(word: "Lan", previous: "chị")
        XCTAssertNil(n.name(after: "chị", word: "lan"), "and in memory")
    }

    /// Task 2 minor 6: a file that cannot be decoded is never overwritten by the session that could not read it.
    func testUndecodableFileIsNotOverwritten() {
        let garbage = Data("not json".utf8)
        let store = InMemoryStore(garbage)
        let n = names(store)
        n.observe(word: "Shopee", previous: nil)
        n.observe(word: "Shopee", previous: nil)
        n.flush()
        XCTAssertEqual(store.saved, garbage)
        XCTAssertEqual(store.saves, 0)
    }

    /// Task 5 minor 4: "Xoá tất cả" erases a file the session could not read, so its names never come back.
    func testRemoveAllErasesAnUnreadableFile() {
        let store = InMemoryStore(Data("not json".utf8))
        let n = names(store)
        n.removeAll()
        n.flush()
        XCTAssertEqual(store.erased, 1)
        XCTAssertNil(store.saved)
        // From now on the file is this session's: changes are saved.
        n.observe(word: "Shopee", previous: nil)
        n.observe(word: "Shopee", previous: nil)
        n.flush()
        XCTAssertEqual(names(store).names.map(\.form), ["Shopee"])
    }

    /// Task 2 minor 1: a lookup marks the name used in memory but starts no save of the whole file; the new
    /// `lastUsed` rides along with the next real change.
    func testLookupStartsNoSave() {
        let store = InMemoryStore()
        let n = names(store)
        n.observe(word: "Shopee", previous: nil)
        n.observe(word: "Shopee", previous: nil)
        n.flush()
        let saves = store.saves
        for _ in 0..<5 { XCTAssertEqual(n.name(after: nil, word: "shopee"), "Shopee") }
        n.flush()
        XCTAssertEqual(store.saves, saves)
    }

    func testRealDictionaryCheck() {
        XCTAssertEqual(LearnedNames.asciiFolded("Đường"), "duong")
        // Task 2 minor 2: letters only, so a hyphen or apostrophe does not make every such word a non-word.
        XCTAssertEqual(LearnedNames.asciiFolded("Ê-đê"), "ede")
        XCTAssertEqual(LearnedNames.asciiFolded("O’Neil"), "oneil")
        XCTAssertFalse(LearnedNames.isDictionaryWord("ede"), "Ê-đê is still learned anywhere")
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
