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
    private var phraseObservers: [(CommittedPhrase) -> Void] = []

    /// Registers an additional listener for committed phrases without overwriting `onPhrase` (used by 4A+ prediction
    /// alongside 4B shortcut suggestions).
    public func addPhraseObserver(_ observer: @escaping (CommittedPhrase) -> Void) {
        phraseObservers.append(observer)
    }

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
    /// What was typed on the current line, as on screen: since the last newline, or since the line's start became
    /// unknown (before the first newline, after a cursor move or a bypass, a delete past what is held, an overflow).
    /// Sentence ends, which end the phrase, keep it.
    private var line: [Character] = []
    /// `line` starts at the line's start.
    private var lineStartIsKnown = false

    /// Longest line held; past it the oldest half is dropped and the line's start becomes unknown.
    static let lineLimit = 2_000

    public init() {}

    /// The current line before the cursor, as on screen; nil when its start is unknown (see `typedTail`).
    public var lineBeforeCursor: String? {
        lineStartIsKnown ? String(line) : nil
    }

    /// `typedTail` starts at the line's start (`lineBeforeCursor != nil`), without building the line.
    public var lineStartKnown: Bool { lineStartIsKnown }

    /// The end of the current line that the mirror saw typed, as on screen: the whole line when its start is known,
    /// else what was typed since the cursor last moved (empty right after). Spec 17.2 reads it.
    public var typedTail: String {
        String(line)
    }

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

    /// The current phrase's words before the cursor, oldest first, ending with the word being typed: runs of
    /// letters and digits, punctuation dropped. Empty while the word being typed is unknown.
    public var phraseWords: [String] {
        phraseText.map { Self.words(in: $0) } ?? []
    }

    /// Completed words in the current phrase strictly before the word currently being typed (`currentWord`).
    /// Immediately after typing Space, `currentWord` is empty and this returns all preceding words in the phrase;
    /// mid-word, this drops the partial word being typed. Returns empty when the word boundary is unknown.
    public var recentWordsBeforeCurrent: [String] {
        guard !wordUnknown else { return [] }
        let before = String(buffer[..<wordStart])
        return Self.words(in: before)
    }

    /// The word being typed is the phrase's first, as far as the mirror knows. Also true when what comes before it
    /// is unknown (after an overflow or an edit past the mirror's start), so a caller that skips phrase-initial words
    /// skips those too.
    public var atPhraseStart: Bool {
        if overflowed || phraseUnknown || wordUnknown { return true }
        guard pendingTerminator == nil else { return false }
        return !buffer[..<wordStart].contains(where: Self.isWordCharacter)
    }

    /// The current phrase's text before the cursor, as on screen; nil while the word being typed is unknown. A
    /// pending `. ! ?` is left out: it joins the phrase only if a character other than Space or Return follows.
    var phraseText: String? {
        wordUnknown ? nil : String(buffer)
    }

    /// Runs of letters and digits in `text`, oldest first.
    static func words(in text: String) -> [String] {
        text.split(whereSeparator: { !isWordCharacter($0) }).map(String.init)
    }

    static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber
    }

    /// An engine edit: delete `deleteCount` characters before the cursor, then insert `insert`. Inserted breaks
    /// commit exactly like typed ones.
    public func apply(deleteCount: Int, insert: [Character]) {
        if deleteCount > 0 {
            if deleteCount <= line.count {
                line.removeLast(deleteCount)
            } else {
                forgetLine()
            }
        }
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
        trackLine(c)
        if let pending = pendingTerminator {
            pendingTerminator = nil
            if Self.closesPending.contains(c) {
                emitPhrase()
                clearPhrase()
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
            clearPhrase()
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
    /// frontmost app changing): forget the word, the phrase and the line, emit nothing. An app switch discards
    /// (ruling R20): by the time it is seen the phrase would be credited to the new app, past its exclusion and
    /// secure-field checks.
    public func discard() {
        clearPhrase()
        forgetLine()
    }

    private func forgetLine() {
        line.removeAll()
        lineStartIsKnown = false
    }

    /// Ends the phrase on the same line: the line stays known.
    private func clearPhrase() {
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
        if !text.isEmpty, text.count <= Self.phraseLimit {
            let phrase = CommittedPhrase(text: text)
            onPhrase?(phrase)
            for observer in phraseObservers { observer(phrase) }
        }
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
            clearPhrase()
            wordUnknown = true
            phraseUnknown = true
            return
        }
        buffer.removeLast(count)
        // Deleted back into the previous word, which is current again.
        if wordStart > buffer.count { findWordStart() }
    }

    /// `line` after `c` reaches the screen. Tab is a cursor move: `typed` resets, which forgets the line.
    private func trackLine(_ c: Character) {
        if c == "\n" || c == "\r" {
            line.removeAll()
            lineStartIsKnown = true
        } else {
            line.append(c)
            if line.count > Self.lineLimit {
                line.removeFirst(line.count / 2)
                lineStartIsKnown = false
            }
        }
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
