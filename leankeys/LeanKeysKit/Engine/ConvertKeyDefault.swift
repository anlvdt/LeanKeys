import Foundation

/// The convert key (⌃⌫) is the restore shortcut's slot under Vikey. A user who never set one gets ⌃⌫, once.
public enum ConvertKeyDefault {
    private static let appliedFlag = "leankeys.convertKeyDefaultApplied"

    /// Once: when no shortcut is stored and the restore shortcut is off, stores ⌃⌫ (keyCode 51, Control = 262144)
    /// and turns it on. Returns whether it wrote.
    public static func apply(_ defaults: UserDefaults, shortcutKey: String, enabledKey: String) -> Bool {
        guard !defaults.bool(forKey: appliedFlag) else { return false }
        defaults.set(true, forKey: appliedFlag)
        guard defaults.data(forKey: shortcutKey) == nil, !defaults.bool(forKey: enabledKey) else { return false }
        guard let data = #"{"keyCode":51,"modifiers":262144}"#.data(using: .utf8) else { return false }
        defaults.set(data, forKey: shortcutKey)
        defaults.set(true, forKey: enabledKey)
        return true
    }
}
