import AppKit
import Combine
import SwiftUI
import XCTest
@testable import LeanKeysKit

/// Writes review images to docs/ui/ when LEANKEYS_SNAPSHOTS=1. Otherwise it is skipped, so swift test writes nothing.
/// Rendering goes through NSHostingView and cacheDisplay: ImageRenderer draws AppKit-backed Toggle and Picker as placeholders.
final class UISnapshotTests: XCTestCase {
    private struct RenderError: Error {
        let message: String
    }

    @MainActor
    func testRenderReviewImages() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LEANKEYS_SNAPSHOTS"] == "1",
            "Set LEANKEYS_SNAPSHOTS=1 to write review images to docs/ui/"
        )

        let outDir = Self.outDir()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let appearances: [(label: String, appearance: NSAppearance.Name)] = [
            ("light", .aqua),
            ("dark", .darkAqua),
        ]
        let vietnameseOn = StatusSnapshot(vietnamese: true, autoSwitchApplies: true, autoSwitchOn: true, blocked: false, blockingApp: nil)
        let blockedByOnePassword = StatusSnapshot(vietnamese: true, autoSwitchApplies: true, autoSwitchOn: true, blocked: true, blockingApp: "1Password")

        for (label, name) in appearances {
            let appearance = try XCTUnwrap(NSAppearance(named: name))

            let popover = StatusPopoverView(model: StatusPopoverModel(actions: Self.popoverActions(vietnameseOn)))
                .background(Color(NSColor.windowBackgroundColor))
            try Self.render(
                popover, width: 280, height: nil, appearance: appearance,
                to: outDir.appendingPathComponent("popover-\(label).png")
            )

            let blocked = StatusPopoverView(model: StatusPopoverModel(actions: Self.popoverActions(blockedByOnePassword)))
                .background(Color(NSColor.windowBackgroundColor))
            try Self.render(
                blocked, width: 280, height: nil, appearance: appearance,
                to: outDir.appendingPathComponent("popover-blocked-\(label).png")
            )

            // 4B: the popover with suggestions waiting, the list (fake data only), and the settings.
            let withSuggestions = StatusPopoverView(model: StatusPopoverModel(actions: Self.popoverActions(vietnameseOn, suggestions: 2)))
                .background(Color(NSColor.windowBackgroundColor))
            try Self.render(
                withSuggestions, width: 280, height: nil, appearance: appearance,
                to: outDir.appendingPathComponent("popover-suggestions-\(label).png")
            )

            let list = ShortcutSuggestionsView(model: .preview(candidates: ShortcutSuggestionsModel.sampleCandidates))
                .background(Color(NSColor.windowBackgroundColor))
            try Self.render(
                list, width: 440, height: nil, appearance: appearance,
                to: outDir.appendingPathComponent("shortcut-suggestions-\(label).png")
            )

            let learnModel = ShortcutSuggestionsModel.preview()
            let learnSettings = VStack(alignment: .leading, spacing: 20) {
                LearnSettingsSection(model: learnModel, part: .general)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
                LearnSettingsSection(model: learnModel, part: .advanced)
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
            try Self.render(
                learnSettings, width: 520, height: nil, appearance: appearance,
                to: outDir.appendingPathComponent("settings-learn-\(label).png")
            )

            let consent = LearnConsentView(confirm: {}, cancel: {})
                .background(Color(NSColor.windowBackgroundColor))
            try Self.render(
                consent, width: 380, height: nil, appearance: appearance,
                to: outDir.appendingPathComponent("settings-learn-consent-\(label).png")
            )

            let settings = SettingsRootView(
                logo: Self.logo(),
                name: "LeanKeys",
                version: "1.0",
                badge: AnyView(Text("Vikey")),
                general: AnyView(Text("Chung")),
                shortcuts: AnyView(Text("Phím tắt")),
                advanced: AnyView(Text("Nâng cao")),
                about: AnyView(Text("Giới thiệu")),
                pageRequests: Empty<SettingsPage, Never>().eraseToAnyPublisher()
            )
            try Self.render(
                settings, width: 700, height: 480, appearance: appearance,
                to: outDir.appendingPathComponent("settings-root-\(label).png")
            )
        }
    }

    /// 4C: the "Tự sửa và tự học" card with fake rules (a memory-only book, never the real store).
    @MainActor
    func testRenderUndoLearningImages() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LEANKEYS_SNAPSHOTS"] == "1",
            "Set LEANKEYS_SNAPSHOTS=1 to write review images to docs/ui/"
        )
        let outDir = Self.outDir()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let model = UndoLearning.preview(records: [("its", "about"), ("cos", ""), ("cos", ""), ("user", "new")])
        XCTAssertEqual(model.rules.count, 3)
        for (label, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            let card = UndoLearningSection(model: model)
                .padding(20)
                .background(Color(NSColor.windowBackgroundColor))
            let url = outDir.appendingPathComponent("settings-undo-learning-\(label).png")
            try? FileManager.default.removeItem(at: url)
            try Self.render(card, width: 520, height: nil, appearance: appearance, to: url)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(url.lastPathComponent) was not written")
        }
    }

    /// docs/ui/: this file is leankeys/Tests/LeanKeysKitTests/UISnapshotTests.swift, so four levels up is the repo root.
    private static func outDir() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/ui", isDirectory: true)
    }

    private static func popoverActions(_ snapshot: StatusSnapshot, suggestions: Int = 0) -> StatusPopoverActions {
        StatusPopoverActions(
            snapshot: { snapshot },
            method: { 0 },
            updateReady: { true },
            setVietnamese: { _ in },
            setMethod: { _ in },
            installUpdate: {},
            openSettings: {},
            quit: {},
            suggestionCount: { suggestions }
        )
    }

    /// A plain placeholder icon, so the snapshot does not depend on the test host's app icon.
    private static func logo() -> NSImage {
        NSImage(size: NSSize(width: 48, height: 48), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            return true
        }
    }

    /// Lays the view out in an offscreen window, then draws it at 2x into a PNG. A nil height fits the content.
    @MainActor
    private static func render<V: View>(
        _ view: V, width: CGFloat, height: CGFloat?, appearance: NSAppearance, to url: URL
    ) throws {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        host.frame = NSRect(x: 0, y: 0, width: width, height: height ?? 1000)

        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.appearance = appearance
        window.contentView = host
        if height == nil {
            host.frame.size.height = ceil(host.fittingSize.height)
            window.setContentSize(host.frame.size)
        }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let size = host.bounds.size
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw RenderError(message: "could not allocate bitmap for \(url.lastPathComponent)")
        }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]), !data.isEmpty else {
            throw RenderError(message: "could not encode \(url.lastPathComponent)")
        }
        try data.write(to: url, options: .atomic)
        try verifyPNG(at: url, pointWidth: width, pointHeight: size.height)
    }

    /// Reads the written PNG back and checks its size at 2x, and that it is not a single flat color.
    private static func verifyPNG(at url: URL, pointWidth: CGFloat, pointHeight: CGFloat) throws {
        let data = try Data(contentsOf: url)
        XCTAssertFalse(data.isEmpty, "\(url.lastPathComponent) is empty")
        let read = try XCTUnwrap(NSBitmapImageRep(data: data), "\(url.lastPathComponent) is not a readable PNG")
        XCTAssertEqual(read.pixelsWide, Int(pointWidth * 2), "\(url.lastPathComponent) width is not 2x")
        XCTAssertEqual(read.pixelsHigh, Int(pointHeight * 2), "\(url.lastPathComponent) height is not 2x")
        XCTAssertGreaterThan(read.pixelsHigh, 0, "\(url.lastPathComponent) has no height")

        // Sample a coarse 8x8 grid; a blank or single-color render has no luminance spread.
        var low = 1.0
        var high = 0.0
        for row in 1...8 {
            for col in 1...8 {
                let x = read.pixelsWide * col / 9
                let y = read.pixelsHigh * row / 9
                guard let color = read.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luminance = 0.2126 * Double(color.redComponent)
                    + 0.7152 * Double(color.greenComponent)
                    + 0.0722 * Double(color.blueComponent)
                low = min(low, luminance)
                high = max(high, luminance)
            }
        }
        XCTAssertGreaterThan(high - low, 0.1, "\(url.lastPathComponent) looks like a single flat color")
    }
}
