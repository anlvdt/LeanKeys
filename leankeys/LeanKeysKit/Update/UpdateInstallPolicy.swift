import Foundation
import Security

/// Whether a downloaded, verified update may install itself with no click (ruling R24).
///
/// macOS ties the Accessibility grant to the signature. A build whose signature keeps the same identity across
/// updates keeps the grant, so the silent install is safe. Two kinds qualify: a Developer ID build (a non-empty
/// TeamIdentifier) and a build signed with a stable certificate, such as the local "LeanKeys Self-Signed"
/// certificate (spec §15.2). An ad-hoc build gets a new signature every release: installed silently, typing would
/// just stop until the user re-grants. Ad-hoc builds therefore still download and verify silently, but wait for one
/// click on the "update ready" menu item.
public enum UpdateInstallPolicy {
    /// kSecCodeSignatureAdhoc (0x2) in kSecCodeInfoFlags: the signature is ad-hoc. Not exported to Swift, so spelled out.
    private static let adhocSignatureFlag: UInt32 = 0x2

    /// How the running app is signed, as far as the update policy cares.
    public enum SignatureKind: Equatable {
        case developerID(team: String)
        case certificate
        case adhoc
        case unsigned
    }

    /// True only for a non-empty team identifier.
    public static func installsSilently(teamIdentifier: String?) -> Bool {
        guard let teamIdentifier else { return false }
        return !teamIdentifier.isEmpty
    }

    /// `readTeamIdentifier` is supplied by the caller; `installsSilently()` reads the running app's signature.
    public static func installsSilently(readTeamIdentifier: () -> String?) -> Bool {
        installsSilently(teamIdentifier: readTeamIdentifier())
    }

    /// True for a Developer ID build and for a stable certificate build; false for ad-hoc and unsigned builds.
    public static func installsSilently(signature: SignatureKind) -> Bool {
        switch signature {
        case let .developerID(team):
            return !team.isEmpty
        case .certificate:
            return true
        case .adhoc, .unsigned:
            return false
        }
    }

    /// The policy decision for the running app.
    public static func installsSilently() -> Bool {
        installsSilently(signature: currentSignature())
    }

    /// The running process's signature kind. Order: no signing info → unsigned; ad-hoc flag → adhoc; non-empty
    /// TeamIdentifier → developerID; non-empty certificate chain → certificate; otherwise adhoc.
    public static func currentSignature() -> SignatureKind {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return .unsigned }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return .unsigned }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else { return .unsigned }

        let codeFlags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        if codeFlags & adhocSignatureFlag != 0 { return .adhoc }

        if let team = dict[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return .developerID(team: team)
        }
        if let certificates = dict[kSecCodeInfoCertificates as String] as? [Any], !certificates.isEmpty {
            return .certificate
        }
        return .adhoc
    }

    /// True when the app bundle at `candidate` satisfies the running app's designated requirement. That is what macOS
    /// checks when it decides a new build is the same app (keeps the Accessibility grant). False when either side
    /// cannot be read. A silent install requires this on top of installsSilently(): see SafeInstaller.Checks.
    public static func candidateMatchesRunningIdentity(_ candidate: URL) -> Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var runningStatic: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &runningStatic) == errSecSuccess, let runningStatic else { return false }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(runningStatic, [], &requirement) == errSecSuccess,
              let requirement
        else { return false }
        var candidateStatic: SecStaticCode?
        guard SecStaticCodeCreateWithPath(candidate as CFURL, [], &candidateStatic) == errSecSuccess,
              let candidateStatic
        else { return false }
        return SecStaticCodeCheckValidity(candidateStatic, [], requirement) == errSecSuccess
    }
}
