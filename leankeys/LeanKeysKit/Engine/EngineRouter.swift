import AppKit
import Foundation

/// What the router did with a key. `.handled` carries `RustBridge.processKey`'s return value as is; its third
/// element (keyConsumed) is false when the key itself must still be typed after the edit.
/// Not Equatable (it holds a tuple): match it with `if case`.
public enum InterceptResult {
    /// Gõ Nhanh's own engine decides.
    case passToGoNhanh
    /// Vikey decided: (backspaces, text, handled), or nil to let the key through.
    case handled((Int, [Character], Bool)?)
}

public extension Notification.Name {
    /// Vikey switched language by itself (its own hotkey). userInfo["vietnamese": Bool].
    static let leanKeysLanguageChanged = Notification.Name("LeanKeys.languageChanged")
}

/// Picks the engine for each key. Vikey is the default (see `LeanSettings.engine`), except under VNI (Vikey here
/// is Telex only) or when Vikey fails to start, where Gõ Nhanh takes over; Gõ Nhanh when the user picks it.
/// Driven from the event-tap thread only, which is the main thread (RustBridge adds the tap to the main run loop): no
/// locking.
public final class EngineRouter {
    /// The app's router: the only one that asks the focused field at Return (tests pass their own answer).
    public static let shared = EngineRouter(fieldAllowsFixAtReturn: { FocusedField.allowsFixAtReturn() })

    private static let vniMethod = 1

    private let settings: LeanSettings
    private let makeVikey: () -> TypingEngine?
    private let makeUndoLearning: () -> UndoLearning
    private var vikey: TypingEngine?
    /// `vikey` when it is the real engine, with the undo learner (spec 12.2) that drains its undo events.
    private var vikeyEngine: VikeyEngine?
    private var undoLearning: UndoLearning?
    /// Spec 17.1, with the real engine only (built with `undoLearning`).
    private var capitalizer: AutoCapitalizer?
    /// The word being typed began with a letter key the user typed as a capital (Shift or Caps Lock).
    private var wordStartsWithUserCapital = false
    /// The phrase text right after a ⌫ undo of a capitalisation: while it stands unchanged, the words it gave back
    /// are not capitalised again at the next break, whatever the rule book says (like Vikey's own undone word).
    private var restoredByUndo: String?
    /// Spec 17.2, with the real engine only (its switch lives on `undoLearning`).
    private var strayEnter = StrayEnterFilter()
    private let now: () -> TimeInterval
    private let frontmostBundleID: () -> String?
    private let fieldAllowsFixAtReturn: () -> Bool
    private var vikeyAttempted = false
    private var method = 0
    private var vietnamese = true
    private var autoSwitch = true
    private var modernTone = true

    /// The language the user had before Vikey's first switch by itself since the user's last explicit choice;
    /// nil when no automatic switch happened since. The app stores this, not the switched state, when it
    /// remembers a language for a newly seen app: automatic switches are never remembered.
    public private(set) var languageBeforeAutoSwitch: Bool?

    public private(set) var fallbackReason: String?

    /// For the debug log, after the last Return/Enter with a word pending: whether Return could finish the word and
    /// why not ("returnFix=1", "returnFix=0 code-app", "returnFix=0 field"; see `FocusedField.lastNote`). nil after
    /// any other key. Holds no typed text.
    public private(set) var returnFixNote: String?

    /// For the debug log: " lang→EN" / " lang→VN" when Vikey switched language by itself at the last key, else "".
    public private(set) var languageLog = ""

    /// `returnFixNote` with what the live field query saw, when it was asked. For the debug log only.
    public var returnFixLog: String? {
        guard let note = returnFixNote else { return nil }
        return note.hasSuffix("code-app") ? note : note + " " + FocusedField.lastNote
    }

    /// What was just typed, from either engine (see `observeGoNhanh`). Memory only.
    public let mirror = TextMirror()

    /// Whether Vikey's automatic switch is on (see `setEnabled`).
    public var autoSwitchOn: Bool { autoSwitch }

    /// `makeVikey` runs at most once, the first time Vikey is needed. `undoLearning` runs at most once too, and only
    /// when that engine is the real `VikeyEngine`: the default (`UndoLearning.shared`, which opens the saved rules)
    /// is never built for a stub engine or a router that never uses Vikey. `now` (seconds, monotonic) and
    /// `frontmostBundleID` serve the stray-key filter (spec 17.2); `frontmostBundleID` also keeps capitals out of
    /// terminals and code editors (spec 17.1). `fieldAllowsFixAtReturn` is asked at Return/Enter with a word pending,
    /// outside code apps: true lets Return finish the word as Space does. The default never allows it (Vikey D62);
    /// `shared` asks the focused field (`FocusedField.allowsFixAtReturn`).
    public init(defaults: UserDefaults = .standard, makeVikey: @escaping () -> TypingEngine? = { VikeyEngine() },
                undoLearning: @escaping () -> UndoLearning = { UndoLearning.shared },
                now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                frontmostBundleID: @escaping () -> String? = {
                    NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                },
                fieldAllowsFixAtReturn: @escaping () -> Bool = { false }) {
        settings = LeanSettings(defaults: defaults)
        self.makeVikey = makeVikey
        makeUndoLearning = undoLearning
        self.now = now
        self.frontmostBundleID = frontmostBundleID
        self.fieldAllowsFixAtReturn = fieldAllowsFixAtReturn
        refresh()
    }

    /// Stored under "LeanKeys.engine". Switching clears both engines' word state.
    public var selected: EngineKind {
        get { settings.engine }
        set {
            guard newValue != settings.engine else { return }
            vikey?.resetContext()
            forgetWord()
            settings.engine = newValue
            refresh()
            vikey?.resetContext()
        }
    }

    /// `selected`, unless VNI or a failed Vikey start forces Gõ Nhanh.
    public var active: EngineKind {
        selected == .vikey && fallbackReason == nil ? .vikey : .gonhanh
    }

    /// `ctrl` is ⌘ or ⌃, and ⌥ outside Return/Enter (the macOS key handler sends ⌥+key as `ctrl`). `option` is ⌥,
    /// which reaches here without `ctrl` only on Return/Enter.
    public func intercept(keyCode: UInt16, caps: Bool, ctrl: Bool, shift: Bool,
                          option: Bool = false) -> InterceptResult {
        languageLog = ""
        returnFixNote = nil   // also when the stray-key filter or a Ctrl chord answers this key
        guard active == .vikey, let vikey else { return .passToGoNhanh }
        // Only the very next key may undo a capitalisation (spec 17.1.4).
        let capitalized = capitalizer?.last
        capitalizer?.last = nil
        // A Ctrl chord is a shortcut, not typing: the word ends and the key goes through untouched.
        if ctrl {
            vikey.resetContext()
            mirror.discard()
            forgetWord()
            return .handled(nil)
        }
        let wordWasEmpty = mirror.currentWord.isEmpty
        let result = dropStrayKey(vikey, keyCode: keyCode, caps: caps, shift: shift, option: option)
            ?? interceptVikey(vikey, keyCode: keyCode, caps: caps, shift: shift, capitalized: capitalized)
        // The words a ⌫ undo gave back stay as typed only until they change or the break after them is typed.
        if let restored = restoredByUndo, mirror.phraseText != restored { restoredByUndo = nil }
        // Whether the word now being typed began with the user's own capital (spec 17.1.3).
        if mirror.currentWord.isEmpty {
            wordStartsWithUserCapital = false
        } else if wordWasEmpty {
            wordStartsWithUserCapital = caps
                && VikeyEngine.typedCharacter(keyCode: keyCode, shift: shift, caps: caps)?.isLetter == true
        }
        return .handled(result)
    }

    private func interceptVikey(_ vikey: TypingEngine, keyCode: UInt16, caps: Bool, shift: Bool,
                                capitalized: AutoCapitalizer.Made?) -> (Int, [Character], Bool)? {
        if keyCode == Self.backspaceKey, let capitalized {
            return undoCapitalization(capitalized, vikey: vikey, keyCode: keyCode, caps: caps, shift: shift)
        }
        // Read before anything changes the mirror: the break key commits the word, and may end the phrase.
        let isSpace = keyCode == Self.spaceKey
        let committed = isSpace || Self.triggersShortcut(keyCode, shift: shift) ? committedWord() : nil
        if let result = expandShortcut(keyCode: keyCode, shift: shift) {
            vikey.resetContext()
            observe(keyCode: keyCode, shift: shift, caps: caps, result: result)
            return result
        }
        // Vikey D62 keeps Return from fixing a word, for an address bar's autocompletion; elsewhere a message's last
        // word is fixed as at Space. The field is asked only here: one Accessibility query per Return after a word.
        // Not in terminals and code editors, where Return accepts a completion from a popup list (as ruling R12).
        if Self.returnKeys.contains(keyCode), !mirror.currentWord.isEmpty {
            if CodeApps.contains(frontmostBundleID()) {
                returnFixNote = "returnFix=0 code-app"
            } else if fieldAllowsFixAtReturn() {
                returnFixNote = "returnFix=1"
                vikey.allowFixAtNextReturn()
            } else {
                returnFixNote = "returnFix=0 field"
            }
        }
        let processed = vikey.process(keyCode: keyCode, caps: caps, shift: shift)
        if let vikeyEngine { undoLearning?.afterPress(engine: vikeyEngine) }
        guard let edit = processed else {
            // Vikey left the word as typed: LeanKeys may capitalise it (spec 17.1). After a fix of Vikey's own at
            // this key it does not, so Vikey's ⌫⌫ undo still finds its word.
            if let committed {
                learnName(committed)
                if let result = capitalize(committed, keyCode: keyCode, shift: shift, caps: caps) { return result }
            }
            observe(keyCode: keyCode, shift: shift, caps: caps, result: nil)
            return nil
        }
        if edit.languageChanged {
            let on = vikey.isVietnamese
            languageLog = on ? " lang→VN" : " lang→EN"
            if languageBeforeAutoSwitch == nil { languageBeforeAutoSwitch = vietnamese }
            vietnamese = on
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .leanKeysLanguageChanged, object: nil, userInfo: ["vietnamese": on])
            }
        }
        let result = (edit.deleteCount, edit.text, !edit.keyPassesThrough)
        observe(keyCode: keyCode, shift: shift, caps: caps, result: result)
        return result
    }

    // MARK: Stray key at Enter (spec 17.2)

    /// A result that only swallows the key: consumed, nothing to delete or type (`.dropKey`). The macOS key handler
    /// returns it without an injection, which would only post U+202F and a ⌫ under `.emptyCharPrefix` (an
    /// autocomplete flicker in address bars) and wait out the settle delay (final review M1).
    public static func swallowsKeyOnly(_ result: (Int, [Character], Bool)) -> Bool {
        result.0 == 0 && result.1.isEmpty && result.2
    }

    /// The edit that drops a key next to Enter hit together with Enter, or nil to go on as usual. Before Enter: the
    /// stray character is deleted and Enter follows (not consumed); Vikey never sees this Enter, so its word ends
    /// here. After Enter: the key is consumed and Vikey never sees it. The mirror follows the screen either way.
    private func dropStrayKey(_ vikey: TypingEngine, keyCode: UInt16, caps: Bool, shift: Bool,
                              option: Bool) -> (Int, [Character], Bool)? {
        guard let undoLearning, undoLearning.strayEnter else { return nil }
        // Only Enter and the keys next to it can be acted on: the frontmost app is asked for those only, and the
        // line is read (as a String) only at Enter, the one key the filter reads it for.
        let isEnter = StrayEnterFilter.enterKeys.contains(keyCode)
        let mayAct = isEnter || StrayEnterFilter.adjacentKeys[keyCode] != nil
        let decision = strayEnter.decide(keyCode: keyCode, shift: shift, otherModifiers: option, time: now(),
                                         lineBeforeCursor: isEnter ? mirror.typedTail : "",
                                         lineStartKnown: mirror.lineStartKnown,
                                         bundleID: mayAct ? frontmostBundleID() : nil,
                                         bracketTypesLetter: vikey.isVietnamese)
        let result: (Int, [Character], Bool)
        switch decision {
        case .none: return nil
        case .deleteBeforeEnter:
            vikey.resetContext()
            result = (1, [], false)
        case .dropKey:
            // The macOS handler swallows this without an injection (`swallowsKeyOnly`).
            result = (0, [], true)
        }
        observe(keyCode: keyCode, shift: shift, caps: caps, result: result)
        return result
    }

    // MARK: Capitalisation (spec 17.1)

    /// The word a break key is about to commit, read from the mirror before the key.
    private struct CommittedWordContext {
        let word: String
        let phraseText: String
        /// The word before `word`, lowercased, when only spaces separate them (as `AutoCapitalizer` reads it).
        let previous: String?
        /// The word starts the phrase or a sentence inside it (after `:` or an opening quote): its capital is
        /// sentence case (ruling R11(a), final re-review N2).
        let atSentenceStart: Bool
        let userCapital: Bool
    }

    /// nil when there is no whole word to commit, or it follows punctuation (`gov.vn`, `3.5`). A word glued to a
    /// symbol that is no word break (`an@vidu`, `~/src`) is returned whole: learning reads it (`Ê-đê`), while
    /// `capitalize` skips it.
    private func committedWord() -> CommittedWordContext? {
        guard capitalizer != nil else { return nil }
        let word = mirror.currentWord
        guard !word.isEmpty, !mirror.currentWordFollowsBreak, let phraseText = mirror.phraseText else { return nil }
        let before = phraseText.dropLast(word.count)
        let atSentenceStart = mirror.atPhraseStart || AutoCapitalizer.startsSentence(after: before)
        // Not across punctuation: "chị, Lan" is no name after a title (task 3 review minor 7).
        let beforeWord = before.reversed().drop(while: { $0 == " " })
        let previous = beforeWord.first.map(TextMirror.isWordCharacter) == true
            ? String(beforeWord.prefix(while: TextMirror.isWordCharacter).reversed()).lowercased() : nil
        return CommittedWordContext(word: word, phraseText: phraseText, previous: previous,
                                    atSentenceStart: atSentenceStart, userCapital: wordStartsWithUserCapital)
    }

    /// Spec 17.1.3: a word the user typed with a capital, mid-phrase, goes to the learned names. Words LeanKeys
    /// wrote (capitalisation, gõ tắt, Vikey's edits) never start with the user's capital key, so they never count.
    private func learnName(_ committed: CommittedWordContext) {
        guard committed.userCapital, !committed.atSentenceStart, committed.word.first?.isUppercase == true else { return }
        undoLearning?.userCapitalized(committed.word, previous: committed.previous)
    }

    /// The edit that capitalises the committed words, with the break key: Space rides in the text (consumed), while
    /// Return and punctuation are typed by the key itself after the edit, as in `expandShortcut`.
    private func capitalize(_ committed: CommittedWordContext, keyCode: UInt16, shift: Bool,
                            caps: Bool) -> (Int, [Character], Bool)? {
        // Only a word of letters and digits: not one glued to a symbol, an address, a path or a tag
        // (`an@tiki`, `~/tiki`, `#tiki`, `ten-tiki`; ruling R13).
        guard committed.word.allSatisfy(TextMirror.isWordCharacter), committed.phraseText != restoredByUndo,
              let undoLearning, undoLearning.autoCapitalize, let capitalizer,
              let replacement = capitalizer.replacement(phraseText: committed.phraseText,
                                                        keepsLowercase: undoLearning.keepsLowercase),
              // Not in a terminal or code editor (ruling R12). Asked only once a rule fired, not at every Space.
              !CodeApps.contains(frontmostBundleID())
        else { return nil }
        // A learned name that made it is now in use (review M3: not at lookup, which the rules may still reject).
        if let name = capitalizer.learnedName(in: replacement) { undoLearning.learnedNames.markUsed(word: name) }
        let isSpace = keyCode == Self.spaceKey
        let result = (replacement.original.count, Array(replacement.capitalized) + (isSpace ? [" "] : []), isSpace)
        observe(keyCode: keyCode, shift: shift, caps: caps, result: result)
        // Not after Return/Enter: in a chat app the text has been sent by now, so ⌫ there must stay a plain ⌫.
        if !Self.returnKeys.contains(keyCode) {
            capitalizer.last = AutoCapitalizer.Made(replacement: replacement, breakLength: 1)
        }
        return result
    }

    /// Spec 17.1.4: ⌫ right after a capitalisation removes the break character and gives the words back as typed.
    /// Vikey sees the ⌫ too, so its buffer follows the screen back into the word; its own edit, if any, is dropped.
    private func undoCapitalization(_ made: AutoCapitalizer.Made, vikey: TypingEngine, keyCode: UInt16, caps: Bool,
                                    shift: Bool) -> (Int, [Character], Bool) {
        if vikey.process(keyCode: keyCode, caps: caps, shift: shift) != nil { vikey.resetContext() }
        if let vikeyEngine { undoLearning?.afterPress(engine: vikeyEngine) }
        let replacement = made.replacement
        undoLearning?.capitalizationUndone(replacement.rule, previous: replacement.previous,
                                           learnedName: capitalizer?.learnedName(in: replacement))
        let result = (replacement.capitalized.count + made.breakLength, Array(replacement.original), true)
        observe(keyCode: keyCode, shift: shift, caps: caps, result: result)
        restoredByUndo = mirror.phraseText
        return result
    }

    /// The word and any capitalisation to undo are gone: the cursor moved, or the text changed out of sight.
    private func forgetWord() {
        strayEnter = StrayEnterFilter()
        capitalizer?.last = nil
        wordStartsWithUserCapital = false
        restoredByUndo = nil
    }

    /// The user's gõ tắt, for Vikey only: Gõ Nhanh expands its own copy (`RustBridge.syncShortcuts`), so the
    /// router never expands while Gõ Nhanh is active. Called from the main thread, which also runs the event tap.
    public func setShortcuts(_ items: [(trigger: String, replacement: String)]) {
        shortcuts = ShortcutExpander(items)
    }

    private var shortcuts = ShortcutExpander()

    /// The edit that replaces the word just typed by its shortcut, when `keyCode` ends a word as in Gõ Nhanh
    /// (Space, Return/Enter, punctuation, Shift+digit; not Tab, Esc or arrows). Space rides in the text, consumed,
    /// because the key handler never posts Space after an edit; Return and punctuation are posted by the key itself.
    private func expandShortcut(keyCode: UInt16, shift: Bool) -> (Int, [Character], Bool)? {
        guard !shortcuts.isEmpty else { return nil }
        let isSpace = keyCode == Self.spaceKey
        guard isSpace || Self.triggersShortcut(keyCode, shift: shift) else { return nil }
        guard !mirror.currentWordFollowsBreak else { return nil }
        let word = mirror.currentWord
        guard let replacement = shortcuts.expand(word: word) else { return nil }
        return (word.count, Array(replacement) + (isSpace ? [" "] : []), isSpace)
    }

    /// Gõ Nhanh's result for a key (`RustBridge.processKey`, nil = the key goes through), fed to `mirror` by the
    /// same rules as Vikey's. Ctrl chords are not passed here: the caller calls `discardPending()` for those.
    public func observeGoNhanh(keyCode: UInt16, shift: Bool, caps: Bool, result: (Int, [Character], Bool)?) {
        observe(keyCode: keyCode, shift: shift, caps: caps, result: result)
    }

    /// Applies an engine result, then the key itself when it reaches the app. The macOS key handler lets the key
    /// through when the result is nil, or when it is not consumed and the key is a break key other than Space
    /// (`isBreakKey` in RustBridge.swift); otherwise the result's text is all that is typed.
    private func observe(keyCode: UInt16, shift: Bool, caps: Bool, result: (Int, [Character], Bool)?) {
        if let (deleteCount, text, consumed) = result {
            mirror.apply(deleteCount: deleteCount, insert: text)
            guard !consumed, Self.keyFollowsEdit(keyCode, shift: shift) else { return }
        }
        switch keyCode {
        case Self.backspaceKey: mirror.apply(deleteCount: 1, insert: [])
        case Self.tabKey: mirror.typed("\t")
        case _ where Self.cursorKeys.contains(keyCode): mirror.reset()
        default:
            if let c = VikeyEngine.typedCharacter(keyCode: keyCode, shift: shift, caps: caps) {
                mirror.typed(c)
            } else {
                // Forward delete, function keys and anything else without a known character: text changed out of sight.
                mirror.discard()
            }
        }
    }

    private static let backspaceKey: UInt16 = 51
    private static let tabKey: UInt16 = 48
    /// Arrows, Home, End, Page Up, Page Down, Esc: the cursor moves, so the phrase is finished (`TextMirror.reset`).
    private static let cursorKeys: Set<UInt16> = [123, 124, 125, 126, 115, 119, 116, 121, 53]
    /// RustBridge's break keys without Space: Tab, Return, Enter, Esc, arrows and punctuation; digits with Shift.
    private static let breakKeys: Set<UInt16> = [48, 36, 76, 53, 123, 124, 125, 126, 47, 43, 44, 41, 39, 33, 30, 42, 27, 24, 50]
    private static let digitKeys: Set<UInt16> = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]

    private static let spaceKey: UInt16 = 49
    private static let returnKeys: Set<UInt16> = [36, 76]
    /// Keys besides Space that end a word for shortcuts in Gõ Nhanh (core/src/engine/mod.rs: Return/Enter and
    /// `break_key_to_char`): `breakKeys` without Tab, Esc and the arrows; digits with Shift.
    private static let shortcutBreakKeys = breakKeys.subtracting([48, 53, 123, 124, 125, 126])

    private static func triggersShortcut(_ keyCode: UInt16, shift: Bool) -> Bool {
        shortcutBreakKeys.contains(keyCode) || (shift && digitKeys.contains(keyCode))
    }

    private static func keyFollowsEdit(_ keyCode: UInt16, shift: Bool) -> Bool {
        breakKeys.contains(keyCode) || (shift && digitKeys.contains(keyCode))
    }

    /// Drops the mirror's pending word and phrase without emitting them: Cmd/Ctrl chords, Option+Backspace, the
    /// restore shortcut, Secure Input, other input sources, an app switch (ruling R20).
    public func discardPending() {
        mirror.discard()
        forgetWord()
    }

    /// Gõ Nhanh's input method: 0 = Telex, 1 = VNI.
    public func setMethod(_ method: Int) {
        guard method != self.method else { return }
        self.method = method
        vikey?.resetContext()
        forgetWord()
        refresh()
    }

    /// The app's on/off state (ruling R25). On always turns Vikey's auto switch back on. Off pauses it only when
    /// `explicit`: the user's own choice (toggle hotkey, menu or settings toggle, a per-app "Tắt" profile, or a
    /// remembered per-app "off", which only the user can have set). Every other caller (the app mirroring
    /// Vikey's own switch, input-source changes, launch) leaves auto switch as it is, so English typed after an
    /// automatic switch can still switch back.
    public func setEnabled(_ vietnamese: Bool, explicit: Bool = false) {
        self.vietnamese = vietnamese
        vikey?.setVietnamese(vietnamese)
        if explicit { languageBeforeAutoSwitch = nil }
        if vietnamese {
            setAutoSwitch(true)
        } else if explicit {
            setAutoSwitch(false)
        }
    }

    private func setAutoSwitch(_ on: Bool) {
        autoSwitch = on
        vikey?.setAutoSwitch(on)
    }

    /// Gõ Nhanh's modern-tone setting, forwarded to Vikey (spec §3.5).
    public func setModernTone(_ modern: Bool) {
        modernTone = modern
        vikey?.setModernTone(modern)
    }

    /// Every place the macOS app drops the word goes through `RustBridge.clearBuffer*` to here, so the mirror
    /// resets with it and emits the pending phrase (a click, Tab or a modified arrow moves the cursor in the app).
    /// Bypass, Secure Input and app-switch sites call `discardPending()` first, which leaves nothing to emit.
    public func clear() {
        vikey?.resetContext()
        mirror.reset()
        forgetWord()
    }

    /// Recomputes `fallbackReason`, building Vikey the first time it is needed.
    private func refresh() {
        guard selected == .vikey else { fallbackReason = nil; return }
        if method == Self.vniMethod { fallbackReason = "vni"; return }
        if !vikeyAttempted {
            vikeyAttempted = true
            vikey = makeVikey()
            if let engine = vikey as? VikeyEngine {
                vikeyEngine = engine
                let learning = makeUndoLearning()
                undoLearning = learning
                learning.install()
                capitalizer = AutoCapitalizer(learned: learning.learnedNames)
            }
            vikey?.setVietnamese(vietnamese)
            vikey?.setAutoSwitch(autoSwitch)
            vikey?.setModernTone(modernTone)
        }
        fallbackReason = vikey == nil ? "vikey-init-failed" : nil
    }
}
