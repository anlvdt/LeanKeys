import AppKit
import LeanKeysKit // LEANKEYS-HOOK: settings-engine
import SwiftUI

// MARK: - Advanced Settings View

struct AdvancedSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var showAddApp = false
    @State private var logEnabled = DebugLog.isOnAfterExpiry() // LEANKEYS-HOOK: debug-log

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                EngineSettingsSection(onEngineChanged: { RustBridge.clearBuffer() }) // LEANKEYS-HOOK: settings-engine (first, spec §14.3)
                LearnSettingsSection(model: .shared, part: .advanced) // LEANKEYS-HOOK: settings-engine (LeanKeys cards first)
                UndoLearningSection(model: .shared, autoFixOff: !appState.autoFix) // LEANKEYS-HOOK: auto-fix
                TerminalVietnameseSection(onChange: { clearDetectionCache() }) // LEANKEYS-HOOK: settings-engine (terminal Vietnamese card)
                perAppSection // LEANKEYS-HOOK: copy (rare and technical sections last)
                performanceSection // LEANKEYS-HOOK: copy
                compatibilitySection // LEANKEYS-HOOK: copy
                logSection // LEANKEYS-HOOK: copy
                Spacer()
            }
        }
    }

    // MARK: - Performance

    private var performanceSection: some View {
        VStack(spacing: 0) {
            SettingsToggleRow(
                "Không theo dõi ô tìm kiếm Spotlight/Raycast", // LEANKEYS-HOOK: copy
                subtitle: "Tiết kiệm CPU và bộ nhớ; gõ trong các ô đó có thể kém ổn định hơn", // LEANKEYS-HOOK: copy
                isOn: $appState.disablePanelDetection
            )
            Divider().padding(.horizontal, 14)
            SettingsToggleRow(
                "Mở lại LeanKeys khi đóng Cài đặt", // LEANKEYS-HOOK: copy
                subtitle: "Giải phóng bộ nhớ mà cửa sổ Cài đặt đã dùng", // LEANKEYS-HOOK: copy
                isOn: $appState.restartOnClose
            )
        }
        .cardBackground()
    }

    // MARK: - Compatibility

    private var compatibilitySection: some View {
        VStack(spacing: 0) {
            SettingsToggleRow(
                "Chế độ điều khiển từ xa", // LEANKEYS-HOOK: copy
                subtitle: "Khi điều khiển máy Mac này từ máy khác (RustDesk, AnyDesk…)", // LEANKEYS-HOOK: copy
                isOn: $appState.sessionTapMode
            )
            .help("Dùng khi điều khiển từ xa bằng RustDesk, AnyDesk, TeamViewer. Nhận phím ở tầng phiên (session) thay vì tầng thiết bị (HID). Bàn phím Trợ năng đã được hỗ trợ sẵn.") // LEANKEYS-HOOK: copy
        }
        .cardBackground()
    }

    // MARK: - Log

    private var logSection: some View {
        VStack(spacing: 0) {
            SettingsRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nhật ký gỡ lỗi").font(.system(size: 13, weight: .medium)) // LEANKEYS-HOOK: copy
                    Text(DebugLog.settingsSubtitle) // LEANKEYS-HOOK: debug-log
                        .font(.system(size: 11))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                        .lineLimit(1).help("Ghi cách xử lý phím vào ~/Library/Logs/LeanKeys/debug.log. " + DebugLog.settingsSubtitle + ".") // LEANKEYS-HOOK: debug-log
                }
                Spacer()
                LogToggleButton(isEnabled: $logEnabled)
            }
            if logEnabled {
                Divider().padding(.leading, 12)
                LogViewerSection()
            }
        }
        .cardBackground()
    }

    // MARK: - Per-App Profiles

    private var perAppSection: some View {
        VStack(spacing: 0) {
            SettingsRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tuỳ chỉnh theo ứng dụng").font(.system(size: 13, weight: .medium))
                    Text("Tuỳ chỉnh cách \(AppMetadata.name) gõ trong từng ứng dụng") // LEANKEYS-HOOK: copy
                        .font(.system(size: 11))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                }
                Spacer()
                Button(action: { showAddApp = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Thêm ứng dụng").accessibilityLabel(Text("Thêm ứng dụng")) // LEANKEYS-HOOK: copy
            }

            ForEach(sortedProfiles, id: \.key) { entry in
                Divider().padding(.leading, 12)
                PerAppProfileRow(
                    bundleId: entry.key,
                    config: entry.value,
                    onChange: { appState.perAppProfiles[entry.key] = $0 },
                    onRemove: { appState.perAppProfiles.removeValue(forKey: entry.key) }
                )
            }
        }
        .cardBackground()
        .sheet(isPresented: $showAddApp) {
            AppPickerSheet(existingBundleIds: Set(appState.perAppProfiles.keys)) { bundleId in
                appState.perAppProfiles[bundleId] = PerAppConfig.fromDetected(bundleId: bundleId)
            }
        }
    }

    private var sortedProfiles: [(key: String, value: PerAppConfig)] {
        appState.perAppProfiles.sorted { $0.key < $1.key }
    }
}

// MARK: - Per-App Profile Row

struct PerAppProfileRow: View {
    let bundleId: String
    let config: PerAppConfig
    let onChange: (PerAppConfig) -> Void
    let onRemove: () -> Void
    @State private var removeHovered = false
    @State private var resetHovered = false

    private let labelWidth: CGFloat = 48
    private let labelColor = Color(NSColor.secondaryLabelColor) // LEANKEYS-HOOK: copy (4.5:1 contrast, spec §14.3)
    private let labelFont = Font.system(size: 11) // LEANKEYS-HOOK: copy

    var body: some View {
        VStack(spacing: 10) {
            // Header
            HStack(spacing: 8) {
                AppIconView(bundleId: bundleId)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(appName).font(.system(size: 12, weight: .medium))
                        if let hint = detectedHint {
                            Text(hint)
                                .font(.system(size: 11)) // LEANKEYS-HOOK: copy
                                .foregroundColor(labelColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(labelColor.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(bundleId)
                        .font(.system(size: 11, design: .monospaced)) // LEANKEYS-HOOK: copy
                        .foregroundColor(labelColor)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button(action: { onChange(PerAppConfig.fromDetected(bundleId: bundleId)) }) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(resetHovered ? .accentColor : Color(NSColor.quaternaryLabelColor))
                }
                .buttonStyle(.plain).onHover { resetHovered = $0 }
                .help("Đặt lại mặc định").accessibilityLabel(Text("Đặt lại mặc định cho \(appName)")) // LEANKEYS-HOOK: copy
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(removeHovered ? .red : Color(NSColor.quaternaryLabelColor))
                }
                .buttonStyle(.plain).onHover { removeHovered = $0 }
                .help("Bỏ tuỳ chỉnh cho ứng dụng này").accessibilityLabel(Text("Bỏ tuỳ chỉnh cho \(appName)")) // LEANKEYS-HOOK: copy
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            // Delay
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Độ trễ").font(labelFont).foregroundColor(labelColor) // LEANKEYS-HOOK: copy
                        .frame(width: labelWidth, alignment: .leading)
                    Slider(value: delaySliderBinding, in: 0 ... Double(DelayPreset.allCases.count - 1), step: 1)
                    Text(delayPresetName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(delayPresetColor)
                        .frame(width: 52, alignment: .trailing)
                }
                Text("Tăng nếu bị mất chữ · Giảm nếu ứng dụng phản hồi nhanh") // LEANKEYS-HOOK: copy
                    .font(.system(size: 11)) // LEANKEYS-HOOK: copy
                    .foregroundColor(Color(NSColor.secondaryLabelColor)) // LEANKEYS-HOOK: copy
                    .padding(.leading, labelWidth + 6)
            }
            .padding(.horizontal, 14)

            // GN · Inject
            HStack(spacing: 8) {
                profilePicker("Tiếng Việt", selection: enabledBinding, width: 140) { // LEANKEYS-HOOK: copy
                    Text("Mặc định").tag(0) // LEANKEYS-HOOK: copy
                    Text("Luôn bật").tag(1) // LEANKEYS-HOOK: copy
                    Text("Luôn tắt").tag(-1) // LEANKEYS-HOOK: copy
                }
                profilePicker("Cách gửi phím", selection: injectionBinding, width: 120) { // LEANKEYS-HOOK: copy
                    ForEach(InjectionOverride.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 12)
    }

    private func profilePicker(_ label: String, selection: Binding<some Hashable>, width: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 4) {
            Text(label).font(labelFont).foregroundColor(labelColor)
                .lineLimit(1).fixedSize()
            Picker(label, selection: selection, content: content) // LEANKEYS-HOOK: copy (VoiceOver name)
                .labelsHidden().frame(width: width)
        }
    }

    // MARK: - Helpers

    private var enabledBinding: Binding<Int> {
        Binding(
            get: { config.enabledState },
            set: { v in var c = config; c.enabledState = v; onChange(c) }
        )
    }

    private var injectionBinding: Binding<Int> {
        Binding(
            get: { config.injectionOverride },
            set: { v in var c = config; c.injectionOverride = v; onChange(c) }
        )
    }

    private var delaySliderBinding: Binding<Double> {
        Binding(
            get: { Double(config.delayPreset) },
            set: { val in var c = config; c.delayPreset = Int(val.rounded()); onChange(c) }
        )
    }

    private var delayPresetName: String {
        (DelayPreset(rawValue: config.delayPreset) ?? .none).name
    }

    private var delayPresetColor: Color {
        (DelayPreset(rawValue: config.delayPreset) ?? .none).color
    }

    /// Show detected default injection method as badge (e.g. "fast", "slow")
    private var detectedHint: String? {
        getDetectedDefault(for: bundleId).map { InjectionOverride.from(detectedMethod: $0.method).name } // LEANKEYS-HOOK: copy (not raw "fast"/"slow")
    }

    private var appName: String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleId })?
            .localizedName ?? bundleId.components(separatedBy: ".").last ?? bundleId
    }
}
