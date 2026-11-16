import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Where a `LearnSettingsSection` sits.
public enum LearnSettingsPart {
    /// The "Gợi ý gõ tắt" row on Chung (inside Gõ Nhanh's Mở rộng card), with the first-time explanation sheet.
    case general
    /// The card on Nâng cao: threshold, excluded apps, erase.
    case advanced
}

/// 4B settings. Copies the look of Gõ Nhanh's `SettingsToggleRow` and card (they live in the app target).
public struct LearnSettingsSection: View {
    static let toggleTitle = "Gợi ý gõ tắt"
    static let toggleSubtitle = "Cho địa chỉ, số điện thoại… bạn hay gõ lại. Chỉ lưu trên máy này."
    static let consentText = "LeanKeys sẽ đếm các cụm bạn gõ lặp lại (địa chỉ, số điện thoại, mã số thuế…) để gợi ý gõ tắt. Dữ liệu chỉ nằm trên máy này, được mã hoá, và bạn xoá được bất cứ lúc nào. Không học trong ô mật khẩu. Gợi ý bạn thêm vào Bảng gõ tắt được lưu như các gõ tắt khác, không mã hoá."
    static let consentConfirm = "Bật"
    static let consentCancel = "Huỷ"
    static let advancedTitle = "Gợi ý gõ tắt"
    static let thresholdTitle = "Gợi ý khi gõ lại"
    static let thresholdNote = "trong 30 ngày, với cụm từ 8 ký tự trở lên"
    static let excludedTitle = "Không học khi gõ trong"
    /// Tooltip on `excludedTitle`: the list also governs 4C and 4D learning (spec §12.3).
    static let excludedHelp = "Áp dụng cho gợi ý gõ tắt, từ giữ nguyên và tên đã học. Các ứng dụng mặc định không bỏ được."
    static let addAppLabel = "Thêm ứng dụng…"
    static let eraseLabel = "Xoá dữ liệu gợi ý gõ tắt"
    static let eraseConfirmTitle = "Xoá dữ liệu gợi ý gõ tắt?"
    static let eraseConfirmMessage = "Mọi số đếm và gợi ý đang chờ sẽ bị xoá. Bảng gõ tắt vẫn giữ nguyên. Không hoàn tác được."
    /// Shown after a default (not removable) excluded app.
    static let defaultTag = "mặc định"
    static let eraseConfirm = "Xoá"

    @ObservedObject private var model: ShortcutSuggestionsModel
    private let part: LearnSettingsPart
    @State private var confirmErase = false

    public init(model: ShortcutSuggestionsModel, part: LearnSettingsPart) {
        self.model = model
        self.part = part
    }

    public var body: some View {
        switch part {
        case .general: toggleRow
        case .advanced: advancedCard
        }
    }

    // MARK: Chung

    private var toggleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.toggleTitle).font(.system(size: 13))
                Text(Self.toggleSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .lineLimit(1)
                    .help(Self.toggleSubtitle)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel(Text(Self.toggleTitle))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .sheet(isPresented: Binding(get: { model.consentPending }, set: { if !$0 { model.cancelConsent() } })) {
            LearnConsentView(confirm: { model.confirmConsent() }, cancel: { model.cancelConsent() })
        }
    }

    // MARK: Nâng cao

    private var advancedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.advancedTitle)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.thresholdTitle).font(.system(size: 13))
                    Text(Self.thresholdNote)
                        .font(.system(size: 11))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                        .lineLimit(1)
                }
                Spacer()
                Picker(Self.thresholdTitle, selection: $model.threshold) {
                    ForEach(ShortcutSuggestionsModel.thresholdChoices, id: \.self) { Text("\($0) lần").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().padding(.leading, 12)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(Self.excludedTitle).font(.system(size: 13)).help(Self.excludedHelp)
                    Spacer()
                    Button(Self.addAppLabel, action: chooseApp).controlSize(.small)
                }
                ForEach(Self.sortedDefaults, id: \.self) { id in
                    excludedRow(id, removable: false)
                }
                ForEach(model.userExcludedApps, id: \.self) { id in
                    excludedRow(id, removable: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().padding(.leading, 12)

            HStack {
                Button(Self.eraseLabel) { confirmErase = true }
                    .controlSize(.small)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
        .alert(Self.eraseConfirmTitle, isPresented: $confirmErase) {
            Button(Self.eraseConfirm, role: .destructive) { model.eraseAll() }
            Button(Self.consentCancel, role: .cancel) {}
        } message: {
            Text(Self.eraseConfirmMessage)
        }
    }

    private static let sortedDefaults = sortedByName(Exclusions.defaultBundleIDs, name: appName)

    /// Bundle IDs in the order of the names shown for them (case-insensitive), bundle ID breaking ties.
    static func sortedByName(_ bundleIDs: Set<String>, name: (String) -> String) -> [String] {
        bundleIDs.sorted {
            switch name($0).localizedCaseInsensitiveCompare(name($1)) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return $0 < $1
            }
        }
    }

    private func excludedRow(_ bundleID: String, removable: Bool) -> some View {
        HStack(spacing: 6) {
            Text(Self.appName(bundleID)).font(.system(size: 12)).lineLimit(1)
            Text(bundleID)
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
                .lineLimit(1)
                .truncationMode(.middle)
            if !removable {
                Text(Self.defaultTag)
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
            }
            Spacer()
            if removable {
                Button { model.removeExcludedApp(bundleID) } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Bỏ \(Self.appName(bundleID))"))
            }
        }
        .padding(.leading, 8)
    }

    /// The app's name when it is installed, else the last part of its bundle ID.
    static func appName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return knownNames[bundleID] ?? bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    /// Names for the default exclusions when the app is not installed; covers every `Exclusions.defaultBundleIDs` entry.
    static let knownNames = [
        "com.1password.1password": "1Password",
        "com.agilebits.onepassword7": "1Password 7",
        "org.keepassxc.keepassxc": "KeePassXC",
        "com.bitwarden.desktop": "Bitwarden",
        "com.apple.keychainaccess": "Keychain Access",
        "com.apple.Passwords": "Passwords",
        "co.zeit.hyper": "Hyper",
        "com.github.wez.wezterm": "WezTerm",
        "com.googlecode.iterm2": "iTerm2",
        "com.mitchellh.ghostty": "Ghostty",
        "io.alacritty": "Alacritty",
        "org.alacritty": "Alacritty (bản cũ)",
        "net.kovidgoyal.kitty": "kitty",
        "org.tabby": "Tabby",
        "dev.warp.Warp-Stable": "Warp",
        "dev.warp.Warp-Preview": "Warp Preview",
        "com.apple.Terminal": "Terminal",
        "com.lastpass.lastpassmacdesktop": "LastPass",
        "in.sinew.Enpass-Desktop": "Enpass",
        "me.proton.pass.electron": "Proton Pass",
        // Code editors (security audit MEDIUM-4).
        "com.microsoft.VSCode": "Visual Studio Code",
        "com.microsoft.VSCodeInsiders": "VS Code Insiders",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.todesktop.cursor": "Cursor (bản cũ)",
        "com.exafunction.windsurf": "Windsurf",
        "dev.zed.Zed": "Zed",
        "dev.zed.Zed-Preview": "Zed Preview",
        "com.apple.dt.Xcode": "Xcode",
        "com.sublimetext.4": "Sublime Text",
        "com.sublimetext.3": "Sublime Text 3",
        "com.panic.Nova": "Nova",
        "com.barebones.bbedit": "BBEdit",
        "com.google.android.studio": "Android Studio",
    ]

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        model.addExcludedApp(id)
    }
}

/// The explanation shown the first time "Gợi ý gõ tắt" is turned on. Nothing is learned until Bật.
struct LearnConsentView: View {
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LearnSettingsSection.toggleTitle).font(.system(size: 13, weight: .semibold))
            Text(LearnSettingsSection.consentText)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(LearnSettingsSection.consentCancel, action: cancel).keyboardShortcut(.cancelAction)
                Button(LearnSettingsSection.consentConfirm, action: confirm).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

struct LearnSettingsSection_Previews: PreviewProvider {
    static var previews: some View {
        let model = ShortcutSuggestionsModel.preview()
        let page = VStack(spacing: 20) {
            LearnSettingsSection(model: model, part: .general)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
            LearnSettingsSection(model: model, part: .advanced)
        }
        .padding(20)
        .frame(width: 500)
        Group {
            page.preferredColorScheme(.light).previewDisplayName("Sáng")
            page.preferredColorScheme(.dark).previewDisplayName("Tối")
            LearnConsentView(confirm: {}, cancel: {}).previewDisplayName("Đồng ý")
        }
    }
}
