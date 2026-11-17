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

/// Keys LeanKeys up to 1.3 kept in the login keychain. Read once, to move them to files.
public protocol LegacyKeyStore {
    /// nil when there is no such item; throws when it exists but cannot be read (the user denied access).
    func read(_ account: String) throws -> Data?
    func delete(_ account: String) throws
}

/// The real store: the counts sealed with AES-GCM in a 0600 file, the AES and HMAC keys (32 random bytes each) in
/// 0600 files next to it (`<file>.aes-gcm.key`, `<file>.hmac-sha256.key`), in a 0700 folder. `erase()` deletes the
/// file and both keys. Nothing here is logged.
///
/// Not the keychain: LeanKeys is self-signed, with no team ID, so the login keychain ties each item to the cdhash of
/// the build that may read it, and every update asked for the login password once per item. Keys an older LeanKeys
/// kept there move to files the first time they are needed, and only when there is data they unlock (one last
/// password prompt per item); a denied read throws, so the data is never replaced (ruling R16) and the move is tried
/// again next time. The name stays for the callers.
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
    private let legacy: LegacyKeyStore?
    /// The AES key once read, so a save does not read the key file each time. `erase()` clears it.
    private var aesKey: Data?

    /// `keychainService`: where LeanKeys up to 1.3 kept this store's keys. `legacy` replaces that keychain in tests.
    public init(url: URL, keychainService: String = "io.github.anlvdt.leankeys.learn", legacy: LegacyKeyStore? = nil) {
        self.url = url
        self.legacy = legacy ?? KeychainLegacyKeys(service: keychainService)
    }

    /// The file holding `account`'s key for the store at `url`.
    public static func keyURL(for url: URL, account: String) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).\(account).key")
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
        for account in [Account.aes, Account.hmac] {
            let key = Self.keyURL(for: url, account: account)
            if FileManager.default.fileExists(atPath: key.path) { try FileManager.default.removeItem(at: key) }
        }
    }

    public func hmacKey() throws -> Data { try key(Account.hmac) }

    // MARK: File

    /// Writes to a 0600 temporary file next to `url`, then renames it over: the data is never readable by others,
    /// not even for a moment, and a crash leaves the old file whole.
    private func writePrivately(_ data: Data) throws { try writePrivately(data, to: url) }

    private func writePrivately(_ data: Data, to url: URL) throws {
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

    // MARK: Keys

    /// The key under `account` from its file, after moving the old keychain's keys of a store from before key
    /// files; nil when there is none. A key file of the wrong size is an error, not a reason to make a new key.
    private func readKey(_ account: String) throws -> Data? {
        try moveLegacyKeysIfNeeded()
        guard let data = try? Data(contentsOf: Self.keyURL(for: url, account: account)) else { return nil }
        guard data.count == 32 else { throw StoreError.badKeyFile }
        return data
    }

    /// A store from before key files (its data there, no key file at all) gets both of its keys from the old
    /// keychain, together: the data and its digests need the pair. A denied read throws before any file is written.
    private func moveLegacyKeysIfNeeded() throws {
        let accounts = [Account.aes, Account.hmac]
        let anyKeyFile = accounts.contains {
            FileManager.default.fileExists(atPath: Self.keyURL(for: url, account: $0).path)
        }
        guard !anyKeyFile, FileManager.default.fileExists(atPath: url.path), let legacy else { return }
        var found: [(String, Data)] = []
        for account in accounts {
            guard let key = try legacy.read(account) else { continue }
            guard key.count == 32 else { throw StoreError.badKeyFile }
            found.append((account, key))
        }
        for (account, key) in found { try writePrivately(key, to: Self.keyURL(for: url, account: account)) }
        for (account, _) in found { try? legacy.delete(account) }
    }

    /// The key under `account`, made (32 random bytes) and written on first use.
    private func key(_ account: String) throws -> Data {
        if let existing = try readKey(account) { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw StoreError.random
        }
        let data = Data(bytes)
        try writePrivately(data, to: Self.keyURL(for: url, account: account))
        return data
    }

    enum StoreError: Error {
        case seal, random, badKeyFile
        case keychain(OSStatus)
        case posix(Int32)
    }
}

/// The login keychain items LeanKeys up to 1.3 wrote: generic passwords under `service`, accounts "aes-gcm" and
/// "hmac-sha256". Reading one of them is what may show macOS's password prompt, once, for the move to files.
struct KeychainLegacyKeys: LegacyKeyStore {
    let service: String

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }

    func read(_ account: String) throws -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainEncryptedFileStore.StoreError.keychain(status)
        }
        return data
    }

    func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainEncryptedFileStore.StoreError.keychain(status)
        }
    }
}
