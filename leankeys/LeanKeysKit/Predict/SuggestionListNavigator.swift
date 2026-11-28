import Foundation

/// Keys the 4A+ suggestion list reacts to (no ⌘/⌃/⌥/⇧).
public enum SuggestionListKey: Equatable {
    case down, up, tab, enter, escape
}

/// What the event tap does with a list key.
public enum SuggestionListAction: Equatable {
    /// Not ours: the key goes on as usual, the list stays.
    case pass
    /// The key goes on as usual and the list hides (↑ with nothing selected, a fast Tab, a plain Enter).
    case passAndHide
    /// Swallow the key (the selection moved).
    case swallow
    /// Swallow the key and hide the list.
    case dismiss
    /// Swallow the key and insert row `index`.
    case accept(Int)
}

/// Google Search–style selection over the suggestion list (spec 2026-11-28-prediction-dropdown): ↓ enters the
/// list, ↑/↓ move, Tab or Enter take the selected row. With nothing selected, Tab takes the first row only once the
/// list has stopped changing for `tabSettle`, so a Tab typed in flow stays a Tab. Pure value type: a few compares
/// per key on the event-tap thread.
public struct SuggestionListNavigator: Equatable {
    public static let tabSettle: CFAbsoluteTime = 0.25

    public private(set) var selectedIndex: Int?
    public private(set) var count = 0
    private var changedAt: CFAbsoluteTime = 0

    public init() {}

    /// The shown rows changed (or the list hid with `count` 0): the selection resets.
    public mutating func listChanged(count: Int, at time: CFAbsoluteTime) {
        self.count = count
        changedAt = time
        selectedIndex = nil
    }

    /// Any other key reached the text: typing goes on, the selection resets.
    public mutating func typing() {
        selectedIndex = nil
    }

    public mutating func handle(_ key: SuggestionListKey, now: CFAbsoluteTime) -> SuggestionListAction {
        guard count > 0 else { return .pass }
        switch key {
        case .down:
            selectedIndex = min((selectedIndex ?? -1) + 1, count - 1)
            return .swallow
        case .up:
            guard let sel = selectedIndex else { return .passAndHide }
            selectedIndex = sel == 0 ? nil : sel - 1
            return .swallow
        case .tab:
            if let sel = selectedIndex { return .accept(sel) }
            return now - changedAt >= Self.tabSettle ? .accept(0) : .passAndHide
        case .enter:
            if let sel = selectedIndex { return .accept(sel) }
            return .passAndHide
        case .escape:
            selectedIndex = nil
            return .dismiss
        }
    }
}
