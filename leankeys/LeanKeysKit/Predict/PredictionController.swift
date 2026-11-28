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
    private let quickType: AsyncPredictionSource?
    /// How long a refresh waits for QuickType before showing our rows alone (a late answer still merges in).
    static let quickTypeWait: TimeInterval = 0.025

    private weak var router: EngineRouter?
    private var shortcutsProvider: () -> [(trigger: String, replacement: String)] = { [] }
    private var injectText: (_ deleteCount: Int, _ chars: [Character]) -> Void = { _, _ in }
    private var contextProbe: () -> LearnContextProbe = LearnContextReader.probe
    private var secureField: (LearnContextProbe) -> Bool = LearnContextReader.isSecureField
    var caretAnchor: () -> CaretLocator.CaretAnchor? = { CaretLocator.currentAnchor() }

    private var appSwitchObserver: NSObjectProtocol?
    private let axQueue = DispatchQueue(label: "io.github.anlvdt.leankeys.predict.ax", qos: .userInteractive)
    private var lastAnchor: CaretLocator.CaretAnchor?
    private var lastAnchorTime: CFAbsoluteTime = 0
    private var pendingRefresh: DispatchWorkItem?
    private var refreshToken: UInt64 = 0
    private var navigator = SuggestionListNavigator()
    private var trace = PredictionTrace()

    /// One refresh waiting for its caret anchor and QuickType's answer (main thread only).
    private struct Pending {
        let token: UInt64
        let query: PredictionQuery
        let phase: PredictionPhase
        let ours: [PredictionCandidate]
        var quickType: [String]?
        var waitedOut = false
        var anchor: CaretLocator.CaretAnchor?
        var shown: [String]?
        var askedQuickType = false
    }
    private var pending: Pending?
    private var now: () -> CFAbsoluteTime = CFAbsoluteTimeGetCurrent

    public init(
        defaults: UserDefaults = .standard,
        personal: PersonalPredictionModel,
        corpus: BuiltInPredictionCorpus = .shared,
        dictionary: DictionaryCompleting? = VikeyDictionaryCompleter.shared,
        panel: CandidatePanelController = CandidatePanelController(),
        onLearnerQueue: @escaping (@escaping () -> Void) -> Void,
        onMain: @escaping (@escaping () -> Void) -> Void,
        quickType: AsyncPredictionSource? = nil
    ) {
        self.quickType = quickType
        self.defaults = defaults
        self.personal = personal
        // Google-style rows: a word grows into the phrase the user typed before (learned phrases only).
        self.engine = PredictionEngine(corpus: corpus, personal: personal, dictionary: dictionary,
                                       phraseExtension: .replace, minExtensionContext: 2, lookAhead: true)
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
        refreshToken &+= 1
        clearSelection()
        trace.scheduled()
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

        trace.refreshStarted()
        let currentWord = router.mirror.currentWord
        let previousWords = router.mirror.recentWordsBeforeCurrent
        let followsBreak = router.mirror.currentWordFollowsBreak

        if currentWord.isEmpty && (!atWordStartAfterSpace || previousWords.isEmpty) {
            hide()
            return
        }
        if !currentWord.isEmpty && currentWord.count < engine.minPrefix {
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
        trace.predicted()
        // QuickType only where its rows can pass `SuggestionGate`: completing the word being typed.
        let askQuickType = quickType != nil && engine.accepts(query)
            && query.currentWord.count >= SuggestionGate.minTypedLetters
        guard !candidates.isEmpty || askQuickType else {
            hide()
            return
        }

        refreshToken &+= 1
        let token = refreshToken
        let phase = engine.phase(of: query)
        pending = Pending(token: token, query: query, phase: phase, ours: candidates)
        pending?.askedQuickType = askQuickType

        if askQuickType, let quickType {
            let text = PredictionEngine.quickTypeText(for: query, phase: phase)
            quickType.request(text: text, vietnamese: isVietnamese) { [weak self] words in
                DispatchQueue.main.async { self?.quickTypeArrived(words, token: token) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.quickTypeWait) { [weak self] in
                guard let self, self.pending?.token == token else { return }
                self.pending?.waitedOut = true
                self.presentPending()
            }
        }

        let now = CFAbsoluteTimeGetCurrent()
        if let cached = lastAnchor, now - lastAnchorTime < 0.08 {
            trace.axCacheHit()
            pending?.anchor = cached
            presentPending()
            return
        }

        let locate = caretAnchor
        axQueue.async { [weak self] in
            let axStart = CFAbsoluteTimeGetCurrent()
            let resolved = locate()
            let axMs = (CFAbsoluteTimeGetCurrent() - axStart) * 1000
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.enabled, self.refreshToken == token else { self.trace.axDropped(); return }
                self.trace.axResolved(ms: axMs)
                self.lastAnchor = resolved
                self.lastAnchorTime = CFAbsoluteTimeGetCurrent()
                guard let resolved else {
                    self.pending = nil
                    self.panel.hide()
                    self.currentCandidates = []
                    return
                }
                self.pending?.anchor = resolved
                self.presentPending()
            }
        }
    }

    func quickTypeArrived(_ words: [String], token: UInt64) {
        guard pending?.token == token else { return }
        trace.quickTypeArrived()
        pending?.quickType = words
        presentPending()
    }

    /// Shows the pending refresh once its anchor is known and QuickType answered or `quickTypeWait` ran out, through
    /// `SuggestionGate`. Shown once: a QuickType answer that comes later is dropped, never redrawn (stable rows).
    private func presentPending() {
        guard var p = pending, p.token == refreshToken, let anchor = p.anchor, p.shown == nil else { return }
        let ready = !p.askedQuickType || p.quickType != nil || p.waitedOut
        guard ready else { return }
        let merged = p.quickType.map { PredictionEngine.merge(ours: p.ours, quickType: $0, phase: p.phase, query: p.query) } ?? p.ours
        let rows = SuggestionGate.apply(merged, phase: p.phase, query: p.query)
        p.shown = rows.map(\.display)
        pending = p
        guard !rows.isEmpty else {
            hideKeepingPending()
            return
        }
        present(candidates: rows, anchor: anchor, token: p.token)
    }

    private func hideKeepingPending() {
        currentCandidates = []
        navigator.listChanged(count: 0, at: now())
        panel.hide()
    }

    func present(candidates: [PredictionCandidate], anchor: CaretLocator.CaretAnchor, token: UInt64) {
        guard enabled, token == refreshToken else { return }
        if candidates.map(\.display) != currentCandidates.map(\.display) || !panel.isVisible {
            navigator.listChanged(count: candidates.count, at: now())
        }
        currentCandidates = candidates
        let showStart = CFAbsoluteTimeGetCurrent()
        panel.show(candidates: candidates, anchor: anchor, selectedIndex: navigator.selectedIndex) { [weak self] idx in
            self?.acceptFromClick(at: idx)
        }
        trace.shown(showMs: (CFAbsoluteTimeGetCurrent() - showStart) * 1000, rows: candidates.count)
    }

    /// Event-tap hook: a key reached the tap now (debug-log timing only).
    public func noteKeyEvent() {
        trace.keyEvent()
    }

    /// Test hook: shows `candidates` as if a refresh had just resolved the caret.
    func presentForTesting(_ candidates: [PredictionCandidate], anchor: CaretLocator.CaretAnchor,
                           clock: @escaping () -> CFAbsoluteTime) {
        now = clock
        present(candidates: candidates, anchor: anchor, token: refreshToken)
    }

    /// ↓ / ↑ / Tab / Enter / Esc while the list shows (spec 2026-11-28-prediction-dropdown). `.accept(i)` is left
    /// to the caller (`acceptCandidate`), which owns the injection; every other effect is applied here.
    public func handleListKey(_ key: SuggestionListKey) -> SuggestionListAction {
        guard isVisible else { return .pass }
        let action = navigator.handle(key, now: now())
        switch action {
        case .swallow:
            panel.setSelectedIndex(navigator.selectedIndex)
        case .passAndHide, .dismiss:
            hide()
        case .pass, .accept:
            break
        }
        return action
    }

    /// ↓ ↑ Tab Return Enter(keypad) Esc: every other key clears the selection before the event tap handles it.
    public static let listKeyCodes: Set<UInt16> = [0x7D, 0x7E, 0x30, 0x24, 0x4C, 0x35]

    /// Any key but a list key reached the tap: whatever path it takes next, a row picked before it is void.
    public func clearSelection() {
        guard navigator.selectedIndex != nil else { return }
        navigator.typing()
        panel.setSelectedIndex(nil)
    }

    /// Row the user moved to with ↓/↑, if any.
    public var selectedIndex: Int? { isVisible ? navigator.selectedIndex : nil }

    /// Accepts candidate `index` (from Tab / ⌥1–⌥3 in the event tap). Returns the edit for `RustBridge` to inject.
    public func acceptCandidate(at index: Int, router: EngineRouter, isVietnamese: Bool) -> (Int, [Character])? {
        guard isVisible, index >= 0, index < currentCandidates.count else { return nil }
        let candidate = currentCandidates[index]
        let chars = Array(candidate.insertion)
        router.resetWordAfterPrediction(deleteCount: candidate.deleteCount, inserted: chars)
        pendingRefresh?.cancel()
        pendingRefresh = nil
        refreshToken &+= 1
        currentCandidates = []
        navigator.listChanged(count: 0, at: now())
        lastAnchor = nil
        panel.hide()

        // Chain the next suggestion when the inserted text ends cleanly with whitespace.
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if candidate.insertion.last == " " {
            let item = DispatchWorkItem { [weak self] in
                self?.refreshNow(router: router, bundleID: bundleID, isVietnamese: isVietnamese,
                                 atWordStartAfterSpace: true)
            }
            pendingRefresh = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: item)
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
        pending = nil
        refreshToken &+= 1
        currentCandidates = []
        navigator.listChanged(count: 0, at: now())
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
        let personal = PersonalPredictionModel(store: store, saveDelay: 2)
        return PredictionController(
            personal: personal,
            onLearnerQueue: { queue.async(execute: $0) },
            onMain: { DispatchQueue.main.async(execute: $0) },
            quickType: QuickTypeSource.shared
        )
    }()
}
