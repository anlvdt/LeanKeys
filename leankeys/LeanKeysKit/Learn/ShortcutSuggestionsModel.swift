import Combine
import Foundation

/// What `ShortcutSuggestionsModel` needs from `PhraseLearner`, so tests can count calls if they want to.
public protocol PhraseLearning: AnyObject {
    var enabled: Bool { get set }
    var excludedBundleIDs: Set<String> { get set }
    var ready: [Candidate] { get }
    func observe(_ phrase: CommittedPhrase, context: LearnContext)
    func accept(_ c: Candidate)
    func dismiss(_ c: Candidate)
    func eraseAll()
}

extension PhraseLearner: PhraseLearning {}

/// One line of the suggestions list: a learned phrase and the trigger (tên tắt) offered for it.
public struct SuggestionRow: Identifiable, Equatable {
    public let candidate: Candidate
    public var trigger: String
    public var id: String { candidate.id }
}

public enum LearnEnableResult: Equatable {
    case enabled, disabled
    /// First time on: the explanation sheet must be confirmed (`confirmConsent()`) before anything is learned.
    case needsConsent
}

/// Drives 4B: the "Đề xuất gõ tắt" switch and its first-time consent, the learner settings, and the suggestions list.
///
/// Threading (ruling R9): the `PhraseLearner` is created and used only inside `onLearnerQueue` (a serial background
/// queue in the app), so observing, file I/O and Keychain access never run on the event-tap thread. Everything
/// `@Published` lives on main; the learner's `ready` list is read on the queue and handed to main with `onMain`.
/// Trigger names are computed on main (`prepareSuggestions()`), only when the list opens (rulings R16, R19).
/// Phrase text is never logged.
public final class ShortcutSuggestionsModel: ObservableObject {
    public static let enabledKey = "LeanKeys.learn.enabled"
    public static let consentKey = "LeanKeys.learn.consented"
    public static let thresholdKey = "LeanKeys.learn.threshold"
    public static let excludedAppsKey = "LeanKeys.learn.excludedApps"
    public static let defaultThreshold = 3
    public static let thresholdChoices = [2, 3, 4, 5]

    static let takenMessage = "Tên tắt này đã có"
    static let invalidMessage = "Tên tắt không được trống hay có dấu cách"

    /// Learning is on (consent given). Mirrored on main so a phrase costs nothing while it is off.
    @Published public private(set) var enabled: Bool
    /// The explanation sheet is up, waiting for `confirmConsent()` or `cancelConsent()`.
    @Published public private(set) var consentPending = false
    /// Learned phrases at the threshold, not yet added or dismissed. Most seen first.
    @Published public private(set) var candidates: [Candidate] = []
    /// The open suggestions list, with a trigger for each candidate (see `prepareSuggestions()`).
    @Published public private(set) var rows: [SuggestionRow] = []
    /// Apps the user excluded, on top of `Exclusions.defaultBundleIDs`.
    @Published public private(set) var userExcludedApps: [String]
    /// Sightings needed in 30 days before a phrase is suggested. Changing it keeps the counts.
    @Published public var threshold: Int {
        didSet {
            guard threshold != oldValue else { return }
            defaults.set(threshold, forKey: Self.thresholdKey)
            let threshold = threshold, excluded = excludedBundleIDs, on = enabled
            onLearnerQueue { [self] in
                // The old learner is dropped as is: turning it off would wipe the texts (R11).
                guard learner != nil else { return }
                let next = makeLearner(threshold)
                next.excludedBundleIDs = excluded
                if on { next.enabled = true }
                learner = next
                publishReady(next)
            }
        }
    }

    /// The app's current gõ tắt triggers. Set by the app.
    public var existingTriggers: () -> [String] = { [] }
    /// Adds a gõ tắt to the app's store (which saves it and syncs both engines); false when it was refused.
    public var addShortcut: (_ trigger: String, _ text: String) -> Bool = { _, _ in false }
    /// Phrases typed in LeanKeys itself (the Sửa field) are not learned.
    public var ownBundleID: String? = Bundle.main.bundleIdentifier

    public var suggestionCount: Int { candidates.count }
    public var excludedBundleIDs: Set<String> { Exclusions.defaultBundleIDs.union(userExcludedApps) }

    private let defaults: UserDefaults
    private let makeLearner: (Int) -> PhraseLearning
    private let eraseStore: () -> Void
    private let onLearnerQueue: (@escaping () -> Void) -> Void
    private let onMain: (@escaping () -> Void) -> Void
    private let suggest: (Candidate, Set<String>) -> String
    /// Reads where the user is typing; main thread, called only while enabled.
    var contextReader: () -> LearnContext = { LearnContext(bundleID: nil, secureInput: true, secureField: true, now: Date()) }

    /// Learner-queue state: touched only inside `onLearnerQueue`.
    private var learner: PhraseLearning?
    /// Main: ids added or dismissed here, filtered out of any `ready` list still on its way from the queue.
    private var handled: Set<String> = []

    /// - Parameters:
    ///   - makeLearner: builds a learner with the given threshold; runs on the learner queue.
    ///   - eraseStore: erases the saved data and keys when no learner exists yet; runs on the learner queue.
    ///   - onLearnerQueue: runs work on the serial learner queue.
    ///   - onMain: runs work on main.
    ///   - suggest: a trigger for a candidate, avoiding the given lowercased triggers; main thread.
    public init(
        defaults: UserDefaults = .standard,
        makeLearner: @escaping (Int) -> PhraseLearning,
        eraseStore: @escaping () -> Void,
        onLearnerQueue: @escaping (@escaping () -> Void) -> Void,
        onMain: @escaping (@escaping () -> Void) -> Void,
        suggest: @escaping (Candidate, Set<String>) -> String = { Abbreviation.suggest(for: $0, existing: $1) }
    ) {
        self.defaults = defaults
        self.makeLearner = makeLearner
        self.eraseStore = eraseStore
        self.onLearnerQueue = onLearnerQueue
        self.onMain = onMain
        self.suggest = suggest
        let storedThreshold = defaults.integer(forKey: Self.thresholdKey)
        threshold = Self.thresholdChoices.contains(storedThreshold) ? storedThreshold : Self.defaultThreshold
        userExcludedApps = defaults.stringArray(forKey: Self.excludedAppsKey) ?? []
        enabled = defaults.bool(forKey: Self.enabledKey) && defaults.bool(forKey: Self.consentKey)
        if enabled { startLearning() }
    }

    // MARK: Switch and consent

    /// The "Đề xuất gõ tắt" switch. The first time on returns `.needsConsent` and changes nothing yet.
    @discardableResult
    public func setEnabled(_ on: Bool) -> LearnEnableResult {
        if on {
            guard defaults.bool(forKey: Self.consentKey) else {
                consentPending = true
                return .needsConsent
            }
            if !enabled { apply(true) }
            return .enabled
        }
        consentPending = false
        if enabled { apply(false) }
        return .disabled
    }

    /// The user agreed on the explanation sheet: learning starts.
    public func confirmConsent() {
        defaults.set(true, forKey: Self.consentKey)
        consentPending = false
        if !enabled { apply(true) }
    }

    /// The user closed the explanation sheet without agreeing: learning stays off.
    public func cancelConsent() {
        consentPending = false
    }

    private func apply(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: Self.enabledKey)
        if on {
            startLearning()
            return
        }
        candidates = []
        rows = []
        onLearnerQueue { [self] in
            // Off also wipes every stored text (R11).
            learner?.enabled = false
        }
    }

    private func startLearning() {
        let threshold = threshold, excluded = excludedBundleIDs
        onLearnerQueue { [self] in
            let learner = learnerOnQueue(threshold: threshold, excluded: excluded)
            learner.enabled = true
            publishReady(learner)
        }
    }

    // MARK: Learning

    /// Hooks the router's mirror up to this model and takes the app's gõ tắt store. Main thread.
    public func start(router: EngineRouter,
                      existingTriggers: @escaping () -> [String],
                      addShortcut: @escaping (String, String) -> Bool) {
        self.existingTriggers = existingTriggers
        self.addShortcut = addShortcut
        contextReader = LearnContextReader.current
        router.mirror.onPhrase = { [weak self] phrase in self?.phraseCommitted(phrase) }
    }

    /// From the mirror, on the event-tap (main) thread: nothing while off; otherwise read the context and hop.
    func phraseCommitted(_ phrase: CommittedPhrase) {
        guard enabled else { return }
        observe(phrase, context: contextReader())
    }

    /// Main thread. Hands the phrase to the learner queue unless learning is off or it was typed in LeanKeys.
    public func observe(_ phrase: CommittedPhrase, context: LearnContext) {
        guard enabled, context.bundleID == nil || context.bundleID != ownBundleID else { return }
        onLearnerQueue { [self] in
            guard let learner, learner.enabled else { return }
            learner.observe(phrase, context: context)
            publishReady(learner)
        }
    }

    /// Learner queue.
    private func learnerOnQueue(threshold: Int, excluded: Set<String>) -> PhraseLearning {
        if let learner { return learner }
        let made = makeLearner(threshold)
        made.excludedBundleIDs = excluded
        learner = made
        return made
    }

    /// Learner queue: reads `ready` and hands it to main.
    private func publishReady(_ learner: PhraseLearning) {
        let ready = learner.ready
        onMain { [weak self] in self?.publish(ready) }
    }

    /// Main thread.
    func publish(_ ready: [Candidate]) {
        guard enabled else {
            candidates = []
            rows = []
            return
        }
        candidates = ready.filter { !handled.contains($0.id) }
        let ids = Set(candidates.map(\.id))
        if rows.contains(where: { !ids.contains($0.id) }) { rows.removeAll { !ids.contains($0.id) } }
    }

    // MARK: Suggestions list

    /// Gives every candidate a free trigger: none taken by an existing gõ tắt or by an earlier row. Main thread,
    /// called when the list opens (the engine replay resets the typing context, as the click that opened it did).
    public func prepareSuggestions() {
        var taken = Set(existingTriggers().map { $0.lowercased() })
        rows = candidates.map { candidate in
            let trigger = suggest(candidate, taken)
            taken.insert(trigger.lowercased())
            return SuggestionRow(candidate: candidate, trigger: trigger)
        }
    }

    /// "Sửa": changes a row's trigger. Returns the reason when refused (empty, has a space, or already used).
    @discardableResult
    public func edit(_ row: SuggestionRow, trigger: String) -> String? {
        let trigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = problem(with: trigger, for: row.id) { return problem }
        guard let i = rows.firstIndex(where: { $0.id == row.id }) else { return nil }
        rows[i].trigger = trigger
        return nil
    }

    /// "Thêm": adds the gõ tắt to the app's store and forgets the phrase. Returns the reason when refused.
    @discardableResult
    public func accept(_ row: SuggestionRow) -> String? {
        let current = rows.first { $0.id == row.id } ?? row
        if let problem = problem(with: current.trigger, for: row.id) { return problem }
        guard addShortcut(current.trigger, current.candidate.text) else { return Self.takenMessage }
        finish(current) { $0.accept($1) }
        refreshTakenTriggers()
        return nil
    }

    /// "Bỏ qua": never suggest this phrase again.
    public func dismiss(_ row: SuggestionRow) {
        finish(row) { $0.dismiss($1) }
    }

    private func finish(_ row: SuggestionRow, _ action: @escaping (PhraseLearning, Candidate) -> Void) {
        handled.insert(row.id)
        rows.removeAll { $0.id == row.id }
        candidates.removeAll { $0.id == row.id }
        let candidate = row.candidate
        onLearnerQueue { [self] in
            guard let learner else { return }
            action(learner, candidate)
            publishReady(learner)
        }
    }

    /// After an add, a row whose trigger is now used gets a new one.
    private func refreshTakenTriggers() {
        var taken = Set(existingTriggers().map { $0.lowercased() })
        for i in rows.indices {
            if taken.contains(rows[i].trigger.lowercased()) {
                let others = Set(rows.enumerated().filter { $0.offset != i }.map { $0.element.trigger.lowercased() })
                rows[i].trigger = suggest(rows[i].candidate, taken.union(others))
            }
            taken.insert(rows[i].trigger.lowercased())
        }
    }

    private func problem(with trigger: String, for id: String) -> String? {
        guard !trigger.isEmpty, !trigger.contains(where: \.isWhitespace) else { return Self.invalidMessage }
        let lower = trigger.lowercased()
        if existingTriggers().contains(where: { $0.lowercased() == lower }) { return Self.takenMessage }
        if rows.contains(where: { $0.id != id && $0.trigger.lowercased() == lower }) { return Self.takenMessage }
        return nil
    }

    // MARK: Settings

    /// "Xoá dữ liệu đã học": counts, texts, dismissals, the file and its keys.
    public func eraseAll() {
        handled = []
        candidates = []
        rows = []
        onLearnerQueue { [self] in
            if let learner {
                learner.eraseAll()
            } else {
                eraseStore()
            }
        }
    }

    public func addExcludedApp(_ bundleID: String) {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !excludedBundleIDs.contains(id) else { return }
        userExcludedApps.append(id)
        excludedAppsChanged()
    }

    /// Only apps the user added; the defaults stay.
    public func removeExcludedApp(_ bundleID: String) {
        guard userExcludedApps.contains(bundleID) else { return }
        userExcludedApps.removeAll { $0 == bundleID }
        excludedAppsChanged()
    }

    private func excludedAppsChanged() {
        defaults.set(userExcludedApps, forKey: Self.excludedAppsKey)
        let excluded = excludedBundleIDs
        onLearnerQueue { [self] in learner?.excludedBundleIDs = excluded }
    }
}

extension ShortcutSuggestionsModel {
    /// The app's model: one serial background queue owns the learner and its Keychain-backed encrypted file.
    public static let shared: ShortcutSuggestionsModel = {
        let queue = DispatchQueue(label: "io.github.anlvdt.leankeys.learn", qos: .utility)
        // Made on the queue the first time it is needed, so a user who never turns learning on touches no Keychain.
        final class StoreBox {
            private var store: KeychainEncryptedFileStore?
            var value: KeychainEncryptedFileStore {
                if let store { return store }
                let made = KeychainEncryptedFileStore(url: KeychainEncryptedFileStore.defaultURL)
                store = made
                return made
            }
        }
        let box = StoreBox()
        return ShortcutSuggestionsModel(
            makeLearner: { PhraseLearner(store: box.value, threshold: $0) },
            eraseStore: { try? box.value.erase() },
            onLearnerQueue: { queue.async(execute: $0) },
            onMain: { DispatchQueue.main.async(execute: $0) }
        )
    }()
}
