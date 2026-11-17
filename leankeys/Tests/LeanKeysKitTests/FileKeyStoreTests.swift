import XCTest
@testable import LeanKeysKit

/// The store's keys live in 0600 files next to its data, not in the login keychain: a self-signed app has no team
/// ID, so the keychain ties each item to the build's cdhash and asked for the login password after every update.
/// Keys an older LeanKeys kept in the keychain move to files once, and only when there is data they unlock.
final class FileKeyStoreTests: XCTestCase {
    private var dir: URL!

    /// Records what the store asks of the old keychain, holding keys like the keychain did.
    private final class FakeLegacy: LegacyKeyStore {
        var keys: [String: Data] = [:]
        var reads: [String] = []
        var deletes: [String] = []
        var failRead = false
        func read(_ account: String) throws -> Data? {
            reads.append(account)
            if failRead { throw KeychainEncryptedFileStore.StoreError.keychain(-128) }   // userCanceled
            return keys[account]
        }
        func delete(_ account: String) throws { deletes.append(account); keys[account] = nil }
    }

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("leankeys-keys-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func mode(_ url: URL) -> Int? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    }

    func testNewStoreKeepsKeysInPrivateFilesAndNeverAsksTheKeychain() throws {
        let url = dir.appendingPathComponent("LeanKeys/learn.bin")
        let legacy = FakeLegacy()
        let store = KeychainEncryptedFileStore(url: url, legacy: legacy)
        XCTAssertNil(try store.load())
        let plaintext = Data("Số 12 đường Lê Lợi".utf8)
        try store.save(plaintext)
        let hmac = try store.hmacKey()
        XCTAssertEqual(hmac.count, 32)
        XCTAssertTrue(legacy.reads.isEmpty, "no data to unlock: the keychain is never asked")

        for account in ["aes-gcm", "hmac-sha256"] {
            let key = KeychainEncryptedFileStore.keyURL(for: url, account: account)
            XCTAssertEqual(mode(key), 0o600, account)
            XCTAssertEqual(try Data(contentsOf: key).count, 32, account)
        }
        XCTAssertEqual(mode(url.deletingLastPathComponent()), 0o700)
        XCTAssertNil(try Data(contentsOf: url).range(of: plaintext))

        let again = KeychainEncryptedFileStore(url: url, legacy: legacy)
        XCTAssertEqual(try again.load(), plaintext)
        XCTAssertEqual(try again.hmacKey(), hmac)
        XCTAssertTrue(legacy.reads.isEmpty)
    }

    func testOldKeychainKeysMoveToFilesOnce() throws {
        let url = dir.appendingPathComponent("learn.bin")
        // What LeanKeys 1.3 left: data sealed with keys held in the keychain, no key files.
        let legacy = FakeLegacy()
        let old = KeychainEncryptedFileStore(url: url, legacy: legacy)
        try old.save(Data("cũ".utf8))
        let oldHMAC = try old.hmacKey()
        for account in ["aes-gcm", "hmac-sha256"] {
            let key = KeychainEncryptedFileStore.keyURL(for: url, account: account)
            legacy.keys[account] = try Data(contentsOf: key)
            try FileManager.default.removeItem(at: key)
        }

        let store = KeychainEncryptedFileStore(url: url, legacy: legacy)
        XCTAssertEqual(try store.load(), Data("cũ".utf8))
        XCTAssertEqual(try store.hmacKey(), oldHMAC)
        XCTAssertEqual(Set(legacy.reads), ["aes-gcm", "hmac-sha256"])
        XCTAssertEqual(Set(legacy.deletes), ["aes-gcm", "hmac-sha256"], "moved keys leave the keychain")

        legacy.reads.removeAll()
        let later = KeychainEncryptedFileStore(url: url, legacy: legacy)
        XCTAssertEqual(try later.load(), Data("cũ".utf8))
        XCTAssertTrue(legacy.reads.isEmpty, "after the move the keychain is never asked again")
    }

    /// The user clicked Deny: the data stays unreadable this session and must not be replaced (ruling R16), and the
    /// move is tried again next launch.
    func testDeniedKeychainReadThrowsAndWritesNoKeyFile() throws {
        let url = dir.appendingPathComponent("learn.bin")
        let legacy = FakeLegacy()
        let old = KeychainEncryptedFileStore(url: url, legacy: legacy)
        try old.save(Data("cũ".utf8))
        let key = KeychainEncryptedFileStore.keyURL(for: url, account: "aes-gcm")
        legacy.keys["aes-gcm"] = try Data(contentsOf: key)
        try FileManager.default.removeItem(at: key)

        legacy.failRead = true
        XCTAssertThrowsError(try KeychainEncryptedFileStore(url: url, legacy: legacy).load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: key.path))
        XCTAssertTrue(legacy.deletes.isEmpty)
    }

    func testEraseRemovesKeyFiles() throws {
        let url = dir.appendingPathComponent("learn.bin")
        let store = KeychainEncryptedFileStore(url: url, legacy: FakeLegacy())
        try store.save(Data("x".utf8))
        _ = try store.hmacKey()
        try store.erase()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        for account in ["aes-gcm", "hmac-sha256"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: KeychainEncryptedFileStore.keyURL(for: url, account: account).path))
        }
        XCTAssertNil(try store.load())
    }

    /// Review C1: a key file that is there but cannot be read is an error, never "no key yet" to be replaced.
    func testUnreadableKeyFileThrowsAndIsNotReplaced() throws {
        let url = dir.appendingPathComponent("learn.bin")
        let store = KeychainEncryptedFileStore(url: url, legacy: FakeLegacy())
        try store.save(Data("x".utf8))
        let key = KeychainEncryptedFileStore.keyURL(for: url, account: "aes-gcm")
        let before = try Data(contentsOf: key)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: key.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path) }

        let fresh = KeychainEncryptedFileStore(url: url, legacy: FakeLegacy())
        XCTAssertThrowsError(try fresh.load())
        XCTAssertThrowsError(try fresh.save(Data("y".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
        XCTAssertEqual(try Data(contentsOf: key), before)
        XCTAssertEqual(try KeychainEncryptedFileStore(url: url, legacy: FakeLegacy()).load(), Data("x".utf8))
    }

    /// Review I1: a move cut short (the HMAC key file written first, the AES one not) finishes next time.
    func testMoveCutShortFinishesNextTime() throws {
        let url = dir.appendingPathComponent("learn.bin")
        let legacy = FakeLegacy()
        let old = KeychainEncryptedFileStore(url: url, legacy: legacy)
        try old.save(Data("cũ".utf8))
        _ = try old.hmacKey()
        let aesFile = KeychainEncryptedFileStore.keyURL(for: url, account: "aes-gcm")
        legacy.keys["aes-gcm"] = try Data(contentsOf: aesFile)
        try FileManager.default.removeItem(at: aesFile)

        XCTAssertEqual(try KeychainEncryptedFileStore(url: url, legacy: legacy).load(), Data("cũ".utf8))
        XCTAssertEqual(legacy.deletes, ["aes-gcm"])
    }

    /// Review I2: after a Deny the keychain is not asked again this session, so the prompt does not repeat.
    func testDeniedMoveIsNotRetriedInTheSameSession() throws {
        let url = dir.appendingPathComponent("learn.bin")
        let legacy = FakeLegacy()
        let old = KeychainEncryptedFileStore(url: url, legacy: legacy)
        try old.save(Data("cũ".utf8))
        for account in ["aes-gcm", "hmac-sha256"] {
            let key = KeychainEncryptedFileStore.keyURL(for: url, account: account)
            if let data = try? Data(contentsOf: key) { legacy.keys[account] = data }
            try? FileManager.default.removeItem(at: key)
        }
        legacy.failRead = true
        let store = KeychainEncryptedFileStore(url: url, legacy: legacy)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.hmacKey())
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(legacy.reads.count, 1)
    }

    /// Review N1: a folder LeanKeys cannot search makes every key file look missing to a plain existence check;
    /// the store must throw, not make a new key and rename it over the old one.
    func testUnsearchableFolderThrowsAndKeepsTheKey() throws {
        let folder = dir.appendingPathComponent("LeanKeys")
        let url = folder.appendingPathComponent("learn.bin")
        try KeychainEncryptedFileStore(url: url, legacy: FakeLegacy()).save(Data("x".utf8))
        let key = KeychainEncryptedFileStore.keyURL(for: url, account: "aes-gcm")
        let before = try Data(contentsOf: key)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }

        let fresh = KeychainEncryptedFileStore(url: url, legacy: FakeLegacy())
        XCTAssertThrowsError(try fresh.save(Data("y".utf8)))
        XCTAssertThrowsError(try fresh.load())
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        XCTAssertEqual(try Data(contentsOf: key), before)
        XCTAssertEqual(try KeychainEncryptedFileStore(url: url, legacy: FakeLegacy()).load(), Data("x".utf8))
    }
}

