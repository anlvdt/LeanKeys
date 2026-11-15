import CryptoKit
import Foundation
import Security

/// Where PhraseLearner keeps its counts. `save` receives the plaintext; a store that writes to disk encrypts it.
public protocol LearnStore {
    func load() throws -> Data?
    func save(_ data: Data) throws
    func erase() throws
}

/// A store that also holds the HMAC key phrases are digested with. A store without one gets a random key for the
/// learner's lifetime, so its saved digests match nothing after a restart.
public protocol LearnKeyProvider {
    /// 32 bytes, the same on every call until `erase()`.
    func hmacKey() throws -> Data
}

/// The real store: the counts sealed with AES-GCM in a 0600 file, the AES and HMAC keys (32 random bytes each) in
/// the login keychain, marked after-first-unlock, this device only, not synchronizable. `erase()` deletes the file and
/// both keys. Nothing here is logged.
public final class KeychainEncryptedFileStore: LearnStore, LearnKeyProvider {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LeanKeys/learn.bin")
    }

    private enum Account {
        static let aes = "aes-gcm"
        static let hmac = "hmac-sha256"
    }

    private let url: URL
    private let service: String
    /// The AES key once read, so a save does not query the Keychain each time. `erase()` clears it.
    private var aesKey: Data?

    public init(url: URL, keychainService: String = "io.github.anlvdt.leankeys.learn") {
        self.url = url
        self.service = keychainService
    }

    /// Nothing saved yet, or a file that no longer opens (its key gone, or damaged): nil, and the next save
    /// replaces it.
    public func load() throws -> Data? {
        guard let sealed = try? Data(contentsOf: url) else { return nil }
        guard let keyData = try readKey(Account.aes),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let plain = try? AES.GCM.open(box, using: SymmetricKey(data: keyData)) else { return nil }
        return plain
    }

    public func save(_ data: Data) throws {
        if aesKey == nil { aesKey = try key(Account.aes) }
        let key = SymmetricKey(data: aesKey!)
        guard let sealed = try AES.GCM.seal(data, using: key).combined else { throw StoreError.seal }
        try writePrivately(sealed)
    }

    public func erase() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        aesKey = nil
        try deleteKey(Account.aes)
        try deleteKey(Account.hmac)
    }

    public func hmacKey() throws -> Data { try key(Account.hmac) }

    // MARK: File

    /// Writes to a 0600 temporary file next to `url`, then renames it over: the data is never readable by others,
    /// not even for a moment, and a crash leaves the old file whole.
    private func writePrivately(_ data: Data) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let fd = open(tmp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw StoreError.posix(errno) }
        var failed: Int32 = 0
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    failed = errno
                    return
                }
                offset += n
            }
        }
        if failed == 0, fsync(fd) != 0 { failed = errno }
        close(fd)
        guard failed == 0, rename(tmp.path, url.path) == 0 else {
            let error = failed != 0 ? failed : errno
            unlink(tmp.path)
            throw StoreError.posix(error)
        }
    }

    // MARK: Keychain

    /// The login keychain. The data-protection keychain needs a keychain-access-groups entitlement, which the
    /// self-signed app and the test runner lack (SecItemAdd there fails with errSecMissingEntitlement, while reads
    /// just find nothing). The login keychain never syncs to iCloud; `kSecAttrAccessible` is still set, so the items
    /// keep the intended policy if they ever move to the data-protection keychain.
    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private func readKey(_ account: String) throws -> Data? {
        var result: CFTypeRef?
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            throw StoreError.keychain(status)
        }
        return data
    }

    /// The key under `account`, made (32 random bytes) and stored on first use.
    private func key(_ account: String) throws -> Data {
        if let existing = try readKey(account) { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw StoreError.random
        }
        let data = Data(bytes)
        var query = baseQuery(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecAttrLabel as String] = "LeanKeys learned phrases"
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = try readKey(account) { return existing }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        return data
    }

    private func deleteKey(_ account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.keychain(status) }
    }

    enum StoreError: Error {
        case seal, random
        case keychain(OSStatus)
        case posix(Int32)
    }
}
