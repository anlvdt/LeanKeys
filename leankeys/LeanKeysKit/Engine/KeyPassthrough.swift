import ApplicationServices
import Foundation

/// Where LeanKeys lets every key through untouched: no Vietnamese, no gõ tắt, no learning.
///
/// - **Remote control and virtual machines.** These apps send the physical keys to another computer, which has its
///   own input method. Synthetic edits (Backspace + Vietnamese letters) are not forwarded the same way, so typing
///   there would be composed twice or garbled.
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
    ]

    /// Single-line fields only: a sign-in box is never a text area.
    static let fieldRoles: Set<String> = ["AXTextField", "AXComboBox"]

    /// Words naming a sign-in field, matched as whole words (lowercased) in the field's placeholder, label, title or
    /// identifier. Vietnamese with and without diacritics.
    static let credentialWords: [String] = [
        "password", "passwd", "passcode", "pin", "otp", "username", "user name", "userid", "user id", "login",
        "log in", "sign in", "signin", "email", "e-mail", "account", "apple id",
        "mật khẩu", "mat khau", "tên đăng nhập", "ten dang nhap", "đăng nhập", "dang nhap", "tài khoản",
        "tai khoan", "mã xác nhận", "ma xac nhan", "mã otp",
    ]

    static let axTimeout: Float = 0.025

    /// "remote", "credential", or nil to type normally.
    public static func reason(bundleID: String?, focused: AXUIElement?) -> String? {
        if let bundleID, remoteBundleIDs.contains(bundleID) { return "remote" }
        guard let focused else { return nil }
        return isCredentialField(attributes: readAttributes(focused)) ? "credential" : nil
    }

    /// Pure decision on the focused element's attributes (AX attribute name → string value).
    static func isCredentialField(attributes a: [String: String]) -> Bool {
        if a[kAXSubroleAttribute as String] == "AXSecureTextField" { return true }
        guard let role = a[kAXRoleAttribute as String], fieldRoles.contains(role) else { return false }
        let texts = [kAXPlaceholderValueAttribute as String, kAXDescriptionAttribute as String,
                     kAXTitleAttribute as String, kAXIdentifierAttribute as String, "AXDOMIdentifier"]
            .compactMap { a[$0]?.lowercased() }
        return texts.contains { text in credentialWords.contains { containsWord(text, $0) } }
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

    /// One AX round trip for all the attributes, capped at `axTimeout` on this element only. Missing attributes,
    /// errors and timeouts read as absent: the field types normally.
    private static func readAttributes(_ element: AXUIElement) -> [String: String] {
        AXUIElementSetMessagingTimeout(element, axTimeout)
        let names: [String] = [kAXRoleAttribute, kAXSubroleAttribute, kAXPlaceholderValueAttribute,
                               kAXDescriptionAttribute, kAXTitleAttribute, kAXIdentifierAttribute, "AXDOMIdentifier"]
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names as CFArray, AXCopyMultipleAttributeOptions(),
                                                     &values) == .success,
              let list = values as? [Any] else { return [:] }
        var out: [String: String] = [:]
        for (name, value) in zip(names, list) {
            if let s = value as? String, !s.isEmpty { out[name] = s }
        }
        return out
    }
}
