import AppKit
import ApplicationServices
import Foundation

/// Where LeanKeys lets every key through untouched: no Vietnamese, no gõ tắt, no learning.
///
/// - **Remote control and virtual machines.** These apps send the physical keys to another computer, which has its
///   own input method. Synthetic edits (Backspace + Vietnamese letters) are not forwarded the same way, so typing
///   there would be composed twice or garbled.
/// - **Terminals** (`CodeApps.terminals`, ruling R22): sudo, ssh, passwd and git prompts take passwords there with no
///   secure field, and commands are not Vietnamese. Code editors keep Vietnamese: their integrated terminals cannot
///   be told apart from the editor.
/// - **Password managers and macOS sign-in dialogs** (`credentialAppBundleIDs`): every field there.
/// - **Sign-in fields.** A user name, email or password must be typed exactly as the keys say. macOS hides real
///   password fields behind Secure Input (LeanKeys then never sees the keys), but many sign-in boxes are plain text
///   fields, and a user name or email field never is secure.
///
/// Called from Gõ Nhanh's `detectMethod()` slow path (at most every 200 ms, when the focus may have changed), which
/// already has the focused element and the owning app's bundle ID. One AX round trip, bounded by `axTimeout`.
public enum KeyPassthrough {
    /// Remote-control clients and virtual machines (bundle IDs). Gõ Nhanh already passes RustDesk, AnyDesk and
    /// TeamViewer through; they are listed here too so this list stands on its own.
    public static let remoteBundleIDs: Set<String> = [
        "com.carriez.rustdesk",            // RustDesk
        "com.philandro.anydesk",           // AnyDesk
        "com.teamviewer.TeamViewer",       // TeamViewer
        "dev.macviewer.app",               // MacViewer (UltraViewer-compatible)
        "com.microsoft.rdc.macos",         // Windows App / Microsoft Remote Desktop
        "com.microsoft.rdc.mac",           // Microsoft Remote Desktop 8
        "tv.parsec.www",                   // Parsec
        "com.realvnc.vncviewer",           // RealVNC Viewer
        "com.p5sys.jump.mac.viewer",       // Jump Desktop
        "com.edovia.screens.mac",          // Screens 4
        "com.edovia.screens5.mac",         // Screens 5
        "com.apple.ScreenSharing",         // Screen Sharing
        "com.splashtop.Splashtop-Business", // Splashtop Business
        "com.splashtop.Splashtop-Personal", // Splashtop Personal
        "com.nomachine.nxplayer",          // NoMachine
        "com.vmware.fusion",               // VMware Fusion
        "com.parallels.desktop.console",   // Parallels Desktop
        "com.utmapp.UTM",                  // UTM
        "org.virtualbox.app.VirtualBoxVM", // VirtualBox
        // Security audit LOW-4.
        "com.deskin.client",               // DeskIn
        "com.citrix.receiver.icaviewer.mac", // Citrix Workspace session viewer
        "com.citrix.receiver.nomas",       // Citrix Workspace
        "com.vmware.horizon",              // VMware Horizon Client
        "com.lemonmojo.RoyalTSX.App",      // Royal TSX
    ]

    /// Password managers, and the macOS dialogs that ask for a user name and password (authorization prompts, the
    /// login window). Their user name, TOTP secret and recovery-code fields are plain text fields (MEDIUM-3).
    public static let credentialAppBundleIDs: Set<String> = Exclusions.passwordManagers.union([
        "com.apple.SecurityAgent",
        "com.apple.SecurityAgentHelper.arm64",
        "com.apple.SecurityAgentHelper.x86_64",
        "com.apple.loginwindow",
    ])

    /// Single-line fields only: a sign-in box is never a text area.
    static let fieldRoles: Set<String> = ["AXTextField", "AXComboBox"]

    /// Words naming a sign-in field, matched as whole words (NFC, lowercased; identifiers split at camelCase and
    /// `_ - .`) in the field's placeholder, label, title, help, identifier or the text of its linked label.
    /// Vietnamese with and without diacritics. Phone numbers too: Vietnamese banks and e-wallets sign in with one.
    static let credentialWords: [String] = [
        "password", "passwd", "passcode", "passphrase", "pin", "otp", "2fa", "username", "user name", "userid",
        "user id", "login", "log in", "sign in", "signin", "email", "e-mail", "account", "apple id", "identifier id",
        "verification", "verify", "security code", "authenticator", "token", "secret", "cvv", "cvc", "phone",
        "mobile",
        "mật khẩu", "mat khau", "mật mã", "mat ma", "tên đăng nhập", "ten dang nhap", "tên người dùng",
        "ten nguoi dung", "đăng nhập", "dang nhap", "tài khoản", "tai khoan", "mã xác nhận", "ma xac nhan", "mã otp",
        "mã xác thực", "ma xac thuc", "xác thực", "xac thuc", "mã xác minh", "ma xac minh", "mã bảo mật",
        "ma bao mat", "mã kích hoạt", "ma kich hoat", "số điện thoại", "so dien thoai", "sđt", "sdt",
    ]

    /// Words also found inside an identifier written as one run ("userpassword", "loginemail"). Only words long and
    /// odd enough not to sit inside ordinary words ("pin" is in "shipping", "otp" in "hotpot").
    static let identifierRunWords: [String] = [
        "password", "passwd", "passcode", "passphrase", "username", "userid", "login", "signin", "email",
    ]

    static let axTimeout: Float = 0.025

    /// The attribute key `readAttributes` stores the text of the field's linked label under
    /// (`kAXTitleUIElementAttribute` → its `kAXValueAttribute`): native forms put "Mật khẩu:" in a separate static text.
    static let titleLabelKey = "AXTitleUIElement.value"

    /// The terminals the user chose to type Vietnamese in (Cài đặt › Nâng cao): bundle IDs, none by default.
    public static let terminalVietnameseKey = "LeanKeys.terminalVietnamese"

    /// The chosen terminals that are terminals (`CodeApps.terminals`); anything else stored there is ignored.
    public static func vietnameseTerminals(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: terminalVietnameseKey) ?? []).intersection(CodeApps.terminals)
    }

    /// Chooses (or no longer chooses) a terminal for Vietnamese typing.
    public static func setVietnamese(_ on: Bool, terminal bundleID: String, defaults: UserDefaults = .standard) {
        var chosen = Set(defaults.stringArray(forKey: terminalVietnameseKey) ?? [])
        if on { chosen.insert(bundleID) } else { chosen.remove(bundleID) }
        defaults.set(chosen.sorted(), forKey: terminalVietnameseKey)
    }

    /// "remote", "terminal", "credential-app", "credential", or nil to type normally. A terminal the user chose for
    /// Vietnamese types normally (its sign-in fields still pass through); it stays in `CodeApps`, so nothing typed
    /// there is learned or capitalised.
    public static func reason(bundleID: String?, focused: AXUIElement?,
                              defaults: UserDefaults = .standard) -> String? {
        if let bundleID, remoteBundleIDs.contains(bundleID) { return "remote" }
        if let bundleID, CodeApps.terminals.contains(bundleID),
           !vietnameseTerminals(defaults: defaults).contains(bundleID) { return "terminal" }
        if let bundleID, credentialAppBundleIDs.contains(bundleID) { return "credential-app" }
        guard let focused else { return nil }
        // An error or timeout reads as "not a credential field": typing must not stall or stop on a busy app.
        return isCredentialField(attributes: readAttributes(focused) ?? [:]) ? "credential" : nil
    }

    /// Pure decision on the focused element's attributes (AX attribute name → string value).
    static func isCredentialField(attributes a: [String: String]) -> Bool {
        if a[kAXSubroleAttribute as String] == "AXSecureTextField" { return true }
        guard let role = a[kAXRoleAttribute as String], fieldRoles.contains(role) else { return false }
        let labels = [kAXPlaceholderValueAttribute as String, kAXDescriptionAttribute as String,
                      kAXTitleAttribute as String, kAXHelpAttribute as String, titleLabelKey]
            .compactMap { a[$0] }.flatMap { [normalized($0), normalized($0, splitWords: false)] } // "E-mail" stays whole
        let identifiers = [kAXIdentifierAttribute as String, "AXDOMIdentifier"].compactMap { a[$0] }
        if (labels + identifiers.map { normalized($0) }).contains(where: { text in
            credentialWords.contains { containsWord(text, $0) }
        }) { return true }
        return identifiers.map { normalized($0, splitWords: false) }.contains { id in
            identifierRunWords.contains { id.contains($0) }
        }
    }

    /// NFC, lowercased; with `splitWords`, a space at each lowercase→uppercase step ("txtPassword" → "txt password")
    /// and in place of `_ - .`.
    static func normalized(_ text: String, splitWords: Bool = true) -> String {
        let nfc = text.precomposedStringWithCanonicalMapping
        guard splitWords else { return nfc.lowercased() }
        var out = ""
        var previous: Character?
        for c in nfc {
            if let p = previous, p.isLowercase, c.isUppercase { out.append(" ") }
            out.append("_-.".contains(c) ? " " : c)
            previous = c
        }
        return out.lowercased()
    }

    /// `phrase` appears in `text` with no letter or digit right before or after it ("pin" is not in "shopping").
    static func containsWord(_ text: String, _ phrase: String) -> Bool {
        var start = text.startIndex
        while let r = text.range(of: phrase, range: start..<text.endIndex) {
            let before = r.lowerBound == text.startIndex ? nil : text[text.index(before: r.lowerBound)]
            let after = r.upperBound == text.endIndex ? nil : text[r.upperBound]
            let edge: (Character?) -> Bool = { c in c.map { !($0.isLetter || $0.isNumber) } ?? true }
            if edge(before) && edge(after) { return true }
            start = text.index(after: r.lowerBound)
        }
        return false
    }

    /// One AX round trip for the attributes, capped at `axTimeout` on this element only, plus one more for the
    /// linked label's text when the role is a field role. Missing attributes read as absent. nil when the element
    /// could not be asked (timeout or another error): typing reads that as an ordinary field, learning as a secure one.
    static func readAttributes(_ element: AXUIElement) -> [String: String]? {
        AXUIElementSetMessagingTimeout(element, axTimeout)
        let names: [String] = [kAXRoleAttribute, kAXSubroleAttribute, kAXPlaceholderValueAttribute,
                               kAXDescriptionAttribute, kAXTitleAttribute, kAXIdentifierAttribute, "AXDOMIdentifier",
                               kAXHelpAttribute, kAXTitleUIElementAttribute]
        var values: CFArray?
        let result = AXUIElementCopyMultipleAttributeValues(element, names as CFArray, AXCopyMultipleAttributeOptions(),
                                                            &values)
        // An element that answers but has none of these: an ordinary element, not an unknown one.
        if [.noValue, .attributeUnsupported, .notImplemented].contains(result) { return [:] }
        guard result == .success, let list = values as? [Any] else { return nil }
        var out: [String: String] = [:]
        var label: AXUIElement?
        for (name, value) in zip(names, list) {
            if let s = value as? String, !s.isEmpty { out[name] = s }
            if name == kAXTitleUIElementAttribute, CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() {
                label = (value as! AXUIElement)
            }
        }
        if let label, let role = out[kAXRoleAttribute], fieldRoles.contains(role) {
            AXUIElementSetMessagingTimeout(label, axTimeout)
            var text: CFTypeRef?
            if AXUIElementCopyAttributeValue(label, kAXValueAttribute as CFString, &text) == .success,
               let s = text as? String, !s.isEmpty { out[titleLabelKey] = s }
        }
        return out
    }

    // MARK: Chromium and Electron

    private static let preparedLock = NSLock()
    private static var preparedPIDs: Set<pid_t> = []

    /// Electron apps (Slack, Discord, Bitwarden…) build their web accessibility tree only once an assistive client
    /// asks for it, so until then a sign-in box reads as a plain web area and its words are never seen. Sets
    /// `AXManualAccessibility` once per process, off the key thread. Called on app switch.
    public static func prepare(_ app: NSRunningApplication?) {
        guard let app, let url = app.bundleURL else { return }
        let pid = app.processIdentifier
        let fresh = preparedLock.withLock { preparedPIDs.insert(pid).inserted }
        guard fresh else { return }
        DispatchQueue.global(qos: .utility).async {
            let electron = url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
            guard FileManager.default.fileExists(atPath: electron.path) else { return }
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.25)
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
    }
}
