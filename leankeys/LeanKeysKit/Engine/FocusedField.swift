import AppKit
import ApplicationServices
import Foundation

/// What LeanKeys reads about the focused text field at Return. Event-tap thread; one bounded Accessibility query.
public enum FocusedField {
    /// Each Accessibility call waits at most this long, so a busy app cannot stall the key (as `KeyPassthrough`).
    static let axTimeout: Float = 0.025

    /// What the last live query saw, for the debug log: "role=AXTextArea sel=0", "role=nil sel=nil". No text.
    public private(set) static var lastNote = ""

    /// Return may finish the word being typed (Vikey D62 kept only where it matters) in a multi-line field with
    /// nothing selected: chat boxes, editors, notes. Single-line fields (address bars, search boxes) keep D62, since a
    /// fix there removes the autocompletion Return should accept; so does a selection (an inline completion) and any
    /// field Accessibility cannot describe.
    public static func allowsFixAtReturn(role: String?, selectionLength: Int?) -> Bool {
        role == "AXTextArea" && selectionLength == 0
    }

    /// `allowsFixAtReturn(role:selectionLength:)` for the field focused now; false when Accessibility does not answer.
    public static func allowsFixAtReturn() -> Bool {
        // The frontmost app's element, not the system-wide one: a timeout set on the system-wide element becomes the
        // default for every Accessibility call in the process (as LearnContextReader notes), cutting Gõ Nhanh's own
        // 0.1 s bound (axSystemWideBounded) to 25 ms. NSWorkspace's frontmost app is cached: no IPC.
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            lastNote = "no-app"
            return false
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { lastNote = "no-focus"; return false }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, axTimeout)
        var role: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleName = role as? String
        guard roleName == "AXTextArea" else { lastNote = "role=\(roleName ?? "nil")"; return false }
        var range: CFTypeRef?
        var selection: Int?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
           let range, CFGetTypeID(range) == AXValueGetTypeID() {
            var r = CFRange()
            if AXValueGetValue(range as! AXValue, .cfRange, &r) { selection = r.length }
        }
        lastNote = "role=\(roleName ?? "nil") sel=\(selection.map(String.init) ?? "nil")"
        return allowsFixAtReturn(role: roleName, selectionLength: selection)
    }
}
