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
}
