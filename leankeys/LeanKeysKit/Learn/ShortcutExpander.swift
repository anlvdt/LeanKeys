import Foundation

/// The user's gõ tắt (text shortcuts) for the Vikey engine; Gõ Nhanh's own engine keeps its copy in Rust
/// (core/src/engine/shortcut.rs), and this follows its rules. A trigger matches a whole word, ignoring case. The
/// result takes the word's case: all capitals give an all-capitals result ("VN" → "VIỆT NAM"), a capital first
/// letter capitalises the result ("Vn" → "Việt Nam"), anything else gives the replacement as stored.
public struct ShortcutExpander {
    /// Lowercased trigger → replacement. A later duplicate replaces an earlier one, as in Gõ Nhanh.
    private var table: [String: String] = [:]

    public init(_ items: [(trigger: String, replacement: String)] = []) {
        for (trigger, replacement) in items where !trigger.isEmpty && !replacement.isEmpty {
            table[trigger.lowercased()] = replacement
        }
    }

    public var isEmpty: Bool { table.isEmpty }

    /// The replacement for `word`, cased like it; nil when `word` is no trigger.
    public func expand(word: String) -> String? {
        guard !word.isEmpty, let replacement = table[word.lowercased()] else { return nil }
        if word.allSatisfy(\.isUppercase) { return replacement.uppercased() }
        if let first = word.first, first.isUppercase, let head = replacement.first {
            return head.uppercased() + replacement.dropFirst()
        }
        return replacement
    }
}
