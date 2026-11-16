/// Which cards of Gõ Nhanh's `SettingsPageView` one LeanKeys settings page shows.
public enum SettingsPart {
    case general
    case shortcuts
}

/// Rules for the minimal General page (spec §14.3).
public enum SettingsLayout {
    /// The Gõ Nhanh-only rows (Gõ W thành Ư, Gõ [ ] thành Ơ Ư, Tự khôi phục tiếng Anh, Tự viết hoa đầu câu, and on
    /// Phím tắt "Trả từ đang gõ về phím gốc": Vikey takes Esc as a word break and has no restore) show only while Gõ Nhanh is the engine typing, so no visible row does nothing.
    public static func showsGoNhanhOnlySettings(active: EngineKind) -> Bool {
        active == .gonhanh
    }

    /// Gõ Nhanh's "Hiển thị cài đặt nâng cao" toggle is hidden: the Nâng cao page is always in the sidebar.
    public static let showsAdvancedModeToggle = false
}
