import AppKit
import Combine
import SwiftUI

/// Observable state backing the subtle ghost-text 4A+ suggestion row.
final class CandidateBarState: ObservableObject {
    @Published var candidates: [PredictionCandidate] = []
    var onAccept: (Int) -> Void = { _ in }
}

/// Non-activating borderless floating `NSPanel` rendering calm ghost text directly below the caret
/// without popup card chrome, borders, or flashing.
public final class CandidatePanelController {
    private final class FloatingPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private let state = CandidateBarState()
    private var panel: FloatingPanel?
    private var hostingController: NSHostingController<CandidateBarView>?
    private var visibilityToken: UInt64 = 0
    private var lastOriginY: CGFloat?

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
        guard let panel, let hostingController else { return }

        let wasVisible = isVisible && panel.isVisible
        visibilityToken &+= 1
        state.onAccept = onAccept
        state.candidates = candidates

        hostingController.view.layoutSubtreeIfNeeded()
        let fitting = hostingController.sizeThatFits(in: CGSize(width: 520, height: 36))
        let panelSize = CGSize(width: max(60, min(520, ceil(fitting.width))),
                               height: max(20, min(34, ceil(fitting.height))))
        var origin = Self.panelOrigin(panelSize: panelSize, caretRect: anchor.rect)
        if wasVisible, let prevY = lastOriginY, abs(origin.y - prevY) <= 4 {
            origin.y = prevY
        }
        lastOriginY = origin.y
        panel.setFrame(CGRect(origin: origin, size: panelSize), display: true)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !wasVisible {
            if reduceMotion {
                panel.alphaValue = 1
                panel.orderFrontRegardless()
            } else {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.14
                    panel.animator().alphaValue = 1
                }
            }
        } else {
            panel.alphaValue = 1
        }
        isVisible = true
    }

    public func hide() {
        isVisible = false
        lastOriginY = nil
        visibilityToken &+= 1
        let token = visibilityToken
        state.candidates = []
        guard let panel, panel.isVisible else { return }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.visibilityToken == token, !self.isVisible else { return }
                self.panel?.orderOut(nil)
            }
        })
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
            contentRect: CGRect(x: 0, y: 0, width: 220, height: 24),
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

        let host = NSHostingController(rootView: CandidateBarView(state: state))
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = .clear
        p.contentViewController = host
        self.panel = p
        self.hostingController = host
    }
}

private struct CandidateBarView: View {
    @ObservedObject var state: CandidateBarState

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(state.candidates.enumerated()), id: \.element.id) { idx, cand in
                if idx > 0 {
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundColor(Color(NSColor.labelColor).opacity(0.22))
                }
                Button {
                    state.onAccept(idx)
                } label: {
                    HStack(spacing: 3) {
                        Text(cand.display)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundColor(Color(NSColor.labelColor).opacity(idx == 0 ? 0.45 : 0.30))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: idx == 0 ? 220 : 140, alignment: .leading)
                        Text(idx == 0 ? "⇥" : "⌥\(idx + 1)")
                            .font(.system(size: idx == 0 ? 10 : 9.5, weight: .medium, design: .rounded))
                            .foregroundColor(Color(NSColor.labelColor).opacity(idx == 0 ? 0.28 : 0.22))
                    }
                    .shadow(color: Color(NSColor.windowBackgroundColor).opacity(0.75), radius: 1.5, x: 0, y: 0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .fixedSize()
    }
}
