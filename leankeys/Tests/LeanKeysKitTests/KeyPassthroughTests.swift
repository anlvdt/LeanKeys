import ApplicationServices
@testable import LeanKeysKit
import XCTest

final class KeyPassthroughTests: XCTestCase {
    private func field(_ role: String = "AXTextField", subrole: String? = nil, placeholder: String? = nil,
                       description: String? = nil, title: String? = nil, identifier: String? = nil,
                       dom: String? = nil, help: String? = nil, label: String? = nil) -> [String: String] {
        var a: [String: String] = [kAXRoleAttribute as String: role]
        a[kAXSubroleAttribute as String] = subrole
        a[kAXPlaceholderValueAttribute as String] = placeholder
        a[kAXDescriptionAttribute as String] = description
        a[kAXTitleAttribute as String] = title
        a[kAXIdentifierAttribute as String] = identifier
        a["AXDOMIdentifier"] = dom
        a[kAXHelpAttribute as String] = help
        a[KeyPassthrough.titleLabelKey] = label
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

    // Terminals (ruling R22) pass every key through unless the user chose Vietnamese for that terminal.

    private func terminalDefaults(_ chosen: [String]) -> UserDefaults {
        let suite = "KeyPassthroughTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        for id in chosen { KeyPassthrough.setVietnamese(true, terminal: id, defaults: defaults) }
        return defaults
    }

    func testChosenTerminalTypesNormally() {
        let defaults = terminalDefaults(["com.mitchellh.ghostty"])
        XCTAssertNil(KeyPassthrough.reason(bundleID: "com.mitchellh.ghostty", focused: nil, defaults: defaults))
        KeyPassthrough.setVietnamese(false, terminal: "com.mitchellh.ghostty", defaults: defaults)
        XCTAssertEqual(KeyPassthrough.reason(bundleID: "com.mitchellh.ghostty", focused: nil, defaults: defaults),
                       "terminal", "turned off again")
    }

    func testOtherTerminalsStillPassThrough() {
        let defaults = terminalDefaults(["com.mitchellh.ghostty"])
        XCTAssertEqual(KeyPassthrough.reason(bundleID: "com.apple.Terminal", focused: nil, defaults: defaults), "terminal")
        XCTAssertEqual(KeyPassthrough.reason(bundleID: "com.apple.Terminal", focused: nil,
                                             defaults: terminalDefaults([])), "terminal", "nothing chosen: R22")
    }

    func testNonTerminalInListIgnored() {
        let defaults = terminalDefaults(["com.apple.TextEdit", "com.apple.Terminal"])
        XCTAssertEqual(KeyPassthrough.vietnameseTerminals(defaults: defaults), ["com.apple.Terminal"])
        XCTAssertNil(KeyPassthrough.reason(bundleID: "com.apple.TextEdit", focused: nil, defaults: defaults))
        XCTAssertEqual(KeyPassthrough.reason(bundleID: "com.teamviewer.TeamViewer", focused: nil, defaults: defaults),
                       "remote")
    }

    func testChosenTerminalStillExcludedFromLearning() {
        _ = terminalDefaults(["com.mitchellh.ghostty"])
        XCTAssertTrue(Exclusions.isExcludedByDefault("com.mitchellh.ghostty"))
        XCTAssertTrue(CodeApps.contains("com.mitchellh.ghostty"), "no capitals, no Return fix, no stray-Enter filter")
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

    // MARK: Security audit MEDIUM-2

    func testCamelCaseAndConcatenatedIdentifiersAreCredentials() {
        let cases: [[String: String]] = [
            field(identifier: "txtPassword"),
            field(dom: "passwordInput"),
            field(identifier: "loginEmail"),
            field(dom: "userPin"),
            field(identifier: "otpCode"),
            field(dom: "identifierId"),              // Google's sign-in box
            field(identifier: "userpassword"),
            field(dom: "useremail"),
            field(identifier: "txt.Username"),
        ]
        for a in cases { XCTAssertTrue(KeyPassthrough.isCredentialField(attributes: a), "\(a)") }
    }

    func testMoreWordsAreCredentials() {
        let labels = ["Tên người dùng", "Ten nguoi dung", "Mã xác thực", "Xác thực", "Mã xác minh", "Mã bảo mật",
                      "Mật mã", "Mã kích hoạt", "Verification code", "Verify", "Security code", "2FA", "Authenticator",
                      "Token", "Passphrase", "Secret", "CVV", "CVC", "Số điện thoại", "So dien thoai", "SĐT", "SDT",
                      "Phone", "Mobile number"]
        for label in labels {
            XCTAssertTrue(KeyPassthrough.isCredentialField(attributes: field(placeholder: label)), label)
        }
    }

    func testDecomposedLabelMatches() {
        let nfd = "Mật khẩu".decomposedStringWithCanonicalMapping
        XCTAssertTrue(KeyPassthrough.isCredentialField(attributes: field(placeholder: nfd)))
    }

    func testHelpAndLinkedLabelAreRead() {
        XCTAssertTrue(KeyPassthrough.isCredentialField(attributes: field(help: "Enter your password")))
        XCTAssertTrue(KeyPassthrough.isCredentialField(attributes: field(label: "Tên người dùng:")))
        XCTAssertFalse(KeyPassthrough.isCredentialField(attributes: field(label: "Ghi chú")))
    }

    func testOrdinaryIdentifiersTypeNormally() {
        let cases: [[String: String]] = [
            field(identifier: "shippingAddress"),     // "pin" only inside a word
            field(dom: "searchField"),
            field(identifier: "messageInput"),
            field(dom: "hotpotMenu"),                 // "otp" only inside a word
            field(placeholder: "Tokenize text"),
            field(identifier: "composeBody"),
        ]
        for a in cases { XCTAssertFalse(KeyPassthrough.isCredentialField(attributes: a), "\(a)") }
    }

    func testLearningSkipsCredentialFieldsAndUnreadableOnes() {
        XCTAssertTrue(LearnContextReader.isExcludedField(attributes: nil))      // timeout or AX error
        XCTAssertTrue(LearnContextReader.isExcludedField(attributes: field(subrole: "AXSecureTextField")))
        XCTAssertTrue(LearnContextReader.isExcludedField(attributes: field(placeholder: "Email")))
        XCTAssertTrue(LearnContextReader.isExcludedField(attributes: field(placeholder: "Số điện thoại")))
        XCTAssertFalse(LearnContextReader.isExcludedField(attributes: field(placeholder: "Nhập tin nhắn")))
        XCTAssertFalse(LearnContextReader.isExcludedField(attributes: [:]))     // no attributes: an ordinary element
    }

    // MARK: Security audit MEDIUM-3

    func testPasswordManagersAndAuthorizationDialogsPassThrough() {
        for id in ["com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
                   "com.apple.keychainaccess", "com.apple.Passwords", "org.keepassxc.keepassxc",
                   "in.sinew.Enpass-Desktop", "com.lastpass.lastpassmacdesktop", "me.proton.pass.electron",
                   "com.apple.SecurityAgent", "com.apple.SecurityAgentHelper.arm64",
                   "com.apple.SecurityAgentHelper.x86_64", "com.apple.loginwindow"] {
            XCTAssertEqual(KeyPassthrough.reason(bundleID: id, focused: nil), "credential-app", id)
        }
        XCTAssertNil(KeyPassthrough.reason(bundleID: "com.apple.TextEdit", focused: nil))
    }

    // MARK: Ruling R22: terminals type no Vietnamese at all

    func testTerminalsPassThroughEditorsDoNot() {
        for id in CodeApps.terminals {
            XCTAssertEqual(KeyPassthrough.reason(bundleID: id, focused: nil), "terminal", id)
        }
        for id in ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
                   "net.kovidgoyal.kitty", "com.github.wez.wezterm"] {
            XCTAssertEqual(KeyPassthrough.reason(bundleID: id, focused: nil), "terminal", id)
        }
        for id in CodeApps.bundleIDs.subtracting(CodeApps.terminals).union(["com.jetbrains.intellij"]) {
            XCTAssertNil(KeyPassthrough.reason(bundleID: id, focused: nil), id)
        }
    }

    // MARK: Security audit LOW-4

    func testMoreRemoteAppsPassThrough() {
        for id in ["com.deskin.client", "com.citrix.receiver.icaviewer.mac", "com.citrix.receiver.nomas",
                   "com.vmware.horizon", "com.lemonmojo.RoyalTSX.App"] {
            XCTAssertEqual(KeyPassthrough.reason(bundleID: id, focused: nil), "remote", id)
        }
    }

    // Security review I-1: a hyphenated label keeps its hyphen for the word list.
    func testHyphenatedLabelsAreCredentials() {
        for a in [field(placeholder: "E-mail"), field(title: "E-mail:"), field(label: "Địa chỉ e-mail"),
                  field(description: "Log-in")] {
            XCTAssertTrue(KeyPassthrough.isCredentialField(attributes: a), "\(a)")
        }
        XCTAssertFalse(KeyPassthrough.isCredentialField(attributes: field(placeholder: "Tìm kiếm")))
    }
}
