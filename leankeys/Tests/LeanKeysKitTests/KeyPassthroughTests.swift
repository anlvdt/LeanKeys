import ApplicationServices
@testable import LeanKeysKit
import XCTest

final class KeyPassthroughTests: XCTestCase {
    private func field(_ role: String = "AXTextField", subrole: String? = nil, placeholder: String? = nil,
                       description: String? = nil, title: String? = nil, identifier: String? = nil,
                       dom: String? = nil) -> [String: String] {
        var a: [String: String] = [kAXRoleAttribute as String: role]
        a[kAXSubroleAttribute as String] = subrole
        a[kAXPlaceholderValueAttribute as String] = placeholder
        a[kAXDescriptionAttribute as String] = description
        a[kAXTitleAttribute as String] = title
        a[kAXIdentifierAttribute as String] = identifier
        a["AXDOMIdentifier"] = dom
        return a
    }

    func testRemoteAppsPassThrough() {
        for id in ["dev.macviewer.app", "com.teamviewer.TeamViewer", "com.philandro.anydesk", "com.carriez.rustdesk",
                   "com.microsoft.rdc.macos", "tv.parsec.www", "com.vmware.fusion", "com.apple.ScreenSharing"] {
            XCTAssertEqual(KeyPassthrough.reason(bundleID: id, focused: nil), "remote", id)
        }
        XCTAssertNil(KeyPassthrough.reason(bundleID: "com.apple.Notes", focused: nil))
        XCTAssertNil(KeyPassthrough.reason(bundleID: nil, focused: nil))
    }

    func testSecureFieldIsCredential() {
        XCTAssertTrue(KeyPassthrough.isCredentialField(attributes: field(subrole: "AXSecureTextField")))
    }

    func testSignInFieldsAreCredentials() {
        let cases: [[String: String]] = [
            field(placeholder: "Username"),
            field(placeholder: "Email address"),
            field(placeholder: "Mật khẩu"),
            field(description: "Tên đăng nhập"),
            field(title: "Tài khoản"),
            field(identifier: "login-field"),
            field(dom: "user_password"),
            field("AXComboBox", placeholder: "Apple ID"),
            field(placeholder: "Nhập mã OTP"),
            field(placeholder: "Enter PIN"),
        ]
        for a in cases { XCTAssertTrue(KeyPassthrough.isCredentialField(attributes: a), "\(a)") }
    }

    func testOrdinaryFieldsTypeNormally() {
        let cases: [[String: String]] = [
            field(placeholder: "Tìm kiếm"),
            field(placeholder: "Shopping list"),          // "pin" inside a word
            field(placeholder: "Nhập tin nhắn"),
            field(description: "To"),
            field(placeholder: "Opinion"),
            field("AXTextArea", placeholder: "Email body"), // a text area is never a sign-in box
            [:],
        ]
        for a in cases { XCTAssertFalse(KeyPassthrough.isCredentialField(attributes: a), "\(a)") }
    }

    func testWholeWordMatch() {
        XCTAssertTrue(KeyPassthrough.containsWord("enter your pin", "pin"))
        XCTAssertFalse(KeyPassthrough.containsWord("shopping", "pin"))
        XCTAssertTrue(KeyPassthrough.containsWord("user_password", "password"))
        XCTAssertTrue(KeyPassthrough.containsWord("đăng nhập bằng email", "đăng nhập"))
    }
}
