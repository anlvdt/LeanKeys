import AppKit

/// Non-activating floating `NSPanel`: a Google Search–style list of up to 3 suggestions under the caret
/// (spec 2026-11-28-prediction-dropdown). What the user already typed is regular, what the row adds is bold.
///
/// Plain AppKit, no SwiftUI: `show` runs on the main thread, which also runs the keyboard event tap, so the three
/// rows are built once and only their text, highlight and the window frame change, and only when they differ.
public final class CandidatePanelController {
    private final class FloatingPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    /// One clickable row (takes the first click although the panel never becomes key).
    final class RowView: NSView {
        let label = NSTextField(labelWithString: "")
        var onClick: () -> Void = {}
        var selected = false {
            didSet { if selected != oldValue { needsDisplay = true } }
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.cell?.truncatesLastVisibleLine = true
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
                label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
                label.widthAnchor.constraint(lessThanOrEqualToConstant: CandidatePanelController.maxTextWidth),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { onClick() }

        override func draw(_ dirtyRect: NSRect) {
            guard selected else { return }
            NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
    }

    static let maxTextWidth: CGFloat = 460
    static let fontSize: CGFloat = 13
    public static let hint = "↓ chọn · Tab nhận · Esc ẩn"

    private var panel: FloatingPanel?
    private var rows: [RowView] = []
    private var stack: NSStackView?
    private var onAccept: (Int) -> Void = { _ in }
    private var lastFrame: CGRect = .zero
    private var lastTexts: [String] = []
    private var lastSelected: Int?

    public private(set) var isVisible = false

    public func containsScreenPoint(_ point: CGPoint) -> Bool {
        guard isVisible, let panel, panel.isVisible else { return false }
        return panel.frame.contains(point)
    }

    public init() {}

    /// Row text: the typed part (`deleteCount` leading characters of `display`) regular, the rest bold.
    static func attributedRow(_ c: PredictionCandidate) -> NSAttributedString {
        let typedCount = c.kind == .shortcut ? 0 : min(max(c.deleteCount, 0), c.display.count)
        let split = c.display.index(c.display.startIndex, offsetBy: typedCount)
        let out = NSMutableAttributedString(string: String(c.display[..<split]), attributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        out.append(NSAttributedString(string: String(c.display[split...]), attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]))
        return out
    }

    public func show(candidates: [PredictionCandidate], anchor: CaretLocator.CaretAnchor, selectedIndex: Int? = nil,
                     onAccept: @escaping (Int) -> Void) {
        guard !candidates.isEmpty else {
            hide()
            return
        }
        ensurePanel()
        guard let panel, let stack else { return }
        self.onAccept = onAccept

        let shown = Array(candidates.prefix(rows.count))
        let texts = shown.map { "\($0.deleteCount)|\($0.display)" }
        let textsChanged = texts != lastTexts
        if textsChanged {
            for (i, row) in rows.enumerated() {
                if i < shown.count {
                    row.label.attributedStringValue = Self.attributedRow(shown[i])
                    row.isHidden = false
                } else {
                    row.isHidden = true
                }
            }
            lastTexts = texts
        }
        setSelectedIndex(selectedIndex)

        var panelSize = lastFrame.size
        if textsChanged || panelSize == .zero {
            stack.layoutSubtreeIfNeeded()
            let fitting = stack.fittingSize
            panelSize = CGSize(width: max(160, ceil(fitting.width)), height: ceil(fitting.height))
        }
        let origin = Self.panelOrigin(panelSize: panelSize, caretRect: anchor.rect)
        let frame = CGRect(origin: origin, size: panelSize)
        if frame != lastFrame {
            panel.setFrame(frame, display: false)
            lastFrame = frame
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        isVisible = true
    }

    /// Highlights row `index` (nil: none). Cheap: only the old and new rows redraw.
    public func setSelectedIndex(_ index: Int?) {
        guard index != lastSelected else { return }
        lastSelected = index
        for (i, row) in rows.enumerated() { row.selected = i == index }
    }

    public func hide() {
        isVisible = false
        guard let panel, panel.isVisible || !lastTexts.isEmpty else { return }
        lastTexts = []
        lastFrame = .zero
        setSelectedIndex(nil)
        panel.orderOut(nil)
    }

    /// Computes panel origin in Cocoa coordinates: below caret by default, flipping above if near screen bottom,
    /// and clamped horizontally inside the containing screen's `visibleFrame`.
    public static func panelOrigin(panelSize: CGSize, caretRect: CGRect, screens: [CGRect] = NSScreen.screens.map(\.visibleFrame)) -> CGPoint {
        let gap: CGFloat = 6
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
            contentRect: CGRect(x: 0, y: 0, width: 240, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isFloatingPanel = true
        p.ignoresMouseEvents = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 0.75
        background.layer?.borderColor = NSColor.separatorColor.cgColor

        let rowViews = (0..<PredictionEngine.maxCandidates).map { i -> RowView in
            let r = RowView()
            r.onClick = { [weak self] in self?.onAccept(i) }
            return r
        }
        let hint = NSTextField(labelWithString: Self.hint)
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: rowViews + [hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        stack.setCustomSpacing(3, after: rowViews[rowViews.count - 1])
        stack.translatesAutoresizingMaskIntoConstraints = false
        for r in rowViews {
            r.translatesAutoresizingMaskIntoConstraints = false
            r.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
        }
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        p.contentView = background
        self.panel = p
        self.rows = rowViews
        self.stack = stack
    }
}
