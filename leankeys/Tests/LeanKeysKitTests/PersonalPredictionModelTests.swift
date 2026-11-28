import XCTest
@testable import LeanKeysKit

final class PersonalPredictionModelTests: XCTestCase {
    private let textEditCtx = LearnContext(
        bundleID: "com.apple.TextEdit",
        secureInput: false,
        secureField: false,
        now: Date(timeIntervalSince1970: 1_800_000_000)
    )

    private final class CountingStore: LearnStore {
        var bytes: Data?
        var saves = 0
        var didSave: () -> Void = {}
        func load() throws -> Data? { bytes }
        func save(_ data: Data) throws { bytes = data; saves += 1; didSave() }
        func erase() throws { bytes = nil }
    }

    func testCoalescedSaveRunsAtDeadline() {
        let saved = expectation(description: "scheduled save")
        let store = CountingStore()
        store.didSave = { saved.fulfill() }
        let model = PersonalPredictionModel(store: store, saveDelay: 0.02)
        model.enabled = true
        model.observe(CommittedPhrase(text: "em gửi báo cáo"), context: textEditCtx)
        wait(for: [saved], timeout: 2)
        withExtendedLifetime(model) {}
    }

    func testCoalescedSaveFlushesLatestSnapshotAndEraseCancelsIt() {
        let store = CountingStore()
        let model = PersonalPredictionModel(store: store, saveDelay: 60)
        model.enabled = true
        for _ in 0..<3 {
            model.observe(CommittedPhrase(text: "em gửi báo cáo"), context: textEditCtx)
        }
        XCTAssertEqual(store.saves, 0)
        model.flush()
        XCTAssertEqual(store.saves, 1)
        let restored = PersonalPredictionModel(store: store)
        restored.enabled = true
        XCTAssertEqual(restored.stats, model.stats)
        XCTAssertFalse(restored.phraseContinuations(after: ["em"]).isEmpty)
        model.observe(CommittedPhrase(text: "em gửi báo cáo"), context: textEditCtx)
        model.eraseAll()
        model.flush()
        XCTAssertNil(store.bytes)
        XCTAssertEqual(store.saves, 1)
    }

    func testLearnsBigramsTrigramsAndPhrasesAfterThreshold() {
        let model = PersonalPredictionModel(store: nil)
        model.enabled = true

        // Sighting 1: bigram/trigram recorded, full phrase NOT yet surfaced
        model.observe(CommittedPhrase(text: "Em gửi báo cáo tiến độ Q4 nhé"), context: textEditCtx)
        let after1 = model.phraseContinuations(after: ["Em", "gửi"])
        XCTAssertTrue(after1.isEmpty, "full phrase needs at least 2 sightings")

        // Sighting 2: phrase reaches threshold and outranks generic continuations
        model.observe(CommittedPhrase(text: "Em gửi báo cáo tiến độ Q4 nhé"), context: textEditCtx)
        let after2 = model.phraseContinuations(after: ["Em", "gửi"])
        XCTAssertEqual(after2.first?.continuation, "báo cáo tiến độ Q4 nhé")

        let engine = PredictionEngine(corpus: BuiltInPredictionCorpus(data: .bundled),
                                      personal: model,
                                      dictionary: nil)
        let query = PredictionQuery(
            previousWords: ["em", "gửi"],
            currentWord: "",
            followsNonSpaceBreak: false,
            atWordStartAfterSpace: true,
            isVietnamese: true
        )
        let top = engine.predict(query)
        XCTAssertEqual(top.first?.display, "báo cáo tiến độ Q4 nhé")
        XCTAssertEqual(top.first?.isPersonal, true)
    }

    func testEncryptedPersistenceRoundTripAndEraseAll() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("prediction.bin")
        let store1 = KeychainEncryptedFileStore(url: url, keychainService: "test.predict")
        let m1 = PersonalPredictionModel(store: store1)
        m1.enabled = true
        m1.observe(CommittedPhrase(text: "Chiều nay họp team nhé"), context: textEditCtx)
        m1.observe(CommittedPhrase(text: "Chiều nay họp team nhé"), context: textEditCtx)

        // File must exist and NOT contain plaintext UTF-8
        let raw = try Data(contentsOf: url)
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("Chiều nay họp team"))

        // Reload in a fresh instance with a new store over same URL
        let store2 = KeychainEncryptedFileStore(url: url, keychainService: "test.predict")
        let m2 = PersonalPredictionModel(store: store2)
        m2.enabled = true
        let continuations = m2.phraseContinuations(after: ["Chiều", "nay"])
        XCTAssertEqual(continuations.first?.continuation, "họp team nhé")

        // Erase removes data and key files
        m2.eraseAll()
        XCTAssertTrue(m2.phraseContinuations(after: ["Chiều", "nay"]).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testExcludesSensitiveContextsAndSecrets() {
        let model = PersonalPredictionModel(store: nil)
        model.enabled = true

        // Excluded contexts
        let contexts = [
            LearnContext(bundleID: "com.apple.TextEdit", secureInput: true, secureField: false, now: Date()),
            LearnContext(bundleID: "com.apple.TextEdit", secureInput: false, secureField: true, now: Date()),
            LearnContext(bundleID: "com.apple.Terminal", secureInput: false, secureField: false, now: Date()),
            LearnContext(bundleID: "com.1password.1password", secureInput: false, secureField: false, now: Date()),
            LearnContext(bundleID: nil, secureInput: false, secureField: false, now: Date()),
        ]
        for ctx in contexts {
            model.observe(CommittedPhrase(text: "mật khẩu bí mật"), context: ctx)
            model.observe(CommittedPhrase(text: "mật khẩu bí mật"), context: ctx)
        }

        // Sensitive numbers and password-shaped tokens in normal app
        model.observe(CommittedPhrase(text: "mã otp là 482910"), context: textEditCtx)
        model.observe(CommittedPhrase(text: "mã otp là 482910"), context: textEditCtx)
        model.observe(CommittedPhrase(text: "mật khẩu P@ssw0rd123"), context: textEditCtx)
        model.observe(CommittedPhrase(text: "mật khẩu P@ssw0rd123"), context: textEditCtx)

        XCTAssertEqual(model.stats.bigramCount, 0)
        XCTAssertEqual(model.stats.phraseCount, 0)
    }
}
