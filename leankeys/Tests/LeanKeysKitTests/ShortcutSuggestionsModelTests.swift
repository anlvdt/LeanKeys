import XCTest
@testable import LeanKeysKit

/// The model with a real PhraseLearner on an in-memory store. Work meant for the learner queue and for main runs
/// right away, so each call has finished when it returns.
final class ShortcutSuggestionsModelTests: XCTestCase {
    private final class MemoryStore: LearnStore, LearnKeyProvider {
        var data: Data?
        var erased = 0
        func load() throws -> Data? { data }
        func save(_ data: Data) throws { self.data = data }
        func erase() throws {
            data = nil
            erased += 1
        }
        func hmacKey() throws -> Data { Data(repeating: 7, count: 32) }
    }

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: MemoryStore!
    private var added: [(String, String)] = []
    private var existing: [String] = []
    private var learnersMade = 0

    override func setUp() {
        super.setUp()
        suiteName = "ShortcutSuggestionsModelTests"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = MemoryStore()
        added = []
        existing = []
        replacements = []
        learnersMade = 0
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private var replacements: [String] = []

    private func makeModel(onLearnerQueue: @escaping (@escaping () -> Void) -> Void = { $0() }) -> ShortcutSuggestionsModel {
        let model = ShortcutSuggestionsModel(
            defaults: defaults,
            makeLearner: { [unowned self] threshold in
                learnersMade += 1
                return PhraseLearner(store: store, threshold: threshold)
            },
            eraseStore: { [unowned self] in try? store.erase() },
            onLearnerQueue: onLearnerQueue,
            onMain: { $0() },
            suggest: { candidate, taken in Abbreviation.suggest(for: candidate, existing: taken) }
        )
        model.existingTriggers = { [unowned self] in existing }
        model.existingReplacements = { [unowned self] in replacements }
        model.addShortcut = { [unowned self] trigger, text in
            added.append((trigger, text))
            existing.append(trigger)
            return true
        }
        return model
    }

    private let notes = LearnContext(bundleID: "com.apple.Notes", secureInput: false, secureField: false, now: Date())

    private func type(_ text: String, times: Int = 3, into model: ShortcutSuggestionsModel) {
        for _ in 0..<times { model.observe(CommittedPhrase(text: text), context: notes) }
    }

    private func enabledModel() -> ShortcutSuggestionsModel {
        let model = makeModel()
        XCTAssertEqual(model.setEnabled(true), .needsConsent)
        model.confirmConsent()
        XCTAssertTrue(model.enabled)
        return model
    }

    func testAcceptAddsShortcutAndClearsCandidate() throws {
        let model = enabledModel()
        type("0912 345 678", into: model)
        XCTAssertEqual(model.suggestionCount, 1)

        model.prepareSuggestions()
        let row = try XCTUnwrap(model.rows.first)
        XCTAssertEqual(row.trigger, "sdt")
        XCTAssertNil(model.accept(row))

        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.0, "sdt")
        XCTAssertEqual(added.first?.1, "0912 345 678")
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.suggestionCount, 0)

        // Never suggested again.
        type("0912 345 678", into: model)
        XCTAssertEqual(model.suggestionCount, 0)
    }

    func testTwoCandidatesGetDistinctTriggers() {
        let model = enabledModel()
        type("0912 345 678", into: model)
        type("0987 654 321", into: model)
        model.prepareSuggestions()
        XCTAssertEqual(Set(model.rows.map(\.trigger)), ["sdt", "sdt2"])
    }

    func testAcceptRefusesTakenTriggerCaseInsensitively() throws {
        existing = ["SDT"]
        let model = enabledModel()
        type("0912 345 678", into: model)
        model.prepareSuggestions()
        let row = try XCTUnwrap(model.rows.first)
        XCTAssertEqual(row.trigger, "sdt2", "suggest skips a trigger already used, whatever its case")

        XCTAssertNotNil(model.edit(row, trigger: "Sdt"), "an edit to a used trigger is refused")
        XCTAssertEqual(model.rows.first?.trigger, "sdt2")
        XCTAssertTrue(added.isEmpty)
    }

    func testEditChangesTrigger() throws {
        let model = enabledModel()
        type("0912 345 678", into: model)
        model.prepareSuggestions()
        let row = try XCTUnwrap(model.rows.first)

        XCTAssertNil(model.edit(row, trigger: " didong "))
        let edited = try XCTUnwrap(model.rows.first)
        XCTAssertEqual(edited.trigger, "didong")
        XCTAssertNotNil(model.edit(edited, trigger: ""), "an empty trigger is refused")
        XCTAssertNotNil(model.edit(edited, trigger: "di dong"), "a trigger with a space is refused")

        XCTAssertNil(model.accept(try XCTUnwrap(model.rows.first)))
        XCTAssertEqual(added.first?.0, "didong")
        XCTAssertEqual(added.first?.1, "0912 345 678")
    }

    func testDismissHides() throws {
        let model = enabledModel()
        type("0912 345 678", into: model)
        model.prepareSuggestions()
        model.dismiss(try XCTUnwrap(model.rows.first))

        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertEqual(model.suggestionCount, 0)
        XCTAssertTrue(added.isEmpty)
        type("0912 345 678", into: model)
        XCTAssertEqual(model.suggestionCount, 0, "a dismissed phrase is never suggested again")
    }

    func testToggleOffStopsObserving() {
        let model = enabledModel()
        type("0912 345 678", into: model)
        XCTAssertEqual(model.suggestionCount, 1)

        XCTAssertEqual(model.setEnabled(false), .disabled)
        XCTAssertFalse(model.enabled)
        XCTAssertEqual(model.suggestionCount, 0, "turning off drops the candidates shown")
        let raw = String(decoding: store.data ?? Data(), as: UTF8.self)
        XCTAssertFalse(raw.contains("0912"), "turning off wipes the stored text (R11)")

        type("0987 654 321", times: 5, into: model)
        XCTAssertEqual(model.suggestionCount, 0)

        // On again: no second consent, and what was typed while off was not counted.
        XCTAssertEqual(model.setEnabled(true), .enabled)
        type("0987 654 321", times: 2, into: model)
        XCTAssertEqual(model.suggestionCount, 0)
    }

    func testFirstEnableRequiresConsent() {
        let model = makeModel()
        XCTAssertFalse(model.enabled, "off by default")
        XCTAssertEqual(model.setEnabled(true), .needsConsent)
        XCTAssertTrue(model.consentPending)
        XCTAssertFalse(model.enabled)
        XCTAssertEqual(learnersMade, 0, "nothing touches the store before consent")
        type("0912 345 678", into: model)
        XCTAssertEqual(model.suggestionCount, 0)

        model.cancelConsent()
        XCTAssertFalse(model.consentPending)
        XCTAssertFalse(model.enabled)
        XCTAssertEqual(model.setEnabled(true), .needsConsent, "cancelled consent is asked again")

        model.confirmConsent()
        XCTAssertFalse(model.consentPending)
        XCTAssertTrue(model.enabled)

        // Persisted: a new model starts enabled and does not ask again.
        let again = makeModel()
        XCTAssertTrue(again.enabled)
        XCTAssertEqual(again.setEnabled(false), .disabled)
        XCTAssertEqual(again.setEnabled(true), .enabled)
    }

    func testEraseAllEmptiesList() {
        let model = enabledModel()
        type("0912 345 678", into: model)
        model.eraseAll()
        XCTAssertEqual(model.suggestionCount, 0)
        XCTAssertEqual(store.erased, 1)
        XCTAssertNil(store.data)
    }

    func testEraseWithoutLearnerErasesStore() {
        let model = makeModel()
        model.eraseAll()
        XCTAssertEqual(store.erased, 1)
        XCTAssertEqual(learnersMade, 0, "erasing never creates a learner (or a Keychain key)")
    }

    func testThresholdChangeKeepsCounts() {
        let model = enabledModel()
        type("0912 345 678", times: 2, into: model)
        XCTAssertEqual(model.suggestionCount, 0)
        model.threshold = 2
        XCTAssertEqual(model.threshold, 2)
        type("0912 345 678", times: 1, into: model)
        XCTAssertEqual(model.suggestionCount, 1)
    }

    func testExcludedAppsAreNotLearned() {
        let model = enabledModel()
        model.addExcludedApp("com.example.secret")
        XCTAssertTrue(model.excludedBundleIDs.contains("com.example.secret"))
        XCTAssertTrue(model.excludedBundleIDs.isSuperset(of: Exclusions.defaultBundleIDs))
        XCTAssertTrue(Exclusions.defaultBundleIDs.isSuperset(of: ["com.agilebits.onepassword7", "org.keepassxc.keepassxc"]),
                      "ruling R22")
        let secret = LearnContext(bundleID: "com.example.secret", secureInput: false, secureField: false, now: Date())
        for _ in 0..<3 { model.observe(CommittedPhrase(text: "0912 345 678"), context: secret) }
        XCTAssertEqual(model.suggestionCount, 0)

        model.removeExcludedApp("com.example.secret")
        model.removeExcludedApp("com.1password.1password")
        XCTAssertTrue(model.excludedBundleIDs.contains("com.1password.1password"), "defaults cannot be removed")
        for _ in 0..<3 { model.observe(CommittedPhrase(text: "0912 345 678"), context: secret) }
        XCTAssertEqual(model.suggestionCount, 1)
    }

    func testOwnAppIsNotLearned() {
        let model = enabledModel()
        model.ownBundleID = "io.github.anlvdt.leankeys"
        let own = LearnContext(bundleID: "io.github.anlvdt.leankeys", secureInput: false, secureField: false, now: Date())
        for _ in 0..<3 { model.observe(CommittedPhrase(text: "0912 345 678"), context: own) }
        XCTAssertEqual(model.suggestionCount, 0)
    }

    func testStaleSnapshotDoesNotBringBackHandledRow() throws {
        let model = enabledModel()
        type("0912 345 678", into: model)
        model.prepareSuggestions()
        let row = try XCTUnwrap(model.rows.first)
        let stale = model.candidates
        model.dismiss(row)
        model.publish(stale)
        XCTAssertEqual(model.suggestionCount, 0)
    }

    /// An expansion reaches the mirror as typed text: `sdt` + Return three times must not suggest the number.
    func testExpandedShortcutIsNotSuggested() {
        existing = ["sdt"]
        replacements = ["0912 345 678"]
        let model = enabledModel()
        type("0912  345 678", into: model)
        XCTAssertEqual(model.suggestionCount, 0)
        // Dismissed in the learner: removing the gõ tắt later does not bring it back.
        replacements = []
        type("0912 345 678", into: model)
        XCTAssertEqual(model.suggestionCount, 0)
    }

    func testPhraseHoldingLongReplacementIsNotSuggested() {
        replacements = ["Số 1 đường Mẫu", "ok"]
        let model = enabledModel()
        type("Gửi về số 1 đường mẫu giúp em", into: model)
        XCTAssertEqual(model.suggestionCount, 0, "a phrase holding an 8+ character replacement")
        type("ok anh nhé, mai gặp", into: model)
        XCTAssertEqual(model.suggestionCount, 1, "a replacement under 8 characters inside a phrase is fine")
    }

    func testShortcutAddedLaterHidesRowWhenListOpens() {
        let model = enabledModel()
        type("0912 345 678", into: model)
        XCTAssertEqual(model.suggestionCount, 1)
        replacements = ["0912 345 678"]
        model.prepareSuggestions()
        XCTAssertTrue(model.rows.isEmpty)
    }

    /// An observe queued before an erase publishes its text when it runs; the erase must publish last.
    func testEraseIsTheLastPublish() {
        var pending: [() -> Void] = []
        let model = makeModel(onLearnerQueue: { pending.append($0) })
        model.setEnabled(true)
        model.confirmConsent()
        func drain() { while !pending.isEmpty { pending.removeFirst()() } }
        drain()
        type("0912 345 678", into: model)
        model.eraseAll()
        XCTAssertEqual(model.suggestionCount, 0)
        drain()
        XCTAssertEqual(model.suggestionCount, 0, "queued observes ran before the erase; the erase published last")
        XCTAssertEqual(store.erased, 1)
    }

    // MARK: The AX secure-field read stays off the key thread (audit item 4)

    /// A model whose learner queue holds its work until `drain`, with a probe for Notes and a counted AX check.
    private final class KeyPath {
        var pending: [() -> Void] = []
        var axReads = 0
        var secure = false
        var probe = LearnContextProbe(bundleID: "com.apple.Notes", pid: 2, secureInput: false, now: Date())
        func drain() { while !pending.isEmpty { pending.removeFirst()() } }
    }

    private func keyPathModel(_ path: KeyPath) -> ShortcutSuggestionsModel {
        let model = makeModel(onLearnerQueue: { path.pending.append($0) })
        model.setEnabled(true)
        model.confirmConsent()
        path.drain()
        model.contextProbe = { path.probe }
        model.secureField = { _ in
            path.axReads += 1
            return path.secure
        }
        return model
    }

    func testPhraseCommittedReadsSecureFieldOnTheLearnerQueueOnly() {
        let path = KeyPath()
        let model = keyPathModel(path)
        for _ in 0..<3 { model.phraseCommitted(CommittedPhrase(text: "0912 345 678")) }
        XCTAssertEqual(path.axReads, 0, "the key path reads no AX")
        XCTAssertEqual(path.pending.count, 3)
        path.drain()
        XCTAssertEqual(path.axReads, 3)
        XCTAssertEqual(model.suggestionCount, 1)
    }

    func testSecureFieldOnTheLearnerQueueDropsThePhrase() {
        let path = KeyPath()
        path.secure = true
        let model = keyPathModel(path)
        for _ in 0..<3 { model.phraseCommitted(CommittedPhrase(text: "0912 345 678")) }
        path.drain()
        XCTAssertEqual(path.axReads, 3)
        XCTAssertEqual(model.suggestionCount, 0)
        path.secure = false
        for _ in 0..<3 { model.phraseCommitted(CommittedPhrase(text: "0912 345 678")) }
        path.drain()
        XCTAssertEqual(model.suggestionCount, 1, "nothing was counted while the field was secure")
    }

    /// Secure Input, excluded apps and LeanKeys itself are decided on the key thread: nothing is queued.
    func testExclusionsDecidedBeforeQueueing() {
        let path = KeyPath()
        let model = keyPathModel(path)
        model.ownBundleID = "io.github.anlvdt.leankeys"
        model.addExcludedApp("com.example.secret")
        path.drain()
        for probe in [
            LearnContextProbe(bundleID: "com.apple.Notes", pid: 2, secureInput: true, now: Date()),
            LearnContextProbe(bundleID: "com.1password.1password", pid: 2, secureInput: false, now: Date()),
            LearnContextProbe(bundleID: "com.example.secret", pid: 2, secureInput: false, now: Date()),
            LearnContextProbe(bundleID: "io.github.anlvdt.leankeys", pid: 2, secureInput: false, now: Date()),
            LearnContextProbe(bundleID: nil, pid: nil, secureInput: false, now: Date()),
        ] {
            path.probe = probe
            model.phraseCommitted(CommittedPhrase(text: "0912 345 678"))
        }
        XCTAssertTrue(path.pending.isEmpty)
        XCTAssertEqual(path.axReads, 0)
    }

    func testSuggestionLine() {
        XCTAssertNil(StatusPopoverModel.suggestionLine(count: 0))
        XCTAssertEqual(StatusPopoverModel.suggestionLine(count: 2), "Có 2 gợi ý gõ tắt")
    }
}
