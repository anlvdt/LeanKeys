import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Where the user is typing, read on the event-tap (main) thread when a phrase ends, and only while learning is on.
///
/// - Bundle ID: `NSWorkspace.frontmostApplication`, a cached value, no IPC.
/// - Secure Input: `IsSecureEventInputEnabled()`, a cheap system flag.
/// - Secure text field: the focused element's AX subrole. That is IPC to the app, which may be busy, so each of the
///   two AX calls is capped at `axTimeout` seconds on its own element (`AXUIElementSetMessagingTimeout` on the
///   system-wide element would change the timeout for every AX call in the process). Worst case 2 × 25 ms, once per
///   phrase. A timeout or another AX error reads as "secure", so the phrase is skipped rather than learned blind;
///   an element that simply has no subrole is not secure.
enum LearnContextReader {
    static let axTimeout: Float = 0.025

    static func current() -> LearnContext {
        let app = NSWorkspace.shared.frontmostApplication
        let secureInput = IsSecureEventInputEnabled()
        // Under Secure Input nothing is learned anyway: skip the AX round trip.
        let secureField = secureInput || app.map { isSecureField(pid: $0.processIdentifier) } ?? true
        return LearnContext(bundleID: app?.bundleIdentifier, secureInput: secureInput, secureField: secureField,
                            now: Date())
    }

    /// True when the focused element is an `AXSecureTextField`, or when that cannot be told in time.
    static func isSecureField(pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, axTimeout)
        var focused: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused)
        // No focused element (some apps expose none): not a secure field.
        if [.noValue, .attributeUnsupported, .notImplemented].contains(focusResult) { return false }
        guard focusResult == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return true }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, axTimeout)
        var subrole: CFTypeRef?
        let subroleResult = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        if [.noValue, .attributeUnsupported, .notImplemented].contains(subroleResult) { return false }
        guard subroleResult == .success else { return true }
        return (subrole as? String) == kAXSecureTextFieldSubrole
    }
}
