import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

/// Coordinates 4A+ Laban Key-style next-word, phrase, and sentence predictions, personal encrypted learning,
/// and the non-activating ghost-text candidate bar.
///
/// Performance:
/// - `scheduleRefresh` on `CGEventTap` performs O(1) locked state update + `DispatchSourceTimer` arming with zero
///   AppKit/AX IPC, zero `TextMirror` string allocations, and zero `DispatchWorkItem` allocations per keystroke.
/// - All JSON corpus loading, `PredictionEngine.predict`, and `CaretLocator.currentAnchor` run off `RunLoop.main`.
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

    private struct PendingTrigger {
        var token: UInt64
        weak var router: EngineRouter?
        var bundleID: String
        var isVietnamese: Bool
        var atWordStartAfterSpace: Bool
    }

    private let defaults: UserDefaults
    private let personal: PersonalPredictionModel
    private let corpusProvider: () -> BuiltInPredictionCorpus
    private let dictionary: DictionaryCompleting?
    private let engineLock = NSLock()
    private var _engine: PredictionEngine?
    private let panel: CandidatePanelController
    private let onLearnerQueue: (@escaping () -> Void) -> Void
    private let onMain: (@escaping () -> Void) -> Void

    private weak var router: EngineRouter?
    private var shortcutsProvider: () -> [(trigger: String, replacement: String)] = { [] }
    private var injectText: (_ deleteCount: Int, _ chars: [Character]) -> Void = { _, _ in }
    private var contextProbe: () -> LearnContextProbe = LearnContextReader.probe
    private var secureField: (LearnContextProbe) -> Bool = LearnContextReader.isSecureField
    private var caretAnchor: (_ pid: pid_t?, _ screenHeight: CGFloat?) -> CaretLocator.CaretAnchor? = { pid, screenH in
        CaretLocator.currentAnchor(pid: pid, primaryScreenHeight: screenH)
    }

    private var appSwitchObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?

    private let predictQueue = DispatchQueue(label: "io.github.anlvdt.leankeys.predict.compute", qos: .userInitiated)
    private let stateLock = NSLock()
    private var debounceTimer: DispatchSourceTimer?
    private var pendingTrigger: PendingTrigger?
    private var refreshToken: UInt64 = 0

    // Main-thread caches (avoid AppKit / UserDefaults calls inside keyboardCallback)
    private var activeBundleID: String?
    private var activePID: pid_t?
    private var activeBundleAllowed = true
    private var cachedPrimaryScreenHeight: CGFloat = 0
    private var cachedExcludedBundleIDs: Set<String> = Exclusions.defaultBundleIDs
    private var cachedShortcuts: [(trigger: String, replacement: String)] = []
    private var lastShortcutsRefresh: CFAbsoluteTime = 0

    private var lastAnchor: CaretLocator.CaretAnchor?
    private var lastAnchorTime: CFAbsoluteTime = 0
    private var lastAnchorPID: pid_t?

    public init(
        defaults: UserDefaults = .standard,
        personal: PersonalPredictionModel,
        corpus: BuiltInPredictionCorpus? = nil,
        dictionary: DictionaryCompleting? = VikeyDictionaryCompleter.shared,
        panel: CandidatePanelController = CandidatePanelController(),
        onLearnerQueue: @escaping (@escaping () -> Void) -> Void,
        onMain: @escaping (@escaping () -> Void) -> Void
    ) {
        self.defaults = defaults
        self.personal = personal
        self.corpusProvider = { corpus ?? .shared }
        self.dictionary = dictionary
        self.panel = panel
        self.onLearnerQueue = onLearnerQueue
        self.onMain = onMain

        self.enabled = defaults.bool(forKey: Self.enabledKey)
        self.learnEnabled = defaults.bool(forKey: Self.learnKey) && defaults.bool(forKey: Self.learnConsentKey)
        if let corpus {
            self._engine = PredictionEngine(corpus: corpus, personal: personal, dictionary: dictionary)
        }
        if learnEnabled {
            onLearnerQueue { [weak self] in
                self?.personal.enabled = true
                self?.refreshStatsOnQueue()
            }
        }
    }

    deinit {
        if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        stateLock.lock()
        debounceTimer?.cancel()
        debounceTimer = nil
        stateLock.unlock()
    }

    private func engineInstance() -> PredictionEngine {
        engineLock.lock()
        defer { engineLock.unlock() }
        if let _engine { return _engine }
        let created = PredictionEngine(corpus: corpusProvider(), personal: personal, dictionary: dictionary)
        _engine = created
        return created
    }

    // MARK: - Settings & Privacy Opt-In

    public func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        defaults.set(on, forKey: Self.enabledKey)
        if on {
            predictQueue.async { [weak self] in
                _ = self?.engineInstance()
            }
        } else {
            hide()
        }
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
        self.cachedShortcuts = shortcuts()
        self.lastShortcutsRefresh = CFAbsoluteTimeGetCurrent()

        let frontApp = NSWorkspace.shared.frontmostApplication
        self.activeBundleID = frontApp?.bundleIdentifier
        self.activePID = frontApp?.processIdentifier
        self.activeBundleAllowed = Self.isBundleAllowed(activeBundleID, ownBundleID: ownBundleID)
        self.cachedPrimaryScreenHeight = CaretLocator.primaryScreenHeight
        self.cachedExcludedBundleIDs = excludedBundleIDs

        router.mirror.addPhraseObserver { [weak self] phrase in
            self?.phraseCommitted(phrase)
        }
        if appSwitchObserver == nil {
            appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self else { return }
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self.activeBundleID = app?.bundleIdentifier
                self.activePID = app?.processIdentifier
                self.activeBundleAllowed = Self.isBundleAllowed(self.activeBundleID, ownBundleID: self.ownBundleID)
                self.lastAnchor = nil
                self.lastAnchorPID = nil
                self.hide()
            }
        }
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.cachedPrimaryScreenHeight = CaretLocator.primaryScreenHeight
            }
        }
        if defaultsObserver == nil {
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: defaults,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.cachedExcludedBundleIDs = self.excludedBundleIDs
            }
        }
        if enabled {
            predictQueue.async { [weak self] in
                _ = self?.engineInstance()
            }
        }
    }

    func phraseCommitted(_ phrase: CommittedPhrase) {
        guard learnEnabled else { return }
        let probe = contextProbe()
        guard !probe.secureInput, let bundleID = probe.bundleID,
              bundleID != ownBundleID,
              !cachedExcludedBundleIDs.contains(bundleID),
              !Exclusions.isExcludedByDefault(bundleID) else { return }
        let secureField = self.secureField
        onLearnerQueue { [weak self] in
            guard let self, self.personal.enabled, !secureField(probe) else { return }
            self.personal.observe(phrase, context: probe.context(secureField: false))
            self.refreshStatsOnQueue()
        }
    }

    // MARK: - Keystroke Handling & Display

    /// Schedules candidate bar update on `predictQueue` using a single coalesced `DispatchSourceTimer`.
    /// - Hidden -> wait 220 ms after the last keystroke before computing and showing ghost text.
    /// - Already visible -> wait 140 ms so fast typing bursts trigger zero mid-burst prediction/AX work.
    public func scheduleRefresh(router: EngineRouter, bundleID: String?, isVietnamese: Bool, atWordStartAfterSpace: Bool) {
        guard enabled else {
            if isVisible { hide() }
            return
        }
        let resolvedBundleID: String?
        if let bundleID {
            if bundleID != activeBundleID {
                activeBundleID = bundleID
                activeBundleAllowed = Self.isBundleAllowed(bundleID, ownBundleID: ownBundleID)
            }
            resolvedBundleID = bundleID
        } else {
            resolvedBundleID = activeBundleID
        }
        guard activeBundleAllowed, let effectiveBundleID = resolvedBundleID else {
            if isVisible { hide() }
            return
        }
        let delay: TimeInterval = isVisible ? 0.14 : 0.22
        armDebouncedRefresh(
            delay: delay,
            router: router,
            bundleID: effectiveBundleID,
            isVietnamese: isVietnamese,
            atWordStartAfterSpace: atWordStartAfterSpace
        )
    }

    private func armDebouncedRefresh(
        delay: TimeInterval,
        router: EngineRouter,
        bundleID: String,
        isVietnamese: Bool,
        atWordStartAfterSpace: Bool
    ) {
        stateLock.lock()
        refreshToken &+= 1
        let token = refreshToken
        pendingTrigger = PendingTrigger(
            token: token,
            router: router,
            bundleID: bundleID,
            isVietnamese: isVietnamese,
            atWordStartAfterSpace: atWordStartAfterSpace
        )
        let timer: DispatchSourceTimer
        if let existing = debounceTimer {
            timer = existing
        } else {
            let created = DispatchSource.makeTimerSource(queue: predictQueue)
            created.setEventHandler { [weak self] in
                self?.fireDebouncedPrediction()
            }
            created.resume()
            debounceTimer = created
            timer = created
        }
        timer.schedule(deadline: .now() + delay, leeway: .milliseconds(20))
        stateLock.unlock()
    }

    private func currentToken() -> UInt64 {
        stateLock.lock()
        let t = refreshToken
        stateLock.unlock()
        return t
    }

    private func fireDebouncedPrediction() {
        stateLock.lock()
        guard let trigger = pendingTrigger, trigger.token == refreshToken else {
            stateLock.unlock()
            return
        }
        pendingTrigger = nil
        stateLock.unlock()

        onMain { [weak self] in
            guard let self else { return }
            guard self.currentToken() == trigger.token,
                  self.enabled,
                  !IsSecureEventInputEnabled(),
                  let router = trigger.router else {
                self.hideIfTokenMatches(trigger.token)
                return
            }

            let currentWord = router.mirror.currentWord
            let previousWords = router.mirror.recentWordsBeforeCurrent
            let followsBreak = router.mirror.currentWordFollowsBreak

            if currentWord.isEmpty && (!trigger.atWordStartAfterSpace || previousWords.isEmpty) {
                self.hideIfTokenMatches(trigger.token)
                return
            }
            let minPrefix = previousWords.isEmpty ? PredictionEngine.minPrefixLength : 1
            if !currentWord.isEmpty && currentWord.count < minPrefix {
                self.hideIfTokenMatches(trigger.token)
                return
            }

            let now = CFAbsoluteTimeGetCurrent()
            if now - self.lastShortcutsRefresh >= 2.0 {
                self.cachedShortcuts = self.shortcutsProvider()
                self.lastShortcutsRefresh = now
            }
            let query = PredictionQuery(
                previousWords: previousWords,
                currentWord: currentWord,
                followsNonSpaceBreak: followsBreak,
                atWordStartAfterSpace: trigger.atWordStartAfterSpace,
                isVietnamese: trigger.isVietnamese,
                shortcuts: self.cachedShortcuts
            )
            let pid = self.activePID
            let screenH = self.cachedPrimaryScreenHeight
            let reusableAnchor: CaretLocator.CaretAnchor? =
                (self.lastAnchorPID == pid && now - self.lastAnchorTime < 0.50) ? self.lastAnchor : nil

            self.predictQueue.async { [weak self] in
                guard let self, self.currentToken() == trigger.token else { return }
                let candidates = self.engineInstance().predict(query)
                guard !candidates.isEmpty else {
                    self.onMain { [weak self] in
                        self?.hideIfTokenMatches(trigger.token)
                    }
                    return
                }
                guard self.currentToken() == trigger.token else { return }

                let anchor: CaretLocator.CaretAnchor?
                let usedCached: Bool
                if let reusableAnchor {
                    anchor = reusableAnchor
                    usedCached = true
                } else {
                    anchor = self.caretAnchor(pid, screenH > 0 ? screenH : nil)
                    usedCached = false
                }
                guard let resolved = anchor else {
                    self.onMain { [weak self] in
                        self?.hideIfTokenMatches(trigger.token)
                    }
                    return
                }

                self.onMain { [weak self] in
                    guard let self,
                          self.enabled,
                          self.currentToken() == trigger.token,
                          !IsSecureEventInputEnabled() else { return }
                    if !usedCached {
                        self.lastAnchor = resolved
                        self.lastAnchorTime = CFAbsoluteTimeGetCurrent()
                        self.lastAnchorPID = pid
                    }
                    self.present(candidates: candidates, anchor: resolved, token: trigger.token)
                }
            }
        }
    }

    private func hideIfTokenMatches(_ token: UInt64) {
        guard currentToken() == token else { return }
        if isVisible || panel.isVisible {
            currentCandidates = []
            panel.hide()
        }
    }

    private func present(candidates: [PredictionCandidate], anchor: CaretLocator.CaretAnchor, token: UInt64) {
        guard enabled, currentToken() == token else { return }
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
        stateLock.lock()
        pendingTrigger = nil
        refreshToken &+= 1
        stateLock.unlock()
        currentCandidates = []
        lastAnchor = nil
        lastAnchorPID = nil

        // Chain the next suggestion smoothly when the insertion ends with whitespace;
        // if no follow-up exists or another key arrives first, `hideIfTokenMatches` hides it.
        if candidate.insertion.last == " ", activeBundleAllowed, let bundleID = activeBundleID {
            armDebouncedRefresh(
                delay: 0.08,
                router: router,
                bundleID: bundleID,
                isVietnamese: isVietnamese,
                atWordStartAfterSpace: true
            )
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
        stateLock.lock()
        pendingTrigger = nil
        refreshToken &+= 1
        stateLock.unlock()
        if isVisible || panel.isVisible {
            currentCandidates = []
            panel.hide()
        } else {
            currentCandidates = []
        }
    }

    private static func isBundleAllowed(_ bundleID: String?, ownBundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleID != ownBundleID
            && !CodeApps.contains(bundleID)
            && !KeyPassthrough.remoteBundleIDs.contains(bundleID)
            && !KeyPassthrough.credentialAppBundleIDs.contains(bundleID)
            && !Exclusions.passwordManagers.contains(bundleID)
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
