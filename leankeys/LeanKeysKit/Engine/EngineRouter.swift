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
/// Driven from the event-tap thread only: no locking.
public final class EngineRouter {
    public static let shared = EngineRouter()

    private static let vniMethod = 1

    private let settings: LeanSettings
    private let makeVikey: () -> TypingEngine?
    private var vikey: TypingEngine?
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

    /// What was just typed, from either engine (see `observeGoNhanh`). Memory only.
    public let mirror = TextMirror()

    /// Whether Vikey's automatic switch is on (see `setEnabled`).
    public var autoSwitchOn: Bool { autoSwitch }

    /// `makeVikey` runs at most once, the first time Vikey is needed.
    public init(defaults: UserDefaults = .standard, makeVikey: @escaping () -> TypingEngine? = { VikeyEngine() }) {
        settings = LeanSettings(defaults: defaults)
        self.makeVikey = makeVikey
        refresh()
    }

    /// Stored under "LeanKeys.engine". Switching clears both engines' word state.
    public var selected: EngineKind {
        get { settings.engine }
        set {
            guard newValue != settings.engine else { return }
            vikey?.resetContext()
            settings.engine = newValue
            refresh()
            vikey?.resetContext()
        }
    }

    /// `selected`, unless VNI or a failed Vikey start forces Gõ Nhanh.
    public var active: EngineKind {
        selected == .vikey && fallbackReason == nil ? .vikey : .gonhanh
    }

    public func intercept(keyCode: UInt16, caps: Bool, ctrl: Bool, shift: Bool) -> InterceptResult {
        guard active == .vikey, let vikey else { return .passToGoNhanh }
        // A Ctrl chord is a shortcut, not typing: the word ends and the key goes through untouched.
        if ctrl {
            vikey.resetContext()
            mirror.reset()
            return .handled(nil)
        }
        guard let edit = vikey.process(keyCode: keyCode, caps: caps, shift: shift) else {
            observe(keyCode: keyCode, shift: shift, caps: caps, result: nil)
            return .handled(nil)
        }
        if edit.languageChanged {
            let on = vikey.isVietnamese
            if languageBeforeAutoSwitch == nil { languageBeforeAutoSwitch = vietnamese }
            vietnamese = on
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .leanKeysLanguageChanged, object: nil, userInfo: ["vietnamese": on])
            }
        }
        let result = (edit.deleteCount, edit.text, !edit.keyPassesThrough)
        observe(keyCode: keyCode, shift: shift, caps: caps, result: result)
        return .handled(result)
    }

    /// Gõ Nhanh's result for a key (`RustBridge.processKey`, nil = the key goes through), fed to `mirror` by the
    /// same rules as Vikey's. Ctrl chords are not passed here: the caller resets `mirror` for those.
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
        default:
            // Arrows, Home/End, Page Up/Down, Esc, forward delete and anything else without a known character move
            // the cursor or change text out of sight.
            if let c = VikeyEngine.typedCharacter(keyCode: keyCode, shift: shift, caps: caps) {
                mirror.typed(c)
            } else {
                mirror.reset()
            }
        }
    }

    private static let backspaceKey: UInt16 = 51
    private static let tabKey: UInt16 = 48
    /// RustBridge's break keys without Space: Tab, Return, Enter, Esc, arrows and punctuation; digits with Shift.
    private static let breakKeys: Set<UInt16> = [48, 36, 76, 53, 123, 124, 125, 126, 47, 43, 44, 41, 39, 33, 30, 42, 27, 24, 50]
    private static let digitKeys: Set<UInt16> = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]

    private static func keyFollowsEdit(_ keyCode: UInt16, shift: Bool) -> Bool {
        breakKeys.contains(keyCode) || (shift && digitKeys.contains(keyCode))
    }

    /// Gõ Nhanh's input method: 0 = Telex, 1 = VNI.
    public func setMethod(_ method: Int) {
        guard method != self.method else { return }
        self.method = method
        vikey?.resetContext()
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

    /// Every place the macOS app drops the word (click, app switch, Secure Input, Cmd/Ctrl, modified arrows)
    /// goes through `RustBridge.clearBuffer*` to here, so the mirror resets with it.
    public func clear() {
        vikey?.resetContext()
        mirror.reset()
    }

    /// Recomputes `fallbackReason`, building Vikey the first time it is needed.
    private func refresh() {
        guard selected == .vikey else { fallbackReason = nil; return }
        if method == Self.vniMethod { fallbackReason = "vni"; return }
        if !vikeyAttempted {
            vikeyAttempted = true
            vikey = makeVikey()
            vikey?.setVietnamese(vietnamese)
            vikey?.setAutoSwitch(autoSwitch)
            vikey?.setModernTone(modernTone)
        }
        fallbackReason = vikey == nil ? "vikey-init-failed" : nil
    }
}
