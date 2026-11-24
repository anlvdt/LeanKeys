/// What an engine wants done to the text before the cursor: delete `deleteCount` characters, then insert `text`.
public struct EngineEdit: Equatable {
    public let deleteCount: Int
    public let text: [Character]
    public let languageChanged: Bool
    /// The key itself still has to be typed after the edit (its own character is not in `text`).
    public let keyPassesThrough: Bool

    public init(deleteCount: Int, text: [Character], languageChanged: Bool, keyPassesThrough: Bool = false) {
        self.deleteCount = deleteCount
        self.text = text
        self.languageChanged = languageChanged
        self.keyPassesThrough = keyPassesThrough
    }
}

/// A Vietnamese typing engine the key handler can drive.
public protocol TypingEngine: AnyObject {
    /// nil = let the key through unchanged.
    func process(keyCode: UInt16, caps: Bool, shift: Bool) -> EngineEdit?
    func resetContext()
    func setVietnamese(_ on: Bool)
    var isVietnamese: Bool { get }
    /// Switching between Vietnamese and English by itself while typing (on by default).
    func setAutoSwitch(_ on: Bool)
    /// Modern tone placement ("hoà") rather than classic ("hòa"); on by default.
    func setModernTone(_ on: Bool)
    /// The next key, when it is Return/Enter, may finish the word being typed as Space would. Off by default.
    func allowFixAtNextReturn()
    /// Pure Telex: no automatic fix at all (no auto switch, no restore of a wrong spelling, no ⌫ repair of a doubled
    /// key). Off by default; engines without such fixes ignore it.
    func setPureTelex(_ on: Bool)
}

public extension TypingEngine {
    func allowFixAtNextReturn() {}
    func setPureTelex(_ on: Bool) {}
}
