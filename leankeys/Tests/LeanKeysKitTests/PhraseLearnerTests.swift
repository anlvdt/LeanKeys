import Foundation
import Security
import XCTest
@testable import LeanKeysKit

/// Keeps what the learner hands over, which is the plaintext before encryption, and a fixed HMAC key so a fresh
/// learner on the same store matches earlier digests.
private final class InMemoryStore: LearnStore, LearnKeyProvider {
    var lastSavedPlaintext: Data?
    var erased = 0
    private var key = Data((0..<32).map { UInt8($0) })

    func load() throws -> Data? { lastSavedPlaintext }
    func save(_ data: Data) throws { lastSavedPlaintext = data }
    func erase() throws {
        lastSavedPlaintext = nil
        erased += 1
        key = Data((0..<32).map { UInt8(255 - $0) })
    }
    func hmacKey() throws -> Data { key }

    var savedString: String { lastSavedPlaintext.map { String(decoding: $0, as: UTF8.self) } ?? "" }
}

private let day: TimeInterval = 86_400
private let start = Date(timeIntervalSince1970: 20_000 * day + 3_600)

private func ctx(_ dayOffset: Int = 0, bundleID: String? = "com.apple.TextEdit", secureInput: Bool = false,
                 secureField: Bool = false) -> LearnContext {
    LearnContext(bundleID: bundleID, secureInput: secureInput, secureField: secureField,
                 now: start.addingTimeInterval(Double(dayOffset) * day))
}

private func phrase(_ text: String) -> CommittedPhrase { CommittedPhrase(text: text) }

final class PhraseLearnerTests: XCTestCase {
    private var store: InMemoryStore!
    private var learner: PhraseLearner!

    override func setUp() {
        store = InMemoryStore()
        learner = PhraseLearner(store: store)
        learner.enabled = true
    }

    private func observe(_ text: String, times: Int = 3, days: [Int]? = nil, _ context: LearnContext? = nil) {
        let offsets = days ?? Array(repeating: 0, count: times)
        for d in offsets { learner.observe(phrase(text), context: context ?? ctx(d)) }
    }

    private func readyTexts() -> [String] { learner.ready.map(\.text) }

    func testThresholdAndWindow() {
        observe("Cảm ơn anh nhiều nhé", days: [0, 10])
        XCTAssertTrue(learner.ready.isEmpty, "two sightings are below the threshold")
        observe("Cảm ơn anh nhiều nhé", days: [29])
        XCTAssertEqual(readyTexts(), ["Cảm ơn anh nhiều nhé"])
        XCTAssertEqual(learner.ready.first?.count, 3)
        XCTAssertEqual(learner.ready.first?.kind, .phrase)

        observe("Hẹn gặp lại mọi người", days: [0, 20, 40])
        XCTAssertFalse(readyTexts().contains("Hẹn gặp lại mọi người"), "three sightings over 40 days")

        // Case and spacing do not split a phrase.
        observe("Chúc ngủ ngon cả nhà", days: [0])
        observe("chúc  ngủ ngon CẢ nhà", days: [1])
        observe("Chúc ngủ ngon cả nhà ", days: [2])
        XCTAssertTrue(readyTexts().contains { $0.lowercased() == "chúc ngủ ngon cả nhà" })

        // Shorter than eight characters: never counted.
        observe("ok anh", times: 5)
        XCTAssertFalse(readyTexts().contains("ok anh"))

        // Off by default.
        let off = PhraseLearner(store: InMemoryStore())
        for _ in 0..<3 { off.observe(phrase("Cảm ơn anh nhiều nhé"), context: ctx()) }
        XCTAssertTrue(off.ready.isEmpty)
    }

    func testPlaintextNeverStoredBelowThreshold() throws {
        let text = "Gọi em số 0912 345 678 hoặc mail an@vidu.vn nhé"
        observe(text, times: 2)
        XCTAssertNotNil(store.lastSavedPlaintext, "the counts are saved")
        let saved = store.savedString
        for secret in [text, text.lowercased(), "0912 345 678", "0912345678", "an@vidu.vn", "vidu", "Gọi em",
                       "gọi em", "phone", "email"] {
            XCTAssertFalse(saved.contains(secret), "saved data contains \(secret)")
        }
        XCTAssertTrue(learner.ready.isEmpty)

        observe(text, times: 1)
        XCTAssertTrue(store.savedString.contains("an@vidu.vn"), "plaintext is kept once the threshold is reached")
    }

    func testSecureAndExcludedNotLearned() {
        let text = "Cảm ơn anh nhiều nhé"
        observe(text, times: 3, ctx(secureInput: true))
        observe(text, times: 3, ctx(secureField: true))
        for bundle in ["com.1password.1password", "com.bitwarden.desktop", "com.apple.keychainaccess",
                       "com.apple.Passwords"] {
            observe(text, times: 3, ctx(bundleID: bundle))
        }
        observe(text, times: 3, ctx(bundleID: nil))
        XCTAssertTrue(learner.ready.isEmpty)
        XCTAssertEqual(learner.trackedCount, 0)
        XCTAssertNil(store.lastSavedPlaintext)
    }

    func testRejectsCardAndOTP() {
        for text in ["4111 1111 1111 1111", "4111-1111-1111-1111", "Thẻ 4111 1111 1111 1111 nhé", "482913",
                     "48291357", "Thẻ 4111 1111 1111 1111 12 28"] {
            observe(text, times: 3)
        }
        XCTAssertTrue(learner.ready.isEmpty)
        XCTAssertEqual(learner.trackedCount, 0)

        // Luhn decides: a 16-digit number that fails it is an ordinary phrase.
        observe("4111 1111 1111 1112", times: 3)
        XCTAssertEqual(readyTexts(), ["4111 1111 1111 1112"])
        // A tax code with its suffix has 13 digits; this one passes Luhn and is still a tax code.
        observe("0312345678-006", times: 3)
        XCTAssertEqual(learner.ready.first { $0.text == "0312345678-006" }?.kind, .taxCode)
        // A phone in space groups is no OTP.
        observe("0912 345 678", times: 3)
        XCTAssertEqual(learner.ready.first { $0.text == "0912 345 678" }?.kind, .phone)
    }

    /// R10: only a phrase that is nothing but 4–8 digits is an OTP; digit groups inside text are fine.
    func testOTPOnlyWhenWholePhrase() {
        observe("482913", times: 3)
        observe("48291357", times: 3)
        observe(" 482913 ", times: 3)
        XCTAssertEqual(learner.trackedCount, 0)

        observe("Mã của em là 482913", times: 3)
        XCTAssertTrue(readyTexts().contains("Mã của em là 482913"))
        observe("Số 1234 đường Lê Lợi, quận 1", times: 3)
        XCTAssertEqual(learner.ready.first { $0.text == "Số 1234 đường Lê Lợi, quận 1" }?.kind, .address)
    }

    /// R11: turning learning off wipes every stored text but keeps the hashed counts.
    func testDisablingWipesPlaintext() {
        let text = "Cảm ơn anh nhiều nhé"
        observe(text, times: 3)
        XCTAssertEqual(readyTexts(), [text])
        learner.enabled = false
        XCTAssertTrue(learner.ready.isEmpty)
        XCTAssertFalse(store.savedString.contains(text))
        XCTAssertEqual(learner.trackedCount, 1, "the digest and its day counts stay")
        observe(text, times: 1)
        XCTAssertTrue(learner.ready.isEmpty, "nothing is observed while off")

        learner.enabled = true
        observe(text, times: 1)
        XCTAssertEqual(readyTexts(), [text])
        XCTAssertEqual(learner.ready.first?.count, 4)
        XCTAssertTrue(store.savedString.contains(text))
    }

    /// R13: a bare 0xxxxxxxxx is a tax code next to "MST", "mã số thuế" or "thuế", else a phone.
    func testBareTenDigitsNearTaxWordIsTaxCode() {
        for text in ["MST 0312345678", "Mã số thuế: 0312345678", "ma so thue cong ty 0312345678",
                     "Thuế 0312345678 nhé"] {
            learner.eraseAll()
            observe(text, times: 3)
            XCTAssertEqual(learner.ready.first { $0.text == "0312345678" }?.kind, .taxCode, text)
            XCTAssertFalse(learner.ready.contains { $0.kind == .phone }, text)
        }
        for text in ["Gọi 0312345678 nhé", "0312345678", "Mã số 0312345678 nhé"] {
            learner.eraseAll()
            observe(text, times: 3)
            XCTAssertEqual(learner.ready.first { $0.text == "0312345678" }?.kind, .phone, text)
        }
    }

    func testDetectsKinds() {
        let cases: [(String, PhraseKind)] = [
            ("0912 345 678", .phone),
            ("+84 912 345 678", .phone),
            ("0312345678-001", .taxCode),
            ("Số 12 đường Lê Lợi, phường Bến Nghé, quận 1", .address),
            ("an@vidu.vn", .email),
        ]
        for (text, kind) in cases {
            learner.eraseAll()
            observe(text, times: 3)
            XCTAssertEqual(learner.ready.map(\.text), [text], text)
            XCTAssertEqual(learner.ready.first?.kind, kind, text)
        }

        // Inside a phrase, each piece counts by itself as well as the whole phrase.
        learner.eraseAll()
        observe("Liên hệ 0912.345.678 hoặc an@vidu.vn", times: 3)
        let kinds = Dictionary(learner.ready.map { ($0.kind, $0.text) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(kinds[.phone], "0912.345.678")
        XCTAssertEqual(kinds[.email], "an@vidu.vn")
        XCTAssertEqual(kinds[.phrase], "Liên hệ 0912.345.678 hoặc an@vidu.vn")

        learner.eraseAll()
        observe("Giao hàng tới Số 12 đường Lê Lợi, phường Bến Nghé, quận 1", times: 3)
        XCTAssertEqual(learner.ready.first { $0.kind == .address }?.text, "Số 12 đường Lê Lợi, phường Bến Nghé, quận 1")

        // The same phone in another spelling is the same item.
        learner.eraseAll()
        observe("0912 345 678", days: [0])
        observe("0912.345.678", days: [1])
        observe("+84912345678", days: [2])
        XCTAssertEqual(learner.ready.filter { $0.kind == .phone }.count, 1)

        // One address word, or a word that only starts like one, is no address.
        learner.eraseAll()
        observe("Cho em xin số điện thoại", times: 3)
        observe("Bé bị sốt từ hôm qua đường ruột", times: 3)
        XCTAssertFalse(learner.ready.contains { $0.kind == .address })
    }

    func testDismissIsRemembered() {
        let text = "Cảm ơn anh nhiều nhé"
        observe(text, times: 3)
        let candidate = try! XCTUnwrap(learner.ready.first)
        learner.dismiss(candidate)
        XCTAssertTrue(learner.ready.isEmpty)
        XCTAssertFalse(store.savedString.contains(text), "dismiss wipes the plaintext")

        observe(text, times: 3)
        XCTAssertTrue(learner.ready.isEmpty)

        let fresh = PhraseLearner(store: store)
        fresh.enabled = true
        for d in 0..<5 { fresh.observe(phrase(text), context: ctx(d)) }
        XCTAssertTrue(fresh.ready.isEmpty, "a new learner on the same store remembers the dismissal")
        XCTAssertFalse(store.savedString.contains(text))
    }

    func testAcceptErasesPlaintext() {
        let text = "Số 12 đường Lê Lợi, phường Bến Nghé, quận 1"
        observe(text, times: 3)
        let candidate = try! XCTUnwrap(learner.ready.first)
        XCTAssertTrue(store.savedString.contains("Lê Lợi"))
        learner.accept(candidate)
        XCTAssertTrue(learner.ready.isEmpty)
        XCTAssertFalse(store.savedString.contains("Lê Lợi"))

        // The new gõ tắt expands back into the same text: it must not come back as a suggestion.
        observe(text, times: 4)
        XCTAssertTrue(learner.ready.isEmpty)
        XCTAssertFalse(store.savedString.contains("Lê Lợi"))
    }

    func testEraseAll() {
        observe("Cảm ơn anh nhiều nhé", times: 3)
        observe("Hẹn gặp lại mọi người", times: 3)
        learner.dismiss(learner.ready.first { $0.text == "Hẹn gặp lại mọi người" }!)
        learner.eraseAll()
        XCTAssertTrue(learner.ready.isEmpty)
        XCTAssertEqual(learner.trackedCount, 0)
        XCTAssertEqual(store.erased, 1)
        XCTAssertFalse(store.savedString.contains("Cảm ơn"))

        // Dismissals go too, and counting starts again from zero.
        observe("Hẹn gặp lại mọi người", times: 2)
        XCTAssertTrue(learner.ready.isEmpty)
        observe("Hẹn gặp lại mọi người", times: 1)
        XCTAssertEqual(readyTexts(), ["Hẹn gặp lại mọi người"])
    }

    func testCountsAgeOut() {
        let text = "Cảm ơn anh nhiều nhé"
        observe(text, days: [0, 1, 2])
        XCTAssertEqual(readyTexts(), [text])
        // Thirty days later the sightings fall out of the window: the candidate and its plaintext go.
        observe("Một câu khác hẳn luôn", days: [40])
        XCTAssertTrue(learner.ready.isEmpty)
        XCTAssertFalse(store.savedString.contains(text))
        XCTAssertEqual(learner.trackedCount, 1)
    }
}

/// The real store, with a Keychain service used only here. Items are deleted in tearDown.
final class KeychainEncryptedFileStoreTests: XCTestCase {
    private var service: String!
    private var dir: URL!

    override func setUp() {
        service = "io.github.anlvdt.leankeys.learn.tests.\(UUID().uuidString)"
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("leankeys-learn-\(UUID().uuidString)")
    }

    override func tearDown() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service!]
        SecItemDelete(query as CFDictionary)
        var dp = query
        dp[kSecUseDataProtectionKeychain as String] = true
        SecItemDelete(dp as CFDictionary)
        try? FileManager.default.removeItem(at: dir)
    }

    private func items() -> Int {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service!,
                                    kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnAttributes as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return 0 }
        return (out as? [[String: Any]])?.count ?? 0
    }

    func testRoundTripThroughKeychain() throws {
        let url = dir.appendingPathComponent("LeanKeys/learn.bin")
        let store = KeychainEncryptedFileStore(url: url, keychainService: service)
        XCTAssertNil(try store.load())

        let plaintext = Data(#"{"secret":"Số 12 đường Lê Lợi"}"#.utf8)
        try store.save(plaintext)
        let raw = try Data(contentsOf: url)
        XCTAssertNil(raw.range(of: plaintext))
        XCTAssertNil(raw.range(of: Data("Lê Lợi".utf8)))
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)

        let hmac = try store.hmacKey()
        XCTAssertEqual(hmac.count, 32)

        // A second store finds both keys in the Keychain, not in memory.
        let again = KeychainEncryptedFileStore(url: url, keychainService: service)
        XCTAssertEqual(try again.load(), plaintext)
        XCTAssertEqual(try again.hmacKey(), hmac)
        try again.save(Data("v2".utf8))
        XCTAssertEqual(try store.load(), Data("v2".utf8))
        XCTAssertEqual(items(), 2)

        try store.erase()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(items(), 0)
        XCTAssertNil(try store.load())
    }

    /// Off by default must mean no trace: a learner that never counts anything creates no Keychain item, and erasing
    /// leaves none behind.
    func testDisabledLearnerLeavesNoKeychainItem() throws {
        let url = dir.appendingPathComponent("learn.bin")
        let idle = PhraseLearner(store: KeychainEncryptedFileStore(url: url, keychainService: service))
        idle.observe(CommittedPhrase(text: "Cảm ơn anh nhiều nhé"),
                     context: LearnContext(bundleID: "com.apple.TextEdit", secureInput: false, secureField: false,
                                           now: Date()))
        XCTAssertTrue(idle.ready.isEmpty)
        XCTAssertEqual(items(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let learner = PhraseLearner(store: KeychainEncryptedFileStore(url: url, keychainService: service))
        learner.enabled = true
        let context = LearnContext(bundleID: "com.apple.TextEdit", secureInput: false, secureField: false, now: Date())
        for _ in 0..<3 { learner.observe(CommittedPhrase(text: "Cảm ơn anh nhiều nhé"), context: context) }
        XCTAssertEqual(learner.ready.map(\.text), ["Cảm ơn anh nhiều nhé"])
        XCTAssertEqual(items(), 2)
        XCTAssertEqual(PhraseLearner(store: KeychainEncryptedFileStore(url: url, keychainService: service)).ready.count, 1)

        learner.eraseAll()
        XCTAssertEqual(items(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        _ = PhraseLearner(store: KeychainEncryptedFileStore(url: url, keychainService: service))
        XCTAssertEqual(items(), 0, "relaunching after an erase recreates nothing")
    }

    func testUnreadableFileLoadsAsNothing() throws {
        let url = dir.appendingPathComponent("learn.bin")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not a sealed box".utf8).write(to: url)
        let store = KeychainEncryptedFileStore(url: url, keychainService: service)
        XCTAssertNil(try store.load())
    }

    func testDefaultLocation() {
        XCTAssertTrue(KeychainEncryptedFileStore.defaultURL.path.hasSuffix("Library/Application Support/LeanKeys/learn.bin"))
    }
}
