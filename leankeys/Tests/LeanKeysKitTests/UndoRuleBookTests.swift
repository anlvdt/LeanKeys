import Foundation
import Security
import XCTest
@testable import LeanKeysKit

/// Keeps the plaintext the book hands over. Saves arrive on the book's private queue, hence the lock.
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

/// A clock that moves one second per reading, so every record has its own `lastUsed`.
private final class Clock {
    private var t = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date {
        t = t.addingTimeInterval(1)
        return t
    }
}

final class UndoRuleBookTests: XCTestCase {
    private var clock: Clock!

    override func setUp() { clock = Clock() }

    private func book(_ store: LearnStore? = nil) -> UndoRuleBook {
        UndoRuleBook(store: store, now: { [clock] in clock!.now() })
    }

    func testContextRuleAfterOneUndo() {
        let b = book()
        XCTAssertFalse(b.shouldKeep(before: "its", previous: "about"))
        b.record(before: "its", previous: "about", reverse: false)
        XCTAssertTrue(b.shouldKeep(before: "its", previous: "about"))
        XCTAssertFalse(b.shouldKeep(before: "its", previous: "with"), "a context rule holds only in its context")
        XCTAssertFalse(b.shouldKeep(before: "its", previous: ""))
        XCTAssertEqual(b.rules.map { [$0.previous, $0.text] }, [["about", "its"]], "the count-1 contextless rule is hidden")
        XCTAssertEqual(b.rules.first?.count, 1)
    }

    func testContextlessAfterTwoUndos() {
        let b = book()
        b.record(before: "cos", previous: "", reverse: false)
        XCTAssertFalse(b.shouldKeep(before: "cos", previous: "the"))
        XCTAssertTrue(b.rules.isEmpty)
        b.record(before: "cos", previous: "this", reverse: false)
        XCTAssertTrue(b.shouldKeep(before: "cos", previous: "the"), "two undos: kept in any context")
        XCTAssertTrue(b.shouldKeep(before: "cos", previous: ""))
        let contextless = b.rules.first { $0.previous.isEmpty }
        XCTAssertEqual(contextless?.text, "cos")
        XCTAssertEqual(contextless?.count, 2)
        XCTAssertEqual(Set(b.rules.map(\.id)), Set(["\u{1F}cos", "this\u{1F}cos"]))
    }

    func testCaseInsensitive() {
        let b = book()
        b.record(before: "Cos", previous: "The", reverse: false)
        XCTAssertTrue(b.shouldKeep(before: "cos", previous: "the"))
        XCTAssertTrue(b.shouldKeep(before: "COS", previous: "THE"))
        XCTAssertEqual(b.rules.first?.text, "cos")
        XCTAssertEqual(b.rules.first?.previous, "the")
    }

    func testReverseDropsAndBlocks() {
        let b = book()
        b.record(before: "its", previous: "about", reverse: false)
        b.record(before: "its", previous: "", reverse: false)
        b.record(before: "car", previous: "", reverse: false)
        b.record(before: "car", previous: "", reverse: false)
        XCTAssertTrue(b.shouldKeep(before: "its", previous: "about"))
        XCTAssertTrue(b.shouldKeep(before: "its", previous: "x"))

        b.record(before: "ITS", previous: "whatever", reverse: true)
        XCTAssertFalse(b.shouldKeep(before: "its", previous: "about"), "every rule for the text goes")
        XCTAssertFalse(b.shouldKeep(before: "its", previous: "x"))
        XCTAssertFalse(b.rules.contains { $0.text == "its" })
        XCTAssertTrue(b.shouldKeep(before: "car", previous: "x"), "other texts are untouched")

        // Spec 12.2: two more same-direction undos recreate the rule. With context: the context rule and the
        // contextless count both come back after the second.
        b.record(before: "its", previous: "about", reverse: false)
        XCTAssertFalse(b.shouldKeep(before: "its", previous: "about"), "one undo after a reverse: still blocked")
        XCTAssertFalse(b.shouldKeep(before: "its", previous: "x"))
        XCTAssertFalse(b.rules.contains { $0.text == "its" }, "a blocked text is not shown")
        b.record(before: "its", previous: "about", reverse: false)
        XCTAssertTrue(b.shouldKeep(before: "its", previous: "about"), "two undos after a reverse: the context rule")
        XCTAssertTrue(b.shouldKeep(before: "its", previous: "x"), "those two undos also reach contextless count 2")

        // Without context.
        b.record(before: "car", previous: "", reverse: true)
        XCTAssertFalse(b.shouldKeep(before: "car", previous: "x"))
        b.record(before: "car", previous: "", reverse: false)
        XCTAssertFalse(b.shouldKeep(before: "car", previous: "x"), "one undo after a reverse: still blocked")
        b.record(before: "car", previous: "", reverse: false)
        XCTAssertTrue(b.shouldKeep(before: "car", previous: "x"), "two undos after a reverse: the contextless rule")
        XCTAssertEqual(b.rules.first { $0.text == "car" }?.count, 2)
    }

    func testLRUCap() {
        let b = book()
        // Two contextless records each: one visible rule per text.
        for i in 0...UndoRuleBook.capacity {
            b.record(before: "w\(i)", previous: "", reverse: false)
            b.record(before: "w\(i)", previous: "", reverse: false)
        }
        let rules = b.rules
        XCTAssertEqual(rules.count, UndoRuleBook.capacity)
        XCTAssertFalse(rules.contains { $0.text == "w0" }, "the least recently used goes")
        XCTAssertTrue(rules.contains { $0.text == "w1" })
        XCTAssertEqual(rules.first?.text, "w\(UndoRuleBook.capacity)", "most recently used first")
        XCTAssertFalse(b.shouldKeep(before: "w0", previous: ""))

        // Using a rule makes it recent: the next eviction takes w2, not w1.
        XCTAssertTrue(b.shouldKeep(before: "w1", previous: ""))
        XCTAssertEqual(b.rules.first?.text, "w1")
        b.record(before: "fresh", previous: "", reverse: false)
        XCTAssertTrue(b.shouldKeep(before: "w1", previous: ""))
        XCTAssertFalse(b.shouldKeep(before: "w2", previous: ""))
    }

    func testRemoveAndRemoveAll() {
        let b = book()
        b.record(before: "its", previous: "about", reverse: false)
        b.record(before: "cos", previous: "", reverse: false)
        b.record(before: "cos", previous: "", reverse: false)
        XCTAssertEqual(b.rules.count, 2)

        let cos = b.rules.first { $0.text == "cos" }!
        b.remove(cos)
        XCTAssertFalse(b.shouldKeep(before: "cos", previous: ""))
        XCTAssertEqual(b.rules.map(\.text), ["its"])

        b.removeAll()
        XCTAssertTrue(b.rules.isEmpty)
        XCTAssertFalse(b.shouldKeep(before: "its", previous: "about"))
        // removeAll also forgets the hidden contextless count and any block.
        b.record(before: "its", previous: "", reverse: false)
        XCTAssertFalse(b.shouldKeep(before: "its", previous: ""))
    }

    func testOnChangeOnMainQueue() {
        let b = book()
        let changed = expectation(description: "onChange")
        changed.assertForOverFulfill = false
        b.onChange = {
            XCTAssertTrue(Thread.isMainThread)
            changed.fulfill()
        }
        DispatchQueue.global().async { b.record(before: "cos", previous: "the", reverse: false) }
        wait(for: [changed], timeout: 5)
    }

    /// Ruling R16: a rules file that cannot be decoded (corrupt, or from a later version) is never overwritten by
    /// the session that could not read it.
    func testUndecodableFileIsNotOverwritten() {
        let garbage = Data("not json".utf8)
        let store = InMemoryStore(garbage)
        let b = book(store)
        b.record(before: "its", previous: "about", reverse: false)
        b.flush()
        XCTAssertTrue(b.shouldKeep(before: "its", previous: "about"), "the rule still works this session")
        XCTAssertEqual(store.saved, garbage)
        XCTAssertEqual(store.saves, 0)
    }

    /// Ruling R16, as for learned names: "Xoá tất cả" erases a file the session could not read, so its rules do
    /// not come back at the next launch; from then on changes are saved.
    func testRemoveAllErasesAnUnreadableFile() {
        let store = InMemoryStore(Data("not json".utf8))
        let b = book(store)
        b.removeAll()
        b.flush()
        XCTAssertEqual(store.erased, 1)
        XCTAssertNil(store.saved)
        b.record(before: "its", previous: "about", reverse: false)
        b.flush()
        XCTAssertTrue(book(store).shouldKeep(before: "its", previous: "about"))
    }

    func testPersistsThroughStore() {
        let store = InMemoryStore()
        let b = book(store)
        b.record(before: "its", previous: "about", reverse: false)
        b.record(before: "cos", previous: "", reverse: false)
        b.record(before: "cos", previous: "", reverse: false)
        b.record(before: "car", previous: "", reverse: false)
        b.record(before: "car", previous: "", reverse: true)
        b.flush()
        XCTAssertGreaterThan(store.saves, 0)

        let again = book(store)
        XCTAssertEqual(again.rules, b.rules)
        XCTAssertTrue(again.shouldKeep(before: "its", previous: "about"))
        XCTAssertTrue(again.shouldKeep(before: "cos", previous: "x"))
        // The block survives too: the first record after reloading still keeps nothing, the second does.
        again.record(before: "car", previous: "a", reverse: false)
        XCTAssertFalse(again.shouldKeep(before: "car", previous: "a"))
        again.record(before: "car", previous: "a", reverse: false)
        XCTAssertTrue(again.shouldKeep(before: "car", previous: "a"))

        // Memory only.
        let none = book(nil)
        none.record(before: "its", previous: "about", reverse: false)
        none.flush()
        XCTAssertTrue(book(nil).rules.isEmpty)
    }
}

/// The real store, with a Keychain service used only here. Items are deleted in tearDown.
final class UndoRuleBookKeychainTests: XCTestCase {
    private var service: String!
    private var dir: URL!

    override func setUp() {
        service = "io.github.anlvdt.leankeys.undo.tests.\(UUID().uuidString)"
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("leankeys-undo-\(UUID().uuidString)")
    }

    override func tearDown() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service!]
        SecItemDelete(query as CFDictionary)
        try? FileManager.default.removeItem(at: dir)
    }

    /// Same rule as KeychainEncryptedFileStoreTests: LEANKEYS_SKIP_KEYCHAIN_TESTS=1 or a locked keychain skips.
    private func requireKeychain() throws {
        if ProcessInfo.processInfo.environment["LEANKEYS_SKIP_KEYCHAIN_TESTS"] == "1" {
            throw XCTSkip("LEANKEYS_SKIP_KEYCHAIN_TESTS=1")
        }
        let probe: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service!,
                                    kSecAttrAccount as String: "probe", kSecValueData as String: Data([0])]
        let status = SecItemAdd(probe as CFDictionary, nil)
        if status == errSecInteractionNotAllowed { throw XCTSkip("keychain locked (errSecInteractionNotAllowed)") }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service!,
                       kSecAttrAccount as String: "probe"] as CFDictionary)
    }

    func testSavedDataEncryptedOnDisk() throws {
        try requireKeychain()
        let url = dir.appendingPathComponent("undo-rules.bin")
        let b = UndoRuleBook(store: KeychainEncryptedFileStore(url: url, keychainService: service))
        b.record(before: "cos", previous: "the", reverse: false)
        b.record(before: "cos", previous: "", reverse: false)
        b.flush()

        let raw = try Data(contentsOf: url)
        XCTAssertNil(raw.range(of: Data("cos".utf8)))
        XCTAssertNil(raw.range(of: Data("the".utf8)))
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)

        let again = UndoRuleBook(store: KeychainEncryptedFileStore(url: url, keychainService: service))
        XCTAssertEqual(again.rules, b.rules)
        XCTAssertTrue(again.shouldKeep(before: "cos", previous: "x"))
    }
}
