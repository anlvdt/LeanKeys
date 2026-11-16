import AppKit
import Foundation
import LeanKeysKit // LEANKEYS-HOOK: branding
import SwiftUI

extension Notification.Name {
    static let updateStateChanged = Notification.Name("gonhanh.updateStateChanged")
}

// MARK: - Update State

enum UpdateState {
    case idle
    case checking
    case available(UpdateInfo)
    case downloading(progress: Double)
    case readyToInstall(dmgPath: URL)
    case upToDate
    case error(String)
}

// MARK: - Update Manager

class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()

    @Published var state: UpdateState = .idle {
        didSet { popoverStateChanged(); NotificationCenter.default.post(name: .updateStateChanged, object: nil) } // LEANKEYS-HOOK: branding
    }

    private var downloadTask: URLSessionDownloadTask?
    private var updateWindow: NSWindow?
    private var backgroundTimer: Timer?
    private var idleInstallTimer: Timer? // LEANKEYS-HOOK: branding
    private var popoverInstallRequested = false // LEANKEYS-HOOK: branding

    private let checkInterval: TimeInterval = 60 * 60 // 1 hour
    private let dmgKey = "gonhanh.update.dmgPath"
    private let versionKey = "gonhanh.update.pendingVersion"

    override private init() {
        super.init()
        // Restore pending update from previous session
        if let path = UserDefaults.standard.string(forKey: dmgKey),
           SafeInstaller.isExpectedUpdatePath(path, caches: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]), // LEANKEYS-HOOK: branding
           FileManager.default.fileExists(atPath: path)
        {
            let version = UserDefaults.standard.string(forKey: versionKey) ?? "?"
            state = .readyToInstall(dmgPath: URL(fileURLWithPath: path))
            pendingVersion = version
        }
    }

    /// Version string of the pending update
    var pendingVersion: String = ""

    // MARK: - Computed Properties

    var isChecking: Bool {
        if case .checking = state {
            return true
        }
        return false
    }

    var updateAvailable: Bool {
        if case .available = state {
            return true
        }
        if case .readyToInstall = state {
            return true
        }
        return false
    }

    var isReadyToInstall: Bool {
        if case .readyToInstall = state {
            return true
        }
        return false
    }

    // MARK: - Public API

    /// Start background auto-update loop (call once at app launch)
    func startBackgroundUpdates() {
        // Check immediately on launch
        checkAndDownloadSilently()
        // Then every hour
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkAndDownloadSilently()
        }
        installWhenIdle() // LEANKEYS-HOOK: branding
    }

    /// User manually checks (only shows window if update available)
    func checkForUpdatesManually() {
        if case let .readyToInstall(dmgPath) = state {
            // Verify DMG still exists before restart
            if FileManager.default.fileExists(atPath: dmgPath.path) {
                restartToUpdate()
            } else {
                // DMG deleted — re-check
                state = .idle
            }
            return
        }
        // Prevent concurrent checks
        if case .checking = state {
            return
        }
        state = .checking
        UpdateChecker.shared.checkForUpdates { [weak self] result in
            guard let self else { return }
            switch result {
            case let .available(info):
                state = .available(info)
                showUpdateWindow()
            case .upToDate:
                state = .upToDate
            case let .error(message):
                state = .error(message)
            }
        }
    }

    /// Download update (from popup CTA)
    func downloadUpdate(_ info: UpdateInfo) {
        state = .downloading(progress: 0)
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        downloadTask = session.downloadTask(with: info.downloadURL)
        downloadTask?.resume()
    }

    /// Mount DMG, copy .app to /Applications, relaunch
    func restartToUpdate() {
        guard case let .readyToInstall(dmgPath) = state else { return }
        // LEANKEYS-HOOK-BEGIN: branding
        // Gõ Nhanh's script here mounted with -noverify, checked nothing and deleted the app before copying.
        // The click goes through the same verified install as the unattended one (installSafely, below).
        #if DEBUG
            _ = dmgPath
            return // Ruling R23: a Debug build never updates itself.
        #else
            installSafely(dmgPath, silent: false)
        #endif
        // LEANKEYS-HOOK-END
    }

    func dismiss() {
        switch state {
        case .available, .upToDate, .error: state = .idle
        default: break
        }
        dismissWindow()
    }

    // MARK: - Window Management

    func showUpdateWindow() {
        if updateWindow == nil {
            let view = UpdatePopupView()
            let controller = NSHostingController(rootView: view)
            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 10),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = controller
            window.title = "Cập nhật phần mềm"
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.hasShadow = true
            window.level = .floating
            window.center()
            window.isReleasedWhenClosed = false
            updateWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        updateWindow?.makeKeyAndOrderFront(nil)
    }

    private func dismissWindow() {
        updateWindow?.close()
    }

    // MARK: - Background Silent Check + Download

    private func checkAndDownloadSilently() {
        // Skip if currently downloading or user is checking
        if case .downloading = state {
            return
        }
        if case .checking = state {
            return
        }

        UpdateChecker.shared.checkForUpdates { [weak self] result in
            guard let self else { return }
            switch result {
            case let .available(info):
                // Skip if same version already downloaded
                if info.version == pendingVersion, case .readyToInstall = state {
                    return
                }
                // Download new version (or newer version replacing old pending)
                pendingVersion = info.version
                downloadSilently(info)
            case .upToDate, .error:
                break
            }
        }
    }

    private func downloadSilently(_ info: UpdateInfo) {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        downloadTask = session.downloadTask(with: info.downloadURL)
        downloadTask?.resume()
        // Don't update state to .downloading — keep it silent
    }

    fileprivate func finishDownload(to destinationURL: URL) {
        UserDefaults.standard.set(destinationURL.path, forKey: dmgKey)
        UserDefaults.standard.set(pendingVersion, forKey: versionKey)
        state = .readyToInstall(dmgPath: destinationURL)
        installWhenIdle() // LEANKEYS-HOOK: branding
    }
}

// MARK: - URLSession Download Delegate

extension UpdateManager: URLSessionDownloadDelegate {
    func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) { // LEANKEYS-HOOK: branding
        // LEANKEYS-HOOK-BEGIN: branding
        // An HTTP error page must not be kept as the update.
        guard SafeInstaller.isSuccessfulDownload(downloadTask.response) else {
            if case .downloading = state {
                state = .error("Tải về thất bại")
            }
            return
        }
        // LEANKEYS-HOOK-END
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let destinationURL = cachesURL.appendingPathComponent("GoNhanh-update.dmg")

        do {
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: location, to: destinationURL)
            finishDownload(to: destinationURL)
        } catch {
            if case .downloading = state {
                state = .error("Không thể lưu bản cập nhật")
            }
        }
    }

    func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Only show progress if user triggered download manually
        if case .downloading = state {
            state = .downloading(progress: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, (error as NSError).code != NSURLErrorCancelled {
            if case .downloading = state {
                state = .error("Tải về thất bại")
            }
        }
    }
}

// MARK: - Update Popup View

struct UpdatePopupView: View {
    @ObservedObject private var manager = UpdateManager.shared

    private var popupWidth: CGFloat {
        if case .available = manager.state {
            return 480
        }
        return 360
    }

    var body: some View {
        VStack(spacing: 0) {
            switch manager.state {
            case .checking:
                checkingContent
            case let .available(info):
                availableContent(info)
            case let .downloading(progress):
                downloadingContent(progress)
            case .readyToInstall:
                readyContent
            case .upToDate:
                upToDateContent
            case let .error(message):
                errorContent(message)
            default:
                EmptyView()
            }
        }
        .frame(width: popupWidth)
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
    }

    // MARK: - Checking

    private var checkingContent: some View {
        VStack(spacing: 16) {
            appIcon
            Text("Đang kiểm tra cập nhật...")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            ProgressView()
                .controlSize(.small)
        }
        .padding(32)
    }

    // MARK: - Update Available

    private func availableContent(_ info: UpdateInfo) -> some View {
        VStack(spacing: 0) {
            // Version info
            Text("\(AppMetadata.name) \(info.version) đã sẵn sàng — bạn đang dùng \(AppMetadata.version)")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 12)

            // Release notes
            if !info.releaseNotes.isEmpty {
                releaseNotesPanel(info.releaseNotes)
                    .padding(.horizontal, 20)
            }

            // CTA
            HStack(spacing: 10) {
                Spacer()
                Button("Để sau") { manager.dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Cập nhật") { manager.downloadUpdate(info) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 18)
        }
    }

    // MARK: - Downloading

    private func downloadingContent(_ progress: Double) -> some View {
        VStack(spacing: 16) {
            appIcon
            Text("Đang tải cập nhật...")
                .font(.system(size: 14, weight: .medium))

            VStack(spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Button(action: { manager.dismiss() }) {
                Text("Ẩn")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(28)
    }

    // MARK: - Ready to Install

    private var readyContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.uturn.forward.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.orange)

            Text("Bản cập nhật đã sẵn sàng")
                .font(.system(size: 15, weight: .semibold))

            Text("Phiên bản \(manager.pendingVersion) đã được tải về.\nKhởi động lại để áp dụng bản cập nhật.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            HStack(spacing: 10) {
                Spacer()
                Button("Để sau") { manager.dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Khởi động lại") { manager.restartToUpdate() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(28)
    }

    // MARK: - Up to Date

    private var upToDateContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)

            Text("Bạn đang dùng phiên bản mới nhất")
                .font(.system(size: 14, weight: .medium))

            Text("v\(AppMetadata.version)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Button(action: { manager.dismiss() }) {
                Text("OK")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 80)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
    }

    // MARK: - Error

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text("Không thể kiểm tra cập nhật")
                .font(.system(size: 14, weight: .medium))

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { manager.dismiss() }) {
                Text("OK")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 80)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
    }

    // MARK: - Components

    private var appIcon: some View {
        Image(nsImage: AppMetadata.logo)
            .resizable()
            .frame(width: 64, height: 64)
    }

    // MARK: - Release Notes

    private enum NoteItem {
        case heading(String)
        case bullet(String)
    }

    private func releaseNotesPanel(_ notes: String) -> some View {
        let items = parseReleaseNotes(notes)
        return ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    noteItemView(item)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 170)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func noteItemView(_ item: NoteItem) -> some View {
        switch item {
        case let .heading(text):
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary.opacity(0.7))
                .padding(.top, 6)
                .padding(.bottom, 1)
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                    .font(.system(size: 9))
                    .foregroundColor(.primary.opacity(0.35))
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func parseReleaseNotes(_ text: String) -> [NoteItem] {
        var items: [NoteItem] = []
        for line in text.components(separatedBy: .newlines) {
            var l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty {
                continue
            }
            if l.allSatisfy({ $0 == "-" || $0 == "=" || $0 == "*" }) {
                continue
            }
            if l.lowercased().contains("what's changed") {
                continue
            }
            if l.lowercased().contains("full changelog") {
                continue
            }

            if l.hasPrefix("#") {
                while l.hasPrefix("#") {
                    l = String(l.dropFirst())
                }
                l = cleanNote(l)
                if !l.isEmpty {
                    items.append(.heading(l))
                }
                continue
            }

            if l.hasPrefix("- ") || l.hasPrefix("* ") {
                l = String(l.dropFirst(2))
                l = cleanNote(l)
                if !l.isEmpty {
                    items.append(.bullet(l))
                }
                continue
            }

            l = cleanNote(l)
            if !l.isEmpty {
                items.append(.bullet(l))
            }
        }
        return items
    }

    private func cleanNote(_ text: String) -> String {
        var l = text.trimmingCharacters(in: .whitespaces)
        l = l.replacingOccurrences(of: "**", with: "")
        l = l.replacingOccurrences(of: "__", with: "")
        l = l.replacingOccurrences(of: "`", with: "")
        return l.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
// LEANKEYS-HOOK-BEGIN: branding

extension UpdateManager {
    /// LeanKeys installs a downloaded update by itself (spec §13.2), with no dialog: only once no key has been
    /// pressed for 30 s (IdleGate), so never mid-typing; otherwise it looks again every 60 s. A pending update
    /// restored at launch goes the same way. The install is installSafely below.
    /// Ruling R24: only a build signed with a team (Developer ID) does this. An ad-hoc build would lose its
    /// Accessibility grant on every update, so it stops at "ready": Gõ Nhanh's "⟳ Khởi động lại để cập nhật" menu
    /// item, whose click (restartToUpdate) runs the same installSafely.
    /// Spec §16.3: an update the user asked for from the popover installs at once, without the idle wait.
    private func installWhenIdle() {
        #if DEBUG
            popoverInstallRequested = false // The popover falls back to "Cài bản mới" rather than spin on "Đang cài".
            NotificationCenter.default.post(name: .updateStateChanged, object: nil)
            return // Ruling R23: a Debug build never updates itself.
        #else
        if popoverInstallRequested, case let .readyToInstall(dmgPath) = state {
            installFromPopover(dmgPath)
            return
        }
        guard isReadyToInstall, UpdateInstallPolicy.installsSilently() else { return }
        if tryInstallIfIdle() { return }
        guard idleInstallTimer == nil else { return }
        idleInstallTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            guard isReadyToInstall else {
                timer.invalidate()
                idleInstallTimer = nil
                return
            }
            if tryInstallIfIdle() {
                timer.invalidate()
                idleInstallTimer = nil
            }
        }
        #endif
    }

    /// Starts the install if the update file is still there and the user is idle; true once started (the outcome
    /// arrives later). A missing file drops the pending state.
    private func tryInstallIfIdle() -> Bool {
        guard case let .readyToInstall(dmgPath) = state else { return false }
        guard FileManager.default.fileExists(atPath: dmgPath.path) else {
            UserDefaults.standard.removeObject(forKey: dmgKey)
            UserDefaults.standard.removeObject(forKey: versionKey)
            state = .idle
            return false
        }
        guard IdleGate().isIdle else { return false }
        installSafely(dmgPath, silent: true)
        return true
    }

    /// Not Gõ Nhanh's restartToUpdate: SafeInstaller mounts and checks the update off the main thread, and the app
    /// quits only once the swap script (which always relaunches an app) has started. Any failure drops the update,
    /// logs it, and leaves this app running. Security audit MEDIUM-5: the click ("Khởi động lại để cập nhật") runs the
    /// popover's checks: a stably signed update, newer than this app, carrying this app's designated requirement when
    /// this app is stably signed. An update with a different identity is dropped, not kept for the click.
    private func installSafely(_ dmgPath: URL, silent: Bool) {
        let installedApp = URL(fileURLWithPath: Bundle.main.bundlePath)
        let bundleID = Bundle.main.bundleIdentifier
        let requireSameIdentity = silent || UpdateInstallPolicy.installsSilently()
        let currentVersion = AppMetadata.version
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let preparation = SafeInstaller.prepare(dmg: dmgPath, appName: LeanBranding.name, expectedBundleID: bundleID,
                                                    requireSameIdentity: requireSameIdentity, requireStableSignature: true,
                                                    currentVersion: currentVersion)
            DispatchQueue.main.async {
                guard let self else { return }
                if case let .prepared(prepared) = preparation,
                   SafeInstaller.launchSwap(prepared, dmg: dmgPath, installedApp: installedApp)
                {
                    UserDefaults.standard.removeObject(forKey: self.dmgKey)
                    UserDefaults.standard.removeObject(forKey: self.versionKey)
                    NSApp.terminate(nil)
                    return
                }
                try? FileManager.default.removeItem(at: dmgPath)
                UserDefaults.standard.removeObject(forKey: self.dmgKey)
                UserDefaults.standard.removeObject(forKey: self.versionKey)
                self.pendingVersion = ""
                self.state = .idle
            }
        }
    }

    // MARK: Popover (spec §16)

    /// What the popover's update row shows.
    var popoverPhase: PopoverUpdateRow.Phase {
        let source: PopoverUpdateRow.Source
        switch state {
        case .idle: source = .idle
        case .checking: source = .checking
        case .available: source = .available
        case let .downloading(progress): source = .downloading(progress: progress)
        case .readyToInstall: source = .readyToInstall
        case .upToDate: source = .upToDate
        case let .error(message): source = .error(message)
        }
        return PopoverUpdateRow.phase(source: source, installRequested: popoverInstallRequested)
    }

    /// "Kiểm tra cập nhật" / "Thử lại" in the popover: check, and if there is a newer version download it with progress
    /// and install it straight away. No window, no second click.
    func checkFromPopover() {
        switch state {
        case .checking:
            return // The About page or the legacy menu is checking; its own flow goes on.
        case .downloading:
            popoverInstallRequested = true // The legacy window's download: install it when done.
            return
        case .readyToInstall:
            installFromPopoverNow()
            return
        case .idle, .available, .upToDate, .error:
            break
        }
        popoverInstallRequested = true
        // A silent background download may be running: adopt it (progress shows, it installs when done) rather than
        // start a second one into the same file.
        if downloadTask?.state == .running {
            state = .downloading(progress: 0)
            return
        }
        state = .checking
        UpdateChecker.shared.checkForUpdates { [weak self] result in
            guard let self, case .checking = state else { return }
            switch result {
            case let .available(info):
                pendingVersion = info.version
                downloadUpdate(info)
            case .upToDate:
                state = .upToDate
            case let .error(message):
                state = .error(message)
            }
        }
    }

    /// "Cài bản mới" in the popover: install the downloaded update now, through the popover's checks.
    func installFromPopoverNow() {
        guard isReadyToInstall else { return }
        popoverInstallRequested = true
        installWhenIdle()
    }

    /// The popover closed: a finished check's result goes back to the "Kiểm tra cập nhật" button.
    func popoverClosed() {
        switch state {
        case .upToDate, .error: state = .idle
        default: break
        }
    }

    /// Called from `state`'s didSet: a check that ended (or was dismissed) ends the user's install request, so a later
    /// background download is not installed without the idle wait.
    private func popoverStateChanged() {
        switch state {
        case .idle, .upToDate, .error: popoverInstallRequested = false
        case .checking, .available, .downloading, .readyToInstall: break
        }
    }

    /// The popover's install. Like installSafely(silent: false), but it never accepts an ad-hoc build: from a stably
    /// signed app the update must carry the same identity; from an ad-hoc app it must at least be stably signed (the
    /// §15.3 move). Any refusal drops the update and shows one line in the popover.
    private func installFromPopover(_ dmgPath: URL) {
        idleInstallTimer?.invalidate() // One install at a time: no unattended attempt alongside this one.
        idleInstallTimer = nil
        let installedApp = URL(fileURLWithPath: Bundle.main.bundlePath)
        let bundleID = Bundle.main.bundleIdentifier
        let requireSameIdentity = UpdateInstallPolicy.installsSilently()
        let currentVersion = AppMetadata.version
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let preparation = SafeInstaller.prepare(dmg: dmgPath, appName: LeanBranding.name, expectedBundleID: bundleID,
                                                    requireSameIdentity: requireSameIdentity, requireStableSignature: true,
                                                    currentVersion: currentVersion)
            DispatchQueue.main.async {
                guard let self else { return }
                if case let .prepared(prepared) = preparation,
                   SafeInstaller.launchSwap(prepared, dmg: dmgPath, installedApp: installedApp)
                {
                    UserDefaults.standard.removeObject(forKey: self.dmgKey)
                    UserDefaults.standard.removeObject(forKey: self.versionKey)
                    NSApp.terminate(nil)
                    return
                }
                try? FileManager.default.removeItem(at: dmgPath)
                UserDefaults.standard.removeObject(forKey: self.dmgKey)
                UserDefaults.standard.removeObject(forKey: self.versionKey)
                self.pendingVersion = ""
                self.state = .error(PopoverUpdateRow.Failure.installMessage)
            }
        }
    }
}
// LEANKEYS-HOOK-END
