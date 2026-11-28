import AppKit
import ApplicationServices
import Foundation

/// Resolves the screen rectangle (in AppKit/Cocoa bottom-left screen coordinates) of the active text caret
/// so the 4A+ candidate bar can float right next to the user's cursor.
///
/// Safety:
/// - Never mutates `AXUIElementCreateSystemWide()` timeouts; uses `AXUIElementCreateApplication(pid)` bounded to 25 ms.
/// - Returns `nil` for secure fields, search boxes, combo/address bars, or non-zero selections.
public enum CaretLocator {
    static let axTimeout: Float = 0.025

    public struct CaretAnchor: Equatable {
        /// Screen rect in Cocoa coordinates (origin bottom-left of primary screen).
        public let rect: CGRect
        public let isFieldFallback: Bool
    }

    /// Converts a Quartz/AX global rect (origin top-left of primary screen, y down) to Cocoa screen coordinates.
    public static func cocoaRect(fromQuartz rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        guard rect.width >= 0, rect.height >= 0, primaryScreenHeight > 0 else { return .zero }
        let y = primaryScreenHeight - rect.origin.y - rect.height
        return CGRect(x: rect.origin.x, y: y, width: rect.width, height: rect.height)
    }

    public static var primaryScreenHeight: CGFloat {
        if let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) {
            return primary.frame.height
        }
        return NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
    }

    /// Queries the frontmost application's focused element for caret bounds. Returns nil when disallowed or unavailable.
    public static func currentAnchor(
        pid: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier,
        primaryScreenHeight overrideScreenHeight: CGFloat? = nil
    ) -> CaretAnchor? {
        guard let pid else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }

        let element = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(element, axTimeout)

        var roleVal: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleVal)
        let role = roleVal as? String
        if role == "AXSecureTextField" || role == "AXSearchField" || role == "AXComboBox" {
            return nil
        }

        let screenH = overrideScreenHeight ?? primaryScreenHeight
        guard screenH > 0 else { return nil }

        // 1. Standard AXSelectedTextRange -> AXBoundsForRange
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) {
                if range.length > 0 { return nil }
                var boundsRef: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(
                    element,
                    kAXBoundsForRangeParameterizedAttribute as CFString,
                    rangeRef,
                    &boundsRef
                ) == .success,
                   let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() {
                    var quartz = CGRect.zero
                    if AXValueGetValue(boundsRef as! AXValue, .cgRect, &quartz),
                       isPlausibleCaretRect(quartz) {
                        return CaretAnchor(rect: cocoaRect(fromQuartz: quartz, primaryScreenHeight: screenH),
                                           isFieldFallback: false)
                    }
                }
            }
        }

        // 2. WebKit / Chromium fallback: AXSelectedTextMarkerRange -> AXBoundsForTextMarkerRange
        var markerRangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRangeRef) == .success,
           let markerRangeRef {
            var boundsRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                "AXBoundsForTextMarkerRange" as CFString,
                markerRangeRef,
                &boundsRef
            ) == .success,
               let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() {
                var quartz = CGRect.zero
                if AXValueGetValue(boundsRef as! AXValue, .cgRect, &quartz),
                   isPlausibleCaretRect(quartz) {
                    return CaretAnchor(rect: cocoaRect(fromQuartz: quartz, primaryScreenHeight: screenH),
                                       isFieldFallback: false)
                }
            }
        }

        // 3. Field bounds fallback when caret range bounds are not exposed (e.g., some Electron/web views).
        if role == "AXTextArea" || role == "AXTextField" || role == "AXWebArea" {
            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
               AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
               let posRef, let sizeRef,
               CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() {
                var origin = CGPoint.zero
                var size = CGSize.zero
                if AXValueGetValue(posRef as! AXValue, .cgPoint, &origin),
                   AXValueGetValue(sizeRef as! AXValue, .cgSize, &size),
                   size.width > 20, size.height > 10 {
                    // Anchor near bottom-left of compact fields, or upper-left interior of tall editors.
                    let yOff = min(size.height, 44)
                    let quartz = CGRect(x: origin.x + 12, y: origin.y + yOff - 20, width: 2, height: 20)
                    return CaretAnchor(rect: cocoaRect(fromQuartz: quartz, primaryScreenHeight: screenH),
                                       isFieldFallback: true)
                }
            }
        }

        return nil
    }

    static func isPlausibleCaretRect(_ r: CGRect) -> Bool {
        !r.isNull && !r.isInfinite && r.height > 0 && r.height < 400 && (r.origin.x != 0 || r.origin.y != 0)
    }
}
