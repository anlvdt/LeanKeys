import Foundation

/// A word the user just finished, and the character that finished it (Space, `, . ; : ! ?`, "\n" or "\t").
public struct CommittedWord: Equatable {
    public let text: String
    public let breakChar: Character
}

/// A phrase the user just finished, trimmed and without its terminator. It ends at `. ! ?` followed by Space,
/// Return/Enter or a cursor move; at Return/Enter; or at a cursor move (`reset`: click, arrows, Home/End,
/// Page Up/Down, Esc, Tab). Bypass, Secure Input and app switch (`discard`) drop it instead.
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
    /// A `. ! ?` just typed. It ends the word at once, but the phrase only if Space, Return/Enter or a reset comes
    /// next; any other character puts it back inside the phrase ("an@vidu.vn", "3.5", "0912.345.678").
    private var pendingTerminator: Character?
    /// An edit deleted more than the mirror holds, so the text left of the cursor is unknown. The current word is
    /// not known to be whole (no `onWord`, empty `currentWord`) until the next break; the phrase is dropped.
    private var wordUnknown = false
    private var phraseUnknown = false

    public init() {}

    /// The word being typed: everything since the last word break. Empty right after a break or a reset.
    public var currentWord: String {
        wordUnknown ? "" : String(buffer[wordStart...])
    }

    /// The current word comes straight after a break other than whitespace (`gov.vn`, `a,vn`, `an@vidu.vn`), or
    /// what comes before it is unknown (after an overflow). Shortcuts expand only when this is false, as in Gõ Nhanh,
    /// which matches ".vn" there, not "vn".
    public var currentWordFollowsBreak: Bool {
        guard wordStart > 0 else { return overflowed }
        let before = buffer[wordStart - 1]
        return !(before == " " || before == "\n" || before == "\r" || before == "\t")
    }

    /// An engine edit: delete `deleteCount` characters before the cursor, then insert `insert`. Inserted breaks
    /// commit exactly like typed ones.
    public func apply(deleteCount: Int, insert: [Character]) {
        var deleteCount = deleteCount
        if deleteCount > 0, pendingTerminator != nil {
            // The pending terminator is the last character on screen: the word before it is current again.
            pendingTerminator = nil
            deleteCount -= 1
            findWordStart()
        }
        if deleteCount > 0 { delete(deleteCount) }
        for c in insert { typed(c) }
    }

    /// A key that reached the app by itself.
    public func typed(_ c: Character) {
        if let pending = pendingTerminator {
            pendingTerminator = nil
            if Self.closesPending.contains(c) {
                emitPhrase()
                discard()
                return
            }
            append(pending)
            wordStart = buffer.count
        }
        guard Self.wordBreaks.contains(c) else { append(c); return }
        let word = String(buffer[wordStart...])
        if !wordUnknown, !word.isEmpty { onWord?(CommittedWord(text: word, breakChar: c)) }
        wordUnknown = false
        if Self.sentenceEnds.contains(c) {
            pendingTerminator = c
            wordStart = buffer.count
        } else if c == "\n" || c == "\r" {
            emitPhrase()
            discard()
        } else if c == "\t" {
            // Tab ends the word (shortcuts expand there) and moves focus in most fields: a cursor move.
            reset()
        } else {
            append(c)
            wordStart = buffer.count
        }
    }

    /// The cursor moved inside the app (click, arrows, Home/End, Page Up/Down, Esc, Tab): the pending phrase, with
    /// the word being typed, is finished and emitted. No `onWord`: no break key was typed.
    public func reset() {
        emitPhrase()
        discard()
    }

    /// Bypass, Secure Input and app switch (Cmd/Ctrl chords, Option+Backspace, restore shortcut, unknown keys, the
    /// frontmost app changing): forget the word and the phrase, emit nothing. An app switch discards (ruling R20):
    /// by the time it is seen the phrase would be credited to the new app, past its exclusion and secure-field checks.
    public func discard() {
        buffer.removeAll()
        wordStart = 0
        overflowed = false
        pendingTerminator = nil
        wordUnknown = false
        phraseUnknown = false
    }

    private func emitPhrase() {
        guard !overflowed, !phraseUnknown else { return }
        var text = String(buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        // "Hả?!": the last terminator was pending, the ones before it went into the buffer.
        while let last = text.last, Self.sentenceEnds.contains(last) { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, text.count <= Self.phraseLimit { onPhrase?(CommittedPhrase(text: text)) }
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
            discard()
            wordUnknown = true
            phraseUnknown = true
            return
        }
        buffer.removeLast(count)
        // Deleted back into the previous word, which is current again.
        if wordStart > buffer.count { findWordStart() }
    }

    private func findWordStart() {
        if let i = buffer.lastIndex(where: { Self.wordBreaks.contains($0) }) {
            wordStart = i + 1
        } else {
            wordStart = 0
            // After an overflow the buffer's start is not the phrase's start: the word may reach further left.
            if overflowed { wordUnknown = true }
        }
    }

    private static let wordBreaks: Set<Character> = [" ", ",", ".", ";", ":", "!", "?", "\n", "\r", "\t"]
    private static let sentenceEnds: Set<Character> = [".", "!", "?"]
    /// What turns a pending `. ! ?` into the end of the phrase (a reset does too).
    private static let closesPending: Set<Character> = [" ", "\n", "\r"]
}
