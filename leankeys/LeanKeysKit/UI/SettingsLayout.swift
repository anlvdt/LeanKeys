/// Which cards of Gõ Nhanh's `SettingsPageView` one LeanKeys settings page shows.
public enum SettingsPart {
    case general
    case shortcuts
}

/// Rules for the minimal General page (spec §14.3).
public enum SettingsLayout {
    /// The Gõ Nhanh-only rows (Gõ W thành Ư, Gõ [ ] thành Ơ Ư, Tự khôi phục tiếng Anh, Tự viết hoa đầu câu) show only
    /// while Gõ Nhanh is the engine typing, so no visible row does nothing. The restore shortcut row is not among them
    /// any more: under Vikey it is the convert key (`showsRestoreShortcut`).
    public static func showsGoNhanhOnlySettings(active: EngineKind) -> Bool {
        active == .gonhanh
    }

    /// The restore shortcut row shows under both engines: Gõ Nhanh restores the word being typed, Vikey converts the
    /// last word (design 5.2).
    public static func showsRestoreShortcut(active: EngineKind) -> Bool { true }

    /// Whether pressing Control (flagsChanged) resets the typing context. Not under Vikey when the restore shortcut
    /// is on and uses Control (the default ⌃⌫): the shim must still hold the word when ⌫ arrives; the reset happens
    /// where the chord completes (design 8.3, ruling 9). `restoreModifiers` is a CGEventFlags raw value.
    public static func resetsOnControlPress(active: EngineKind, restoreEnabled: Bool, restoreModifiers: UInt64) -> Bool {
        !(active == .vikey && restoreEnabled && restoreModifiers & controlMask != 0)
    }

    private static let controlMask: UInt64 = 0x40000   // CGEventFlags.maskControl

    public static func restoreRowTitle(active: EngineKind) -> String {
        active == .vikey ? "Đổi từ vừa gõ Việt ⇄ Anh" : "Trả từ đang gõ về phím gốc"
    }

    public static func restoreRowSubtitle(active: EngineKind) -> String {
        active == .vikey ? "Bấm ngay sau một từ: cos → có, bể → beer" : "Ví dụ: việt → vieejt · Bấm để đổi phím tắt"
    }

    /// Gõ Nhanh's "Hiển thị cài đặt nâng cao" toggle is hidden: the Nâng cao page is always in the sidebar.
    public static let showsAdvancedModeToggle = false

    /// Whether Gõ Nhanh's Nâng cao settings take effect (per-app profiles, "Mở lại LeanKeys khi đóng Cài đặt",
    /// "Không theo dõi ô tìm kiếm Spotlight/Raycast"). Gõ Nhanh applies them only in its advanced mode, whose switch
    /// LeanKeys hides while always showing the page, so with the switch hidden they always apply: a shown setting
    /// must work (copy audit I2).
    public static func advancedSettingsApply(advancedMode: Bool) -> Bool {
        advancedMode || !showsAdvancedModeToggle
    }
}
