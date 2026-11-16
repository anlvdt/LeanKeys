import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// The part of a `LearnContext` read on the key-handling thread: no IPC. The secure-field check (AX) is made later,
/// on the queue that records the learning, for the app captured here (`LearnContextReader.isSecureField(_:)`).
public struct LearnContextProbe: Equatable {
    public let bundleID: String?
    /// The frontmost app's process, whose focused element the queue asks about. nil reads as a secure field.
    public let pid: pid_t?
    public let secureInput: Bool
    public let now: Date

    public init(bundleID: String?, pid: pid_t?, secureInput: Bool, now: Date) {
        self.bundleID = bundleID
        self.pid = pid
        self.secureInput = secureInput
        self.now = now
    }

    /// The whole context, once the secure-field check has answered.
    public func context(secureField: Bool) -> LearnContext {
        LearnContext(bundleID: bundleID, secureInput: secureInput, secureField: secureInput || secureField, now: now)
    }
}

/// Where the user is typing, read in two halves (audit item 4: no AX on the event-tap thread):
///
/// - `probe()`, on the event-tap (main) thread, only while learning is on: the bundle ID and pid from
///   `NSWorkspace.frontmostApplication` (cached values, no IPC), `IsSecureEventInputEnabled()` (a cheap system flag)
///   and the time. Secure Input and excluded apps are decided from this, before anything is queued.
/// - `isSecureField(_:)`, on the background queue that records the learning: the focused element's AX subrole. That
///   is IPC to the app, which may be busy, so each of the two AX calls is capped at `axTimeout` seconds on its own
///   element (`AXUIElementSetMessagingTimeout` on the system-wide element would change the timeout for every AX call
///   in the process). Worst case 2 × 25 ms, off the key thread. A timeout or another AX error reads as "secure", so
///   the observation is dropped rather than learned blind; an element that simply has no subrole is not secure.
///   The field is the one focused when the queue asks, a few milliseconds after the key.
enum LearnContextReader {
    static let axTimeout: Float = 0.025

    /// Key-handling thread: no IPC.
    static func probe() -> LearnContextProbe {
        let app = NSWorkspace.shared.frontmostApplication
        return LearnContextProbe(bundleID: app?.bundleIdentifier, pid: app?.processIdentifier,
                                 secureInput: IsSecureEventInputEnabled(), now: Date())
    }

    /// Background queue only. Under Secure Input nothing is learned anyway: no AX round trip. No app: secure.
    static func isSecureField(_ probe: LearnContextProbe) -> Bool {
        probe.secureInput || probe.pid.map { isSecureField(pid: $0) } ?? true
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
