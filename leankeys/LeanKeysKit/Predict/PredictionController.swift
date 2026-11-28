import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

/// Coordinates 4A+ Laban Key-style next-word, phrase, and sentence predictions, personal encrypted learning,
/// and the non-activating floating candidate bar.
///
/// Privacy (spec 2026-11-28-privacy-opt-in & 2026-11-28-prediction-4a):
/// - Both `enabled` (showing suggestions) and `learnEnabled` (recording personal phrases/n-grams) are OFF by default.
/// - Turning `learnEnabled` ON for the first time returns `.needsConsent` and explains data stays encrypted locally.
/// - Zero files are created until `learnEnabled` is consented AND valid non-sensitive typing is observed.
public final class PredictionController: ObservableObject {
    public static let enabledKey = "LeanKeys.predict.enabled"
    public static let learnKey = "LeanKeys.predict.learn"
    public static let learnConsentKey = "LeanKeys.predict.learnConsented"

    @Published public private(set) var enabled: Bool
    @Published public private(set) var learnEnabled: Bool
    @Published public private(set) var learnConsentPending = false
    @Published public private(set) var learnedBigramCount = 0
    @Published public private(set) var learnedPhraseCount = 0

    /// Cached on main for fast check inside keyboard event tap.
    public private(set) var currentCandidates: [PredictionCandidate] = []
    public var isVisible: Bool { panel.isVisible && !currentCandidates.isEmpty }

    public func containsScreenPoint(_ point: CGPoint) -> Bool {
        isVisible && panel.containsScreenPoint(point)
    }

    public var ownBundleID: String? = Bundle.main.bundleIdentifier
    public var excludedBundleIDs: Set<String> {
        Exclusions.defaultBundleIDs.union(defaults.stringArray(forKey: ShortcutSuggestionsModel.excludedAppsKey) ?? [])
    }

    private let defaults: UserDefaults
    private let personal: PersonalPredictionModel
    private let engine: PredictionEngine
    private let panel: CandidatePanelController
    private let onLearnerQueue: (@escaping () -> Void) -> Void
    private let onMain: (@escaping () -> Void) -> Void

    private weak var router: EngineRouter?
    private var shortcutsProvider: () -> [(trigger: String, replacement: String)] = { [] }
    private var injectText: (_ deleteCount: Int, _ chars: [Character]) -> Void = { _, _ in }
    private var contextProbe: () -> LearnContextProbe = LearnContextReader.probe
    private var secureField: (LearnContextProbe) -> Bool = LearnContextReader.isSecureField
    private var caretAnchor: () -> CaretLocator.CaretAnchor? = { CaretLocator.currentAnchor() }

    private var appSwitchObserver: NSObjectProtocol?
    private var lastAnchor: CaretLocator.CaretAnchor?
    private var lastAnchorTime: CFAbsoluteTime = 0
    private var pendingRefresh: DispatchWorkItem?

    public init(
        defaults: UserDefaults = .standard,
        personal: PersonalPredictionModel,
        corpus: BuiltInPredictionCorpus = .shared,
        dictionary: DictionaryCompleting? = VikeyDictionaryCompleter.shared,
        panel: CandidatePanelController = CandidatePanelController(),
        onLearnerQueue: @escaping (@escaping () -> Void) -> Void,
        onMain: @escaping (@escaping () -> Void) -> Void
    ) {
        self.defaults = defaults
        self.personal = personal
        self.engine = PredictionEngine(corpus: corpus, personal: personal, dictionary: dictionary)
        self.panel = panel
        self.onLearnerQueue = onLearnerQueue
        self.onMain = onMain

        self.enabled = defaults.bool(forKey: Self.enabledKey)
        self.learnEnabled = defaults.bool(forKey: Self.learnKey) && defaults.bool(forKey: Self.learnConsentKey)
        if learnEnabled {
            onLearnerQueue { [weak self] in
                self?.personal.enabled = true
                self?.refreshStatsOnQueue()
            }
        }
    }

    // MARK: - Settings & Privacy Opt-In

    public func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        defaults.set(on, forKey: Self.enabledKey)
        if !on { hide() }
    }

    @discardableResult
    public func setLearnEnabled(_ on: Bool) -> LearnEnableResult {
        if on {
            guard defaults.bool(forKey: Self.learnConsentKey) else {
                learnConsentPending = true
                return .needsConsent
            }
            if !learnEnabled { applyLearn(true) }
            return .enabled
        }
        learnConsentPending = false
        if learnEnabled { applyLearn(false) }
        return .disabled
    }

    public func confirmLearnConsent() {
        defaults.set(true, forKey: Self.learnConsentKey)
        learnConsentPending = false
        if !learnEnabled { applyLearn(true) }
    }

    public func cancelLearnConsent() {
        learnConsentPending = false
    }

    public func eraseLearnedData() {
        onLearnerQueue { [weak self] in
            guard let self else { return }
            self.personal.eraseAll()
            self.refreshStatsOnQueue()
        }
    }

    private func applyLearn(_ on: Bool) {
        learnEnabled = on
        defaults.set(on, forKey: Self.learnKey)
        onLearnerQueue { [weak self] in
            guard let self else { return }
            self.personal.enabled = on
            self.refreshStatsOnQueue()
        }
    }

    private func refreshStatsOnQueue() {
        let st = personal.stats
        onMain { [weak self] in
            self?.learnedBigramCount = st.bigramCount
            self?.learnedPhraseCount = st.phraseCount
        }
    }

    // MARK: - Lifecycle Wiring

    public func start(
        router: EngineRouter,
        shortcuts: @escaping () -> [(trigger: String, replacement: String)],
        inject: @escaping (_ deleteCount: Int, _ chars: [Character]) -> Void
    ) {
        self.router = router
        self.shortcutsProvider = shortcuts
        self.injectText = inject
        router.mirror.addPhraseObserver { [weak self] phrase in
            self?.phraseCommitted(phrase)
        }
        if appSwitchObserver == nil {
            appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.lastAnchor = nil
                self?.hide()
            }
        }
    }

    func phraseCommitted(_ phrase: CommittedPhrase) {
        guard learnEnabled else { return }
        let probe = contextProbe()
        guard !probe.secureInput, let bundleID = probe.bundleID,
              bundleID != ownBundleID,
              !excludedBundleIDs.contains(bundleID),
              !Exclusions.isExcludedByDefault(bundleID) else { return }
        let secureField = self.secureField
        onLearnerQueue { [weak self] in
            guard let self, self.personal.enabled, !secureField(probe) else { return }
            self.personal.observe(phrase, context: probe.context(secureField: false))
            self.refreshStatsOnQueue()
        }
    }

    // MARK: - Keystroke Handling & Display

    /// Schedules candidate bar update asynchronously so the CGEventTap callback returns immediately.
    public func scheduleRefresh(router: EngineRouter, bundleID: String?, isVietnamese: Bool, atWordStartAfterSpace: Bool) {
        guard enabled else {
            if isVisible { hide() }
            return
        }
        pendingRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.refreshNow(router: router, bundleID: bundleID, isVietnamese: isVietnamese,
                             atWordStartAfterSpace: atWordStartAfterSpace)
        }
        pendingRefresh = item
        DispatchQueue.main.async(execute: item)
    }

    func refreshNow(router: EngineRouter, bundleID: String?, isVietnamese: Bool, atWordStartAfterSpace: Bool) {
        guard enabled,
              !IsSecureEventInputEnabled(),
              let bundleID,
              bundleID != ownBundleID,
              !CodeApps.contains(bundleID),
              !KeyPassthrough.remoteBundleIDs.contains(bundleID),
              !KeyPassthrough.credentialAppBundleIDs.contains(bundleID),
              !Exclusions.passwordManagers.contains(bundleID) else {
            hide()
            return
        }

        let currentWord = router.mirror.currentWord
        let previousWords = router.mirror.recentWordsBeforeCurrent
        let followsBreak = router.mirror.currentWordFollowsBreak

        if currentWord.isEmpty && (!atWordStartAfterSpace || previousWords.isEmpty) {
            hide()
            return
        }
        if !currentWord.isEmpty && currentWord.count < PredictionEngine.minPrefixLength {
            hide()
            return
        }

        let query = PredictionQuery(
            previousWords: previousWords,
            currentWord: currentWord,
            followsNonSpaceBreak: followsBreak,
            atWordStartAfterSpace: atWordStartAfterSpace,
            isVietnamese: isVietnamese,
            shortcuts: shortcutsProvider()
        )
        let candidates = engine.predict(query)
        guard !candidates.isEmpty else {
            hide()
            return
        }

        // Reuse cached anchor for 80 ms on rapid typing to minimize AX IPC calls.
        let now = CFAbsoluteTimeGetCurrent()
        let anchor: CaretLocator.CaretAnchor?
        if let cached = lastAnchor, now - lastAnchorTime < 0.08 {
            anchor = cached
        } else {
            anchor = caretAnchor()
            lastAnchor = anchor
            lastAnchorTime = now
        }
        guard let anchor else {
            hide()
            return
        }

        currentCandidates = candidates
        panel.show(candidates: candidates, anchor: anchor) { [weak self] idx in
            self?.acceptFromClick(at: idx)
        }
    }

    /// Accepts candidate `index` (from Tab / ⌥1–⌥3 in the event tap). Returns the edit for `RustBridge` to inject.
    public func acceptCandidate(at index: Int, router: EngineRouter, isVietnamese: Bool) -> (Int, [Character])? {
        guard isVisible, index >= 0, index < currentCandidates.count else { return nil }
        let candidate = currentCandidates[index]
        let chars = Array(candidate.insertion)
        router.resetWordAfterPrediction(deleteCount: candidate.deleteCount, inserted: chars)
        currentCandidates = []
        lastAnchor = nil

        // Chain the next suggestion when the inserted text ends cleanly with whitespace.
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let endsWithSpace = candidate.insertion.last == " "
        if endsWithSpace {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.refreshNow(router: router, bundleID: bundleID, isVietnamese: isVietnamese,
                                 atWordStartAfterSpace: true)
            }
        } else {
            panel.hide()
        }
        return (candidate.deleteCount, chars)
    }

    private func acceptFromClick(at index: Int) {
        guard let router else { return }
        guard let (bs, chars) = acceptCandidate(at: index, router: router, isVietnamese: router.currentVietnamese) else { return }
        injectText(bs, chars)
    }

    public func dismiss() {
        hide()
    }

    public func hide() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        currentCandidates = []
        panel.hide()
    }
}

extension PredictionController {
    public static let shared: PredictionController = {
        let queue = DispatchQueue(label: "io.github.anlvdt.leankeys.predict", qos: .utility)
        let store = KeychainEncryptedFileStore(
            url: PersonalPredictionModel.defaultURL,
            keychainService: "io.github.anlvdt.leankeys.predict"
        )
        let personal = PersonalPredictionModel(store: store)
        return PredictionController(
            personal: personal,
            onLearnerQueue: { queue.async(execute: $0) },
            onMain: { DispatchQueue.main.async(execute: $0) }
        )
    }()
}
