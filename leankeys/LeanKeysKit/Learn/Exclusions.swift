import Foundation

/// What PhraseLearner never learns from: password managers, and phrases holding a card number or an OTP.
public enum Exclusions {
    /// Password managers. Every key passes straight through there too (`KeyPassthrough`, security audit MEDIUM-3):
    /// user names, TOTP secrets and recovery codes are plain text fields.
    public static let passwordManagers: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "org.keepassxc.keepassxc",
        "in.sinew.Enpass-Desktop",          // Enpass
        "com.lastpass.lastpassmacdesktop",  // LastPass
        "me.proton.pass.electron",          // Proton Pass
    ]

    /// Apps never learned from, by default.
    public static let defaultBundleIDs: Set<String> = passwordManagers
    // Terminals: sudo, ssh and git ask for passwords there without Secure Input or a secure text field. The one
    // list `CodeApps` keeps (task 4 review minor 8).
    .union(CodeApps.terminals)

    /// A word shaped like a password or key: at least 6 characters (sentence punctuation at its ends aside) mixing
    /// letters with digits ("hunter2hunter2", "Matkhau2024"), or using a symbol people put in passwords
    /// (`@ # $ % ^ & * ! ~ _ + = | \\ < > ?`) next to letters or digits ("P4ssw0rd!", "Abc@12345").
    /// Not secret-shaped: plain words, hyphenated words ("check-in"), numbers with `. , / : -` (dates, prices,
    /// times, house numbers), money and times with a unit ("500.000đ", "12h30"), and web addresses whose last
    /// label is letters only ("shopee.vn/abc", "https://…"; "Matkhau.2024" is no address). Emails and phones are recognised pieces and never reach this check.
    public static func looksLikeSecret(_ word: String) -> Bool {
        let core = trimmedWord(word)
        guard core.count >= 6 else { return false }
        let lower = core.lowercased()
        if lower.range(of: #"^(https?://)?[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}(/\S*)?$"#, options: .regularExpression) != nil { return false }
        if lower.range(of: #"^\d[\d.,]*(đ|d|k|vnđ|vnd|usd|tr|đồng)$"#, options: .regularExpression) != nil { return false }
        if lower.range(of: #"^\d{1,2}h(\d{1,2})?(p|ph)?$"#, options: .regularExpression) != nil { return false }
        var letters = false, digits = false, special = false
        for scalar in core.unicodeScalars {
            if CharacterSet.letters.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar) { letters = true }
            else if CharacterSet.decimalDigits.contains(scalar) { digits = true }
            else if !"-'’./,:".unicodeScalars.contains(scalar) { special = true }
        }
        return (letters && digits) || (special && (letters || digits))
    }

    /// `word` without the sentence punctuation and quotes around it.
    public static func trimmedWord(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:()\"'“”‘’…"))
    }

    /// A number as typed: digit groups joined by single spaces, dots or dashes ("4111 1111 1111 1111",
    /// "0912.345.678", "482913").
    private static let numberToken = try! NSRegularExpression(pattern: #"\d+(?:[ .\-]\d+)*"#)

    /// `text` holds a card number, or is an OTP. Such a phrase is dropped whole, with every piece in it.
    /// - Card: any run of consecutive digit groups in a number, 13–19 digits in all, passing Luhn
    ///   ("Thẻ 4111 1111 1111 1111 12 28" holds one).
    /// - OTP: the whole phrase is one group of 4–8 digits ("482913"). Digit groups inside text are fine
    ///   ("Số 1234 đường Lê Lợi").
    public static func containsSensitiveNumber(_ text: String) -> Bool {
        if text.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil { return true }
        let ns = text as NSString
        for match in numberToken.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            let tokenNS = token as NSString
            let groups = digitGroup.matches(in: token, range: NSRange(location: 0, length: tokenNS.length)).map(\.range)
            for i in groups.indices {
                var count = 0
                for j in i..<groups.count {
                    count += groups[j].length
                    if count > 19 { break }
                    guard count >= 13 else { continue }
                    let start = groups[i].location
                    let run = tokenNS.substring(with: NSRange(location: start,
                                                              length: groups[j].location + groups[j].length - start))
                    // A tax code with its branch suffix ("0312345678-001") has 13 digits too; one in ten passes Luhn.
                    if luhn(run.filter(\.isASCIIDigit)), !isTaxCode(run) { return true }
                }
            }
        }
        return false
    }

    private static let digitGroup = try! NSRegularExpression(pattern: #"\d+"#)

    private static func isTaxCode(_ token: String) -> Bool {
        token.range(of: #"^\d{10}-\d{3}$"#, options: .regularExpression) != nil
    }

    static func luhn(_ digits: String) -> Bool {
        var sum = 0
        for (i, c) in digits.reversed().enumerated() {
            guard var d = c.wholeNumberValue else { return false }
            if i % 2 == 1 {
                d *= 2
                if d > 9 { d -= 9 }
            }
            sum += d
        }
        return sum % 10 == 0
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
