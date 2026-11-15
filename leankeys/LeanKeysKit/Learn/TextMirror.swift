import Foundation

/// A word the user just finished, and the character that finished it (Space, `, . ; : ! ?`, "\n" or "\t").
public struct CommittedWord: Equatable {
    public let text: String
    public let breakChar: Character
}

/// A phrase the user just finished with `. ! ?` or Return/Enter, without that terminator and trimmed.
/// A reset (navigation, click, bypass, app switch, Secure Input) ends a phrase by discarding it, never by emitting it.
public struct CommittedPhrase: Equatable {
    public let text: String
}

/// What the user just typed, as both engines report it: their edits (`apply`) and the keys that reach the app by
/// themselves (`typed`). It holds the current phrase only, in memory. Nothing here is logged or stored: keep it so.
/// Single-threaded, like `EngineRouter`.
public final class TextMirror {
    /// Longest phrase emitted. A longer one is dropped whole, never cut.
    public static let phraseLimit = 500

    public var onWord: ((CommittedWord) -> Void)?
    public var onPhrase: ((CommittedPhrase) -> Void)?

    /// Text since the last phrase boundary. Once the phrase overflows, only the current word is kept.
    private var buffer: [Character] = []
    /// Where the current word starts in `buffer`.
    private var wordStart = 0
    /// The phrase grew past `phraseLimit`: drop it at its end.
    private var overflowed = false
    /// An edit deleted more than the mirror holds, so the text left of the cursor is unknown. The current word is
    /// not known to be whole (no `onWord`, empty `currentWord`) until the next break; the phrase is dropped.
    private var wordUnknown = false
    private var phraseUnknown = false

    public init() {}

    /// The word being typed: everything since the last word break. Empty right after a break or a reset.
    public var currentWord: String {
        wordUnknown ? "" : String(buffer[wordStart...])
    }

    /// An engine edit: delete `deleteCount` characters before the cursor, then insert `insert`. Inserted breaks
    /// commit exactly like typed ones.
    public func apply(deleteCount: Int, insert: [Character]) {
        if deleteCount > 0 { delete(deleteCount) }
        for c in insert { typed(c) }
    }

    /// A key that reached the app by itself.
    public func typed(_ c: Character) {
        guard Self.wordBreaks.contains(c) else { append(c); return }
        let word = String(buffer[wordStart...])
        if !wordUnknown, !word.isEmpty { onWord?(CommittedWord(text: word, breakChar: c)) }
        wordUnknown = false
        if Self.phraseEnds.contains(c) {
            if !overflowed, !phraseUnknown {
                let text = String(buffer).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, text.count <= Self.phraseLimit { onPhrase?(CommittedPhrase(text: text)) }
            }
            reset()
        } else if c == "\t" {
            // Tab ends the word (shortcuts expand there) but moves focus in most fields: the phrase is gone.
            reset()
        } else {
            append(c)
            wordStart = buffer.count
        }
    }

    /// Navigation, click, bypass, app switch, Secure Input: forget the word and the phrase, emit nothing.
    public func reset() {
        buffer.removeAll()
        wordStart = 0
        overflowed = false
        wordUnknown = false
        phraseUnknown = false
    }

    private func append(_ c: Character) {
        buffer.append(c)
        guard buffer.count > Self.phraseLimit else { return }
        overflowed = true
        buffer.removeFirst(wordStart)
        wordStart = 0
        // A single "word" this long is no shortcut and no phrase: stop holding it.
        if buffer.count > Self.phraseLimit {
            buffer.removeAll()
            wordUnknown = true
        }
    }

    private func delete(_ count: Int) {
        guard count <= buffer.count else {
            reset()
            wordUnknown = true
            phraseUnknown = true
            return
        }
        buffer.removeLast(count)
        guard wordStart > buffer.count else { return }
        // Deleted back into the previous word, which is current again.
        if let i = buffer.lastIndex(where: { Self.wordBreaks.contains($0) }) {
            wordStart = i + 1
        } else {
            wordStart = 0
            // After an overflow the buffer's start is not the phrase's start: the word may reach further left.
            if overflowed { wordUnknown = true }
        }
    }

    private static let wordBreaks: Set<Character> = [" ", ",", ".", ";", ":", "!", "?", "\n", "\r", "\t"]
    private static let phraseEnds: Set<Character> = [".", "!", "?", "\n", "\r"]
}
