import AppKit
import Foundation

/// Non-activating borderless floating `NSPanel` rendering calm ghost text directly below the caret
/// using lightweight pure AppKit (zero SwiftUI layout or animation overhead during typing).
public final class CandidatePanelController {
    private final class FloatingPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private var panel: FloatingPanel?
    private var barView: GhostBarView?
    private var lastOriginY: CGFloat?
    private var lastFrame: CGRect = .zero
    private var lastRenderedTexts: [String] = []

    public private(set) var isVisible = false

    public func containsScreenPoint(_ point: CGPoint) -> Bool {
        guard isVisible, let panel, panel.isVisible else { return false }
        return panel.frame.contains(point)
    }

    public init() {}

    public func show(candidates: [PredictionCandidate], anchor: CaretLocator.CaretAnchor, onAccept: @escaping (Int) -> Void) {
        guard !candidates.isEmpty else {
            hide()
            return
        }
        ensurePanel()
        guard let panel, let barView else { return }

        let wasVisible = isVisible && panel.isVisible
        barView.onAccept = onAccept
        let texts = candidates.map(\.display)
        let textsChanged = texts != lastRenderedTexts
        if textsChanged || !wasVisible {
            barView.update(candidates: candidates)
            lastRenderedTexts = texts
        }

        let fitting = barView.fittingSize
        let panelSize = CGSize(width: max(60, min(520, ceil(fitting.width))),
                               height: max(20, min(32, ceil(fitting.height))))
        var origin = Self.panelOrigin(panelSize: panelSize, caretRect: anchor.rect)
        if wasVisible, let prevY = lastOriginY, abs(origin.y - prevY) <= 4 {
            origin.y = prevY
        }
        lastOriginY = origin.y

        let nextFrame = CGRect(origin: origin, size: panelSize)
        if wasVisible && !textsChanged && nextFrame == lastFrame {
            return
        }
        if nextFrame != lastFrame {
            panel.setFrame(nextFrame, display: false)
            lastFrame = nextFrame
        }
        if textsChanged {
            barView.needsDisplay = true
        }
        if !wasVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        isVisible = true
    }

    public func hide() {
        isVisible = false
        lastOriginY = nil
        lastFrame = .zero
        lastRenderedTexts = []
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    /// Computes panel origin in Cocoa coordinates: tightly below caret (`gap = 3`), flipping above if near
    /// screen bottom, and clamped horizontally inside the containing screen's `visibleFrame`.
    public static func panelOrigin(panelSize: CGSize, caretRect: CGRect, screens: [CGRect] = NSScreen.screens.map(\.visibleFrame)) -> CGPoint {
        let gap: CGFloat = 3
        let screenFrame = screens.first(where: { $0.contains(CGPoint(x: caretRect.midX, y: caretRect.midY)) })
            ?? screens.first
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        var x = caretRect.minX
        if x + panelSize.width > screenFrame.maxX - 8 {
            x = screenFrame.maxX - panelSize.width - 8
        }
        if x < screenFrame.minX + 8 {
            x = screenFrame.minX + 8
        }

        let belowY = caretRect.minY - panelSize.height - gap
        let aboveY = caretRect.maxY + gap
        let y: CGFloat
        if belowY >= screenFrame.minY + 8 {
            y = belowY
        } else if aboveY + panelSize.height <= screenFrame.maxY - 8 {
            y = aboveY
        } else {
            y = max(screenFrame.minY + 8, min(belowY, screenFrame.maxY - panelSize.height - 8))
        }
        return CGPoint(x: round(x), y: round(y))
    }

    private func ensurePanel() {
        if panel != nil { return }
        let p = FloatingPanel(
            contentRect: CGRect(x: 0, y: 0, width: 220, height: 22),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isFloatingPanel = true
        p.ignoresMouseEvents = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let view = GhostBarView(frame: CGRect(x: 0, y: 0, width: 220, height: 22))
        p.contentView = view
        self.panel = p
        self.barView = view
    }
}

/// Single-view ghost-text renderer with zero Auto Layout or SwiftUI overhead.
private final class GhostBarView: NSView {
    private struct ChipLayout {
        let text: NSAttributedString
        let textRect: CGRect
        let hint: NSAttributedString
        let hintRect: CGRect
        let hitRect: CGRect
    }

    var onAccept: (Int) -> Void = { _ in }

    private var chips: [ChipLayout] = []
    private var separatorPositions: [(NSAttributedString, CGPoint)] = []
    private var cachedFittingSize = CGSize(width: 60, height: 22)

    private static let textFont = NSFont.systemFont(ofSize: 12.5, weight: .regular)
    private static let hintFontPrimary = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
    private static let hintFontSecondary = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium)
    private static let sepFont = NSFont.systemFont(ofSize: 11, weight: .regular)

    override var fittingSize: NSSize { cachedFittingSize }
    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    func update(candidates: [PredictionCandidate]) {
        chips.removeAll(keepingCapacity: true)
        separatorPositions.removeAll(keepingCapacity: true)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.windowBackgroundColor.withAlphaComponent(0.75)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = .zero

        let sepAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.sepFont,
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.22),
            .shadow: shadow,
        ]
        let sepAttr = NSAttributedString(string: "·", attributes: sepAttrs)
        let sepSize = sepAttr.size()

        var x: CGFloat = 4
        let height: CGFloat = 22
        let yPad: CGFloat = 3

        for (idx, cand) in candidates.prefix(PredictionEngine.maxCandidates).enumerated() {
            if idx > 0 {
                x += 6
                let sepY = round((height - sepSize.height) / 2)
                separatorPositions.append((sepAttr, CGPoint(x: x, y: sepY)))
                x += ceil(sepSize.width) + 6
            }

            let textAlpha: CGFloat = idx == 0 ? 0.48 : 0.30
            let hintAlpha: CGFloat = idx == 0 ? 0.28 : 0.22
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font: Self.textFont,
                .foregroundColor: NSColor.labelColor.withAlphaComponent(textAlpha),
                .paragraphStyle: paragraph,
                .shadow: shadow,
            ]
            let hintAttrs: [NSAttributedString.Key: Any] = [
                .font: idx == 0 ? Self.hintFontPrimary : Self.hintFontSecondary,
                .foregroundColor: NSColor.labelColor.withAlphaComponent(hintAlpha),
                .shadow: shadow,
            ]

            let attrText = NSAttributedString(string: cand.display, attributes: textAttrs)
            let maxTextW: CGFloat = idx == 0 ? 220 : 140
            let rawTextSize = attrText.size()
            let textW = min(maxTextW, ceil(rawTextSize.width))
            let textH = ceil(rawTextSize.height)

            let hintString = idx == 0 ? "⇥" : "⌥\(idx + 1)"
            let attrHint = NSAttributedString(string: hintString, attributes: hintAttrs)
            let hintSize = attrHint.size()
            let hintW = ceil(hintSize.width)
            let hintH = ceil(hintSize.height)

            let textRect = CGRect(x: x, y: max(yPad, round((height - textH) / 2)), width: textW, height: textH)
            let hintX = x + textW + 3
            let hintRect = CGRect(x: hintX, y: max(yPad, round((height - hintH) / 2)), width: hintW, height: hintH)
            let hitRect = CGRect(x: x - 2, y: 0, width: textW + 3 + hintW + 4, height: height)

            chips.append(ChipLayout(text: attrText, textRect: textRect, hint: attrHint, hintRect: hintRect, hitRect: hitRect))
            x = hintX + hintW
        }

        let totalW = max(60, min(520, ceil(x + 4)))
        cachedFittingSize = CGSize(width: totalW, height: height)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        for (sep, pt) in separatorPositions {
            sep.draw(at: pt)
        }
        for chip in chips {
            chip.text.draw(with: chip.textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            chip.hint.draw(at: chip.hintRect.origin)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if let idx = chips.firstIndex(where: { $0.hitRect.contains(pt) }) {
            onAccept(idx)
        }
    }
}
