import XCTest
@testable import LeanKeysKit

/// Where Return may finish the word being typed (Vikey D62 stays in single-line fields: address bars, search boxes).
final class FocusedFieldTests: XCTestCase {
    func testMultiLineFieldWithoutSelectionAllows() {
        XCTAssertTrue(FocusedField.allowsFixAtReturn(role: "AXTextArea", selectionLength: 0))
    }

    func testSingleLineFieldsKeepD62() {
        for role in ["AXTextField", "AXComboBox", "AXSearchField"] {
            XCTAssertFalse(FocusedField.allowsFixAtReturn(role: role, selectionLength: 0), role)
        }
    }

    /// An inline completion is a selection after the cursor: Return must send it untouched.
    func testSelectionKeepsD62() {
        XCTAssertFalse(FocusedField.allowsFixAtReturn(role: "AXTextArea", selectionLength: 7))
    }

    /// Accessibility gave no answer (busy app, web area without a role, no permission): keep D62.
    func testUnknownKeepsD62() {
        XCTAssertFalse(FocusedField.allowsFixAtReturn(role: nil, selectionLength: 0))
        XCTAssertFalse(FocusedField.allowsFixAtReturn(role: "AXTextArea", selectionLength: nil))
        XCTAssertFalse(FocusedField.allowsFixAtReturn(role: "AXWebArea", selectionLength: 0))
    }
}
