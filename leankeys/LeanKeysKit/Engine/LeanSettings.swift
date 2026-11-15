import Foundation

/// Which engine types Vietnamese.
public enum EngineKind: String {
    case gonhanh, vikey
}

/// LeanKeys' own preferences, kept apart from Gõ Nhanh's under the "LeanKeys." prefix.
public struct LeanSettings {
    public static let engineKey = "LeanKeys.engine"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Vikey unless Gõ Nhanh was picked; nothing stored, or an unknown stored value, reads as Vikey (spec §13).
    public var engine: EngineKind {
        get { defaults.string(forKey: Self.engineKey).flatMap(EngineKind.init(rawValue:)) ?? .vikey }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.engineKey) }
    }
}
