// Test-only copy of the v1.14 SwiftUI candidate bar, for the before/after bench.
@testable import LeanKeysKit
import AppKit
import Combine
import SwiftUI

/// Observable state backing the floating 4A+ candidate bar.
final class LegacyCandidateBarState: ObservableObject {
    @Published var candidates: [PredictionCandidate] = []
    var onAccept: (Int) -> Void = { _ in }
}

/// Non-activating floating `NSPanel` displaying up to 3 word/phrase/sentence suggestions near the caret.
final class LegacyCandidatePanelController {
    private final class FloatingPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private let state = LegacyCandidateBarState()
    private var panel: FloatingPanel?
    private var hostingController: NSHostingController<LegacyCandidateBarView>?
    private var lastFrame: CGRect = .zero
    private var lastTexts: [String] = []

    private(set) var isVisible = false

    func containsScreenPoint(_ point: CGPoint) -> Bool {
        guard isVisible, let panel, panel.isVisible else { return false }
        return panel.frame.contains(point)
    }

    init() {}

    func show(candidates: [PredictionCandidate], anchor: CaretLocator.CaretAnchor, onAccept: @escaping (Int) -> Void) {
        guard !candidates.isEmpty else {
            hide()
            return
        }
        ensurePanel()
        guard let panel, let hostingController else { return }

        state.onAccept = onAccept
        // Same bar as before, but skip SwiftUI re-layout and window resizing when nothing changed: `show` runs on
        // the main thread, which also runs the keyboard event tap.
        let texts = candidates.map(\.display)
        let textsChanged = texts != lastTexts
        if textsChanged {
            state.candidates = candidates
            hostingController.rootView = LegacyCandidateBarView(state: state)
            lastTexts = texts
        }

        var panelSize = lastFrame.size
        if textsChanged || panelSize == .zero {
            let fitting = hostingController.sizeThatFits(in: CGSize(width: 520, height: 48))
            panelSize = CGSize(width: max(120, min(520, ceil(fitting.width))),
                               height: max(30, min(48, ceil(fitting.height))))
        }
        let origin = CandidatePanelController.panelOrigin(panelSize: panelSize, caretRect: anchor.rect)
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

    func hide() {
        isVisible = false
        guard let panel, panel.isVisible || !lastTexts.isEmpty else { return }
        state.candidates = []
        lastTexts = []
        lastFrame = .zero
        panel.orderOut(nil)
    }

    private func ensurePanel() {
        if panel != nil { return }
        let p = FloatingPanel(
            contentRect: CGRect(x: 0, y: 0, width: 240, height: 34),
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

        let host = NSHostingController(rootView: LegacyCandidateBarView(state: state))
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = .clear
        p.contentViewController = host
        self.panel = p
        self.hostingController = host
    }
}

private struct LegacyCandidateBarView: View {
    @ObservedObject var state: LegacyCandidateBarState

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(state.candidates.enumerated()), id: \.element.id) { idx, cand in
                Button {
                    state.onAccept(idx)
                } label: {
                    HStack(spacing: 5) {
                        Text(idx == 0 ? "Tab" : "⌥\(idx + 1)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(idx == 0 ? Color.accentColor : Color(NSColor.secondaryLabelColor))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(idx == 0 ? Color.accentColor.opacity(0.14) : Color(NSColor.quaternaryLabelColor).opacity(0.45))
                            )
                        Text(cand.display)
                            .font(.system(size: 12.5, weight: idx == 0 ? .medium : .regular))
                            .foregroundColor(Color(NSColor.labelColor))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: idx == 0 ? 220 : 140, alignment: .leading)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(idx == 0 ? Color.accentColor.opacity(0.08) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            LegacyPopoverBlurBackground()
                .clipShape(RoundedRectangle(cornerRadius: 9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color(NSColor.separatorColor).opacity(0.55), lineWidth: 0.75)
        )
        .fixedSize()
    }
}

private struct LegacyPopoverBlurBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
