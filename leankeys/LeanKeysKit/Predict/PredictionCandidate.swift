import Foundation

/// What kind of suggestion a `PredictionCandidate` represents in the 4A+ candidate bar.
public enum PredictionKind: Equatable {
    /// A single word or syllable ("ơn", "Chương", "improve").
    case word
    /// A multi-word phrase continuation ("bạn nhiều", "kiểm tra lại").
    case phrase
    /// A full multi-word sentence continuation learned or common ("kiểm tra lại rồi báo anh sau").
    case sentence
    /// An expansion from the user's Gõ Tắt table.
    case shortcut
}

/// One candidate shown in the floating prediction bar (max 3).
public struct PredictionCandidate: Identifiable, Equatable {
    public let id: String
    /// Short label shown in the chip.
    public let display: String
    /// Exact text typed after deleting `deleteCount` characters before the cursor.
    public let insertion: String
    /// Number of UTF-16/Character code units to backspace (`0` after Space, `currentWord.count` mid-word).
    public let deleteCount: Int
    public let kind: PredictionKind
    public let score: Double
    public let isPersonal: Bool

    public init(id: String, display: String, insertion: String, deleteCount: Int,
                kind: PredictionKind, score: Double, isPersonal: Bool = false) {
        self.id = id
        self.display = display
        self.insertion = insertion
        self.deleteCount = deleteCount
        self.kind = kind
        self.score = score
        self.isPersonal = isPersonal
    }
}
