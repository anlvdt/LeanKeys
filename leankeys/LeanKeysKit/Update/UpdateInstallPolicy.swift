import Foundation
import Security

/// Whether a downloaded, verified update may install itself with no click (ruling R24).
///
/// macOS ties the Accessibility grant to the signature. A Developer ID build keeps its TeamIdentifier across
/// updates, so the grant survives and the silent install is safe. An ad-hoc build gets a new signature every
/// release: installed silently, typing would just stop until the user re-grants. Ad-hoc builds therefore still
/// download and verify silently, but wait for one click on the "update ready" menu item.
public enum UpdateInstallPolicy {
    /// True only for a non-empty team identifier.
    public static func installsSilently(teamIdentifier: String?) -> Bool {
        guard let teamIdentifier else { return false }
        return !teamIdentifier.isEmpty
    }

    /// `readTeamIdentifier` defaults to the running app's own signature.
    public static func installsSilently(readTeamIdentifier: () -> String? = currentTeamIdentifier) -> Bool {
        installsSilently(teamIdentifier: readTeamIdentifier())
    }

    /// The running process's TeamIdentifier, or nil when unsigned, ad-hoc signed, or unreadable.
    public static func currentTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
