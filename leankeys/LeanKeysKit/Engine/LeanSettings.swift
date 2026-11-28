import Foundation

/// Which engine types Vietnamese.
public enum EngineKind: String {
    case gonhanh, vikey
}

/// LeanKeys' own preferences, kept apart from Gõ Nhanh's under the "LeanKeys." prefix.
public struct LeanSettings {
    public static let engineKey = "LeanKeys.engine"
    public static let autoFixKey = "LeanKeys.autoFix"
    public static let advancedTelexKey = "LeanKeys.advancedTelex"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Vikey unless Gõ Nhanh was picked; nothing stored, or an unknown stored value, reads as Vikey (spec §13).
    public var engine: EngineKind {
        get { defaults.string(forKey: Self.engineKey).flatMap(EngineKind.init(rawValue:)) ?? .vikey }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.engineKey) }
    }

    /// The master switch for every automatic fix (auto switch, restore of a wrong spelling, ⌫ repair of a doubled
    /// key, capitals, stray key at Enter, finishing a word at Return). Nothing stored reads as on. The sub-switches
    /// keep their own values whatever this is.
    public var autoFix: Bool {
        get { defaults.object(forKey: Self.autoFixKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.autoFixKey) }
    }

    /// Laban Key-style initial consonant doubling (`cc→ch`, `gg→gi`, `kk→kh`, `nn→ng`, `pp→ph`, `qq→qu`, `tt→th`).
    /// Off by default so standard Telex users are unaffected.
    public var advancedTelex: Bool {
        get { defaults.object(forKey: Self.advancedTelexKey) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Self.advancedTelexKey) }
    }
}
