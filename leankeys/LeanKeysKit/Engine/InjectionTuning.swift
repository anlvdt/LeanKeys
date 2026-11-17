import Foundation

/// How long the event-tap callback waits after posting an edit (backspaces + replacement) before it returns.
///
/// Gõ Nhanh waits a fixed 5 ms (20 ms for its slow method) after every edit, synchronously, so the user's next
/// key waits too. LeanKeys waits less for the two backspace methods; everything else keeps Gõ Nhanh's 5 ms.
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

    /// The default for `c`, or the user's override (`defaults write <bundle id> LeanKeys.settleMicros.fast -int N`)
    /// clamped to 0…30000. Only fast and slow can be overridden. A missing or non-numeric value means no override.
    public static func settleMicros(_ c: SettleClass, defaults: UserDefaults = .standard) -> UInt32 {
        let key: String
        switch c {
        case .fast: key = fastOverrideKey
        case .slow: key = slowOverrideKey
        case .other: return defaultSettleMicros(.other)
        }
        // object(forKey:), not integer(forKey:): a missing key must not read as an override of 0.
        guard let n = (defaults.object(forKey: key) as? NSNumber)?.intValue else { return defaultSettleMicros(c) }
        return UInt32(min(max(n, 0), Int(maxSettleMicros)))
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

