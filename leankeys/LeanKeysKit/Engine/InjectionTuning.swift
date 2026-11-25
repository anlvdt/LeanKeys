import Foundation

/// How long the event-tap callback waits after posting an edit (backspaces + replacement) before it returns.
///
/// Gõ Nhanh waits a fixed 5 ms (20 ms for its slow method) after every edit, synchronously, so the user's next
/// key waits too. LeanKeys waits less for the two backspace methods, and less again (with shorter per-key delays) for
/// the measured apps in `tuned`; everything else keeps Gõ Nhanh's 5 ms.
/// The app's `TextInjector.injectSync` maps its private `InjectionMethod` onto `SettleClass`.
public enum InjectionTuning {
    public enum SettleClass {
        /// `InjectionMethod.fast`: the default for most apps.
        case fast
        /// `InjectionMethod.slow`: terminals, VS Code-likes, JetBrains, Office, Notion.
        case slow
        /// Every other method (browsers' emptyCharPrefix, selection, charByChar, axDirect, syncProxy).
        case other
    }

    public static let fastOverrideKey = "LeanKeys.settleMicros.fast"
    public static let slowOverrideKey = "LeanKeys.settleMicros.slow"
    public static let otherOverrideKey = "LeanKeys.settleMicros.other"
    public static let maxSettleMicros: UInt32 = 30000

    /// Gõ Nhanh v1.0.165's settle for each class, kept for reference and the latency harness.
    public static func upstreamSettleMicros(_ c: SettleClass) -> UInt32 {
        c == .slow ? 20000 : 5000
    }

    public static func defaultSettleMicros(_ c: SettleClass) -> UInt32 {
        switch c {
        case .fast: return 1000
        case .slow: return 8000
        case .other: return 5000
        }
    }

    /// Delays and settle LeanKeys uses instead of Gõ Nhanh's for one detection, only in the apps listed.
    public struct Tuned {
        public let delays: (UInt32, UInt32, UInt32)
        public let settle: UInt32
        public let apps: Set<String>
    }

    /// Chromium browsers: Chrome was measured; the others share its input pipeline.
    static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta", "org.chromium.Chromium",
        "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary",
        "com.vivaldi.Vivaldi", "com.vivaldi.Vivaldi.snapshot", "company.thebrowser.Browser", "company.thebrowser.Arc",
        "company.thebrowser.dia", "net.imput.helium", "ai.perplexity.comet", "com.openai.atlas",
    ]

    /// Detections where Gõ Nhanh waits far longer than the app needs, with the delays and settle LeanKeys uses instead.
    /// Measured 2026-11-25 by posting HID keys at 20 and 30 keys/s and reading the field back over Accessibility:
    /// - `emptyChar:browser` in Chrome (input, textarea, contenteditable, Lexical, Quill, an address-bar style
    ///   completion field): 3/8/3 ms + 5 ms gave p90 ~32 ms; 1/2/1 + 1 gives ~20 ms, every sentence right. All zeros
    ///   lost letters in Lexical and the completion field.
    /// - `slow:code` in VS Code and Terminal (Vietnamese on): 8/25/8 + 8 ms gave p90 ~31 ms and one wrong word at
    ///   30 keys/s in VS Code (keys queued behind the sleeps); 1/3/1 + 1 gives 11–25 ms, every sentence right.
    ///   VSCodium, Code - OSS and Cursor's VS Code build share VS Code's editor. GPU terminals (Ghostty, Warp,
    ///   Alacritty, kitty, ...) and other editors keep Gõ Nhanh's delays: not measured.
    /// Every other detection, and these detections in any other app, keep Gõ Nhanh's delays.
    public static let tuned: [String: Tuned] = [
        "emptyChar:browser": Tuned(delays: (1000, 2000, 1000), settle: 1000, apps: chromiumBrowsers),
        "slow:code": Tuned(delays: (1000, 3000, 1000), settle: 1000, apps: [
            "com.microsoft.VSCode", "com.visualstudio.code.oss", "com.vscodium", "com.todesktop.cursor",
            "com.apple.Terminal",
        ]),
    ]

    /// The tuning for detection `name` in app `bundleID`, or nil when either is not tuned.
    public static func tuning(for name: String?, bundleID: String?) -> Tuned? {
        guard let name, let bundleID, let t = tuned[name], t.apps.contains(bundleID) else { return nil }
        return t
    }

    /// The settle for `c` after an edit made under detection `name` in `bundleID`: the user's class override
    /// (`defaults write <bundle id> LeanKeys.settleMicros.fast -int N`, clamped to 0…30000) if set, else the tuned
    /// settle, else the class default. A missing or non-numeric override means no override.
    public static func settleMicros(_ c: SettleClass, name: String?, bundleID: String?,
                                    defaults: UserDefaults = .standard) -> UInt32 {
        let key: String
        switch c {
        case .fast: key = fastOverrideKey
        case .slow: key = slowOverrideKey
        case .other: key = otherOverrideKey
        }
        if defaults.object(forKey: key) == nil, let t = tuning(for: name, bundleID: bundleID) { return t.settle }
        return settleMicros(c, defaults: defaults)
    }

    /// The default for `c`, or the user's override (`defaults write <bundle id> LeanKeys.settleMicros.fast -int N`)
    /// clamped to 0…30000. A missing or non-numeric value means no override.
    public static func settleMicros(_ c: SettleClass, defaults: UserDefaults = .standard) -> UInt32 {
        let key: String
        switch c {
        case .fast: key = fastOverrideKey
        case .slow: key = slowOverrideKey
        case .other: key = otherOverrideKey
        }
        // object(forKey:), not integer(forKey:): a missing key must not read as an override of 0.
        guard let n = (defaults.object(forKey: key) as? NSNumber)?.intValue else { return defaultSettleMicros(c) }
        return UInt32(min(max(n, 0), Int(maxSettleMicros)))
    }

    /// Prefix of the hidden per-method delay override: `LeanKeys.delays.<name>` = "backspace,wait,text" in µs, where
    /// `<name>` is the detection's name as the debug log prints it (`emptyChar:browser`, `slow:code`, `default`, ...).
    public static let delaysOverridePrefix = "LeanKeys.delays."

    /// The user's override for `methodName` (each value clamped to 0…30000; any app), else the tuned delays for
    /// `bundleID`, else `detected`. Anything other than three comma-separated integers means no override. Read once
    /// per detection (at most every 200 ms), not per key.
    public static func delays(for methodName: String, bundleID: String?, _ detected: (UInt32, UInt32, UInt32),
                              defaults: UserDefaults = .standard) -> (UInt32, UInt32, UInt32) {
        let fallback = tuning(for: methodName, bundleID: bundleID)?.delays ?? detected
        guard let text = defaults.string(forKey: delaysOverridePrefix + methodName) else { return fallback }
        let parts = text.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 3, parts.allSatisfy({ $0 != nil }) else { return fallback }
        let v = parts.map { UInt32(min(max($0!, 0), Int(maxSettleMicros))) }
        return (v[0], v[1], v[2])
    }

    /// Microseconds `injectSync` sleeps for one backspace-method edit (fast, slow, charByChar, emptyCharPrefix):
    /// a sleep after each backspace, one wait after the backspaces, one per text chunk, then the settle. It mirrors
    /// `TextInjector.injectViaBackspace` in the app; the event posts themselves are not counted.
    /// `charByChar` sends one UTF-16 unit per chunk, otherwise 20. `emptyCharPrefix` adds one sleep and one backspace.
    public static func blockingMicros(bs: Int, textUTF16: Int, delays: (UInt32, UInt32, UInt32), settle: UInt32,
                                      charByChar: Bool = false, emptyCharPrefix: Bool = false) -> UInt64 {
        var bs = UInt64(max(bs, 0))
        var total: UInt64 = 0
        if emptyCharPrefix {
            total += UInt64(delays.0 > 0 ? delays.0 : 1000)
            bs += 1
        }
        total += bs * UInt64(delays.0)
        if bs > 0 { total += UInt64(delays.1) }
        let chunkSize = charByChar ? 1 : 20
        let chunks = (max(textUTF16, 0) + chunkSize - 1) / chunkSize
        total += UInt64(chunks) * UInt64(delays.2)
        return total + UInt64(settle)
    }
}

/// How an edit is sent into a ProseMirror editor (Claude, Tiptap and many web apps), in a browser or an Electron
/// app. Gõ Nhanh sends every browser field the address-bar method (`emptyCharPrefix`) and Electron apps a backspace
/// method; in ProseMirror synthetic Backspaces are lost with any backspace method (measured in Chrome 2026-11-17
/// with webbench: emptyCharPrefix, charByChar, fast and slow all left the old letters, "Hoom" gave "Hoôm"), so
/// Vikey's word fixes left the old word on screen. Selecting the letters with Shift+Left and typing over them is
/// right there. Every other field keeps Gõ Nhanh's method: Lexical, Quill and contenteditable were right with it.
public enum BrowserEditorInjection {
    public enum Method: String { case fast, slow, charByChar, emptyCharPrefix, selection }

    /// Hidden setting for measuring (`defaults write io.github.anlvdt.leankeys LeanKeys.browserEditorMethod fast`).
    public static let overrideKey = "LeanKeys.browserEditorMethod"
    public static let defaultMethod: Method = .selection

    public static func method(defaults: UserDefaults = .standard) -> Method {
        defaults.string(forKey: overrideKey).flatMap(Method.init(rawValue:)) ?? defaultMethod
    }
}

import AppKit
import ApplicationServices

extension BrowserEditorInjection {
    /// A ProseMirror editor: an AXTextArea whose DOM class list (Chromium and Electron expose `AXDOMClassList`)
    /// has "ProseMirror". It gets `selection` in any app, not only in a browser: the Claude desktop app's prompt box
    /// is ProseMirror inside Electron, where the default backspace method lost keys ("kieemr" stayed raw).
    public static func isProseMirror(role: String?, domClasses: [String]) -> Bool {
        role == "AXTextArea" && domClasses.contains("ProseMirror")
    }

    /// The element's DOM classes, read with a 25 ms cap; empty when the app does not expose them or does not answer.
    public static func domClasses(of element: AXUIElement) -> [String] {
        AXUIElementSetMessagingTimeout(element, 0.025)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXDOMClassList" as CFString, &value) == .success else { return [] }
        return (value as? [String]) ?? []
    }
}

extension BrowserEditorInjection {
    private static let electronLock = NSLock()
    private static var electronApps: [String: Bool] = [:]

    /// Whether the app ships Electron, cached per bundle ID: only those (and browsers) are asked for DOM classes,
    /// so Terminal, Xcode or TextEdit never pay for the extra Accessibility query.
    public static func isElectronApp(bundleID: String) -> Bool {
        if let known = electronLock.withLock({ electronApps[bundleID] }) { return known }
        var electron = false
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let framework = url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
            electron = FileManager.default.fileExists(atPath: framework.path)
        }
        electronLock.withLock { electronApps[bundleID] = electron }
        return electron
    }
}

