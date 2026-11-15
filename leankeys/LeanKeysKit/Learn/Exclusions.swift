import Foundation

/// What PhraseLearner never learns from: password managers, and phrases holding a card number or an OTP.
public enum Exclusions {
    /// Apps never learned from, by default.
    public static let defaultBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
    ]

    /// A number as typed: digit groups joined by single spaces, dots or dashes ("4111 1111 1111 1111",
    /// "0912.345.678", "482913").
    private static let numberToken = try! NSRegularExpression(pattern: #"\d+(?:[ .\-]\d+)*"#)

    /// `text` holds a card number (13–19 digits passing Luhn, separators allowed) or an OTP (4–8 digits typed as
    /// one group, with no letter or digit run touching it). Such a phrase is dropped whole, with every piece in it.
    public static func containsSensitiveNumber(_ text: String) -> Bool {
        let ns = text as NSString
        for match in numberToken.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            let digits = token.filter(\.isASCIIDigit)
            // A tax code with its branch suffix ("0312345678-001") has 13 digits too; one in ten passes Luhn.
            if (13...19).contains(digits.count), luhn(digits), !isTaxCode(token) { return true }
            if digits.count == token.count, (4...8).contains(digits.count), !touchesLetter(ns, match.range) {
                return true
            }
        }
        return false
    }

    /// A letter right before or after the run ("A1234B", "v2024x"): part of a code word, not an OTP standing alone.
    private static func touchesLetter(_ ns: NSString, _ range: NSRange) -> Bool {
        func isLetter(_ i: Int) -> Bool {
            guard i >= 0, i < ns.length, let scalar = UnicodeScalar(ns.character(at: i)) else { return false }
            return CharacterSet.letters.contains(scalar)
        }
        return isLetter(range.location - 1) || isLetter(range.location + range.length)
    }

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
