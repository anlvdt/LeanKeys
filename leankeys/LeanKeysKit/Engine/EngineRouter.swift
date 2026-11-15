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
    /// The language this router last announced (`leanKeysLanguageChanged`), until the next `setEnabled`. The
    /// app mirrors that announcement into its on/off state, which comes back here as `setEnabled`: an echo, not
    /// the user's choice (ruling R25).
    private var announcedLanguage: Bool?

    public private(set) var fallbackReason: String?

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
            return .handled(nil)
        }
        guard let edit = vikey.process(keyCode: keyCode, caps: caps, shift: shift) else { return .handled(nil) }
        if edit.languageChanged {
            let on = vikey.isVietnamese
            vietnamese = on
            announcedLanguage = on
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .leanKeysLanguageChanged, object: nil, userInfo: ["vietnamese": on])
            }
        }
        return .handled((edit.deleteCount, edit.text, !edit.keyPassesThrough))
    }

    /// Gõ Nhanh's input method: 0 = Telex, 1 = VNI.
    public func setMethod(_ method: Int) {
        guard method != self.method else { return }
        self.method = method
        vikey?.resetContext()
        refresh()
    }

    /// The app's on/off state. An explicit change (not the echo of the router's own announcement) also sets
    /// Vikey's auto switch: off means English stays English until the user turns it on again (ruling R25).
    public func setEnabled(_ vietnamese: Bool) {
        let echo = announcedLanguage == vietnamese
        announcedLanguage = nil
        self.vietnamese = vietnamese
        vikey?.setVietnamese(vietnamese)
        guard !echo else { return }
        autoSwitch = vietnamese
        vikey?.setAutoSwitch(vietnamese)
    }

    /// Gõ Nhanh's modern-tone setting, forwarded to Vikey (spec §3.5).
    public func setModernTone(_ modern: Bool) {
        modernTone = modern
        vikey?.setModernTone(modern)
    }

    public func clear() {
        vikey?.resetContext()
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
