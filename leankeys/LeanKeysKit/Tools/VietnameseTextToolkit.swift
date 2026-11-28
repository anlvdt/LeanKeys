import AppKit
import Foundation

/// UniKey-style text transformations applied explicitly on user demand (menu click).
/// Never monitors or reads the clipboard in the background.
public enum VietnameseTextToolkit {
    public enum Action: String, CaseIterable {
        case stripDiacritics = "Bỏ dấu tiếng Việt"
        case uppercase = "CHỮ HOA"
        case lowercase = "chữ thường"
        case sentenceCase = "Viết hoa đầu câu"
        case titleCase = "Viết Hoa Từng Từ"
        case tcvn3ToUnicode = "TCVN3 (ABC) → Unicode"
        case unicodeToTCVN3 = "Unicode → TCVN3 (ABC)"
        case vniWindowsToUnicode = "VNI Windows → Unicode"
    }

    public static func transform(_ text: String, action: Action) -> String {
        switch action {
        case .stripDiacritics: return stripDiacritics(text)
        case .uppercase: return text.precomposedStringWithCanonicalMapping.uppercased()
        case .lowercase: return text.precomposedStringWithCanonicalMapping.lowercased()
        case .sentenceCase: return sentenceCase(text)
        case .titleCase: return titleCase(text)
        case .tcvn3ToUnicode: return tcvn3ToUnicode(text)
        case .unicodeToTCVN3: return unicodeToTCVN3(text)
        case .vniWindowsToUnicode: return vniWindowsToUnicode(text)
        }
    }

    /// Reads the current clipboard string, applies `action`, and writes the result back. Returns true if changed/applied.
    @discardableResult
    public static func applyToClipboard(_ action: Action, pasteboard: NSPasteboard = .general) -> Bool {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return false }
        let out = transform(text, action: action)
        pasteboard.clearContents()
        return pasteboard.setString(out, forType: .string)
    }

    public static func stripDiacritics(_ text: String) -> String {
        let nfc = text.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
        return nfc.folding(options: .diacriticInsensitive, locale: Locale(identifier: "vi_VN"))
    }

    public static func sentenceCase(_ text: String) -> String {
        let lower = text.precomposedStringWithCanonicalMapping.lowercased()
        var out = ""
        out.reserveCapacity(lower.count)
        var capNext = true
        for ch in lower {
            if capNext, ch.isLetter {
                out.append(contentsOf: String(ch).uppercased())
                capNext = false
            } else {
                out.append(ch)
                if ch == "." || ch == "!" || ch == "?" || ch == "\n" || ch == "\r" {
                    capNext = true
                } else if !ch.isWhitespace && ch != "\"" && ch != "“" && ch != "(" {
                    capNext = false
                }
            }
        }
        return out
    }

    public static func titleCase(_ text: String) -> String {
        let lower = text.precomposedStringWithCanonicalMapping.lowercased()
        var out = ""
        out.reserveCapacity(lower.count)
        var atWordStart = true
        for ch in lower {
            if ch.isLetter || ch.isNumber {
                if atWordStart && ch.isLetter {
                    out.append(contentsOf: String(ch).uppercased())
                } else {
                    out.append(ch)
                }
                atWordStart = false
            } else {
                out.append(ch)
                atWordStart = true
            }
        }
        return out
    }

    // MARK: - Legacy Vietnamese encodings (TCVN3 & VNI Windows)

    private static let tcvn3Pairs: [(String, String)] = [
        ("µ", "à"), ("¸", "á"), ("¶", "ả"), ("·", "ã"), ("¹", "ạ"),
        ("¨", "ă"), ("»", "ằ"), ("¾", "ắ"), ("¼", "ẳ"), ("½", "ẵ"), ("Æ", "ặ"),
        ("©", "â"), ("Ç", "ầ"), ("Ê", "ấ"), ("È", "ẩ"), ("É", "ẫ"), ("Ë", "ậ"),
        ("Ì", "è"), ("Ð", "é"), ("Î", "ẻ"), ("Ï", "ẽ"), ("Ñ", "ẹ"),
        ("ª", "ê"), ("Ò", "ề"), ("Õ", "ế"), ("Ó", "ể"), ("Ô", "ễ"), ("Ö", "ệ"),
        ("×", "ì"), ("Ý", "í"), ("Ø", "ỉ"), ("Ü", "ĩ"), ("Þ", "ị"),
        ("ß", "ò"), ("ã", "ó"), ("á", "ỏ"), ("â", "õ"), ("ä", "ọ"),
        ("«", "ô"), ("å", "ồ"), ("è", "ố"), ("æ", "ổ"), ("ç", "ỗ"), ("é", "ộ"),
        ("¬", "ơ"), ("ê", "ờ"), ("í", "ớ"), ("ë", "ở"), ("ì", "ỡ"), ("î", "ợ"),
        ("ï", "ù"), ("ó", "ú"), ("ñ", "ủ"), ("ò", "ũ"), ("ô", "ụ"),
        ("­", "ư"), ("õ", "ừ"), ("ø", "ứ"), ("ö", "ử"), ("÷", "ữ"), ("ù", "ự"),
        ("ú", "ỳ"), ("ý", "ý"), ("û", "ỷ"), ("ü", "ỹ"), ("þ", "ỵ"),
        ("®", "đ"), ("§", "Đ"),
        ("¡", "Ă"), ("¢", "Â"), ("£", "Ê"), ("¤", "Ô"), ("¥", "Ơ"), ("¦", "Ư"),
    ]

    private static let tcvn3ToUniMap: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (k, v) in tcvn3Pairs {
            if let kc = k.first, let vc = v.first { map[kc] = vc }
        }
        return map
    }()

    private static let uniToTcvn3Map: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (k, v) in tcvn3Pairs {
            if let kc = k.first, let vc = v.first, map[vc] == nil { map[vc] = kc }
        }
        return map
    }()

    public static func tcvn3ToUnicode(_ text: String) -> String {
        String(text.map { tcvn3ToUniMap[$0] ?? $0 }).precomposedStringWithCanonicalMapping
    }

    public static func unicodeToTCVN3(_ text: String) -> String {
        String(text.precomposedStringWithCanonicalMapping.map { uniToTcvn3Map[$0] ?? $0 })
    }

    private static let vniWinTable: [(vni: String, uni: String)] = [
        ("aø", "à"), ("aù", "á"), ("aû", "ả"), ("aõ", "ã"), ("aï", "ạ"),
        ("AØ", "À"), ("AÙ", "Á"), ("AÛ", "Ả"), ("AÕ", "Ã"), ("AÏ", "Ạ"),
        ("aê", "ă"), ("aè", "ằ"), ("aé", "ắ"), ("aú", "ẳ"), ("aü", "ẵ"), ("aë", "ặ"),
        ("AÊ", "Ă"), ("AÈ", "Ằ"), ("AÉ", "Ắ"), ("AÚ", "Ẳ"), ("AÜ", "Ẵ"), ("AË", "Ặ"),
        ("aâ", "â"), ("aà", "ầ"), ("aá", "ấ"), ("aå", "ẩ"), ("aã", "ẫ"), ("aä", "ậ"),
        ("AÂ", "Â"), ("AÀ", "Ầ"), ("AÁ", "Ấ"), ("AÅ", "Ẩ"), ("AÃ", "Ẫ"), ("AÄ", "Ậ"),
        ("eø", "è"), ("eù", "é"), ("eû", "ẻ"), ("eõ", "ẽ"), ("eï", "ẹ"),
        ("EØ", "È"), ("EÙ", "É"), ("EÛ", "Ẻ"), ("EÕ", "Ẽ"), ("EÏ", "Ẹ"),
        ("eâ", "ê"), ("eà", "ề"), ("eá", "ế"), ("eå", "ể"), ("eã", "ễ"), ("eä", "ệ"),
        ("EÂ", "Ê"), ("EÀ", "Ề"), ("EÁ", "Ế"), ("EÅ", "Ể"), ("EÃ", "Ễ"), ("EÄ", "Ệ"),
        ("ì", "ì"), ("í", "í"), ("æ", "ỉ"), ("ó", "ĩ"), ("ò", "ị"),
        ("Ì", "Ì"), ("Í", "Í"), ("Æ", "Ỉ"), ("Ó", "Ĩ"), ("Ò", "Ị"),
        ("oø", "ò"), ("où", "ó"), ("oû", "ỏ"), ("oõ", "õ"), ("oï", "ọ"),
        ("OØ", "Ò"), ("OÙ", "Ó"), ("OÛ", "Ỏ"), ("OÕ", "Õ"), ("OÏ", "Ọ"),
        ("oâ", "ô"), ("oà", "ồ"), ("oá", "ố"), ("oå", "ổ"), ("oã", "ỗ"), ("oä", "ộ"),
        ("OÂ", "Ô"), ("OÀ", "Ồ"), ("OÁ", "Ố"), ("OÅ", "Ổ"), ("OÃ", "Ỗ"), ("OÄ", "Ộ"),
        ("ô", "ơ"), ("ôø", "ờ"), ("ôù", "ớ"), ("ôû", "ở"), ("ôõ", "ỡ"), ("ôï", "ợ"),
        ("Ô", "Ơ"), ("ÔØ", "Ờ"), ("ÔÙ", "Ớ"), ("ÔÛ", "Ở"), ("ÔÕ", "Ỡ"), ("ÔÏ", "Ợ"),
        ("uø", "ù"), ("uù", "ú"), ("uû", "ủ"), ("uõ", "ũ"), ("uï", "ụ"),
        ("UØ", "Ù"), ("UÙ", "Ú"), ("UÛ", "Ủ"), ("UÕ", "Ũ"), ("UÏ", "Ụ"),
        ("ö", "ư"), ("öø", "ừ"), ("öù", "ứ"), ("öû", "ử"), ("öõ", "ữ"), ("öï", "ự"),
        ("Ö", "Ư"), ("ÖØ", "Ừ"), ("ÖÙ", "Ứ"), ("ÖÛ", "Ử"), ("ÖÕ", "Ữ"), ("ÖÏ", "Ự"),
        ("yø", "ỳ"), ("yù", "ý"), ("yû", "ỷ"), ("yõ", "ỹ"), ("î", "ỵ"),
        ("YØ", "Ỳ"), ("YÙ", "Ý"), ("YÛ", "Ỷ"), ("YÕ", "Ỹ"), ("Î", "Ỵ"),
        ("ñ", "đ"), ("Ñ", "Đ"),
    ]

    private static let vniTwoChar: [String: Character] = {
        var map: [String: Character] = [:]
        for pair in vniWinTable where pair.vni.count == 2 {
            if let ch = pair.uni.first { map[pair.vni] = ch }
        }
        return map
    }()

    private static let vniOneChar: [Character: Character] = {
        var map: [Character: Character] = [:]
        for pair in vniWinTable where pair.vni.count == 1 {
            if let k = pair.vni.first, let ch = pair.uni.first { map[k] = ch }
        }
        return map
    }()

    public static func vniWindowsToUnicode(_ text: String) -> String {
        // Single-pass left-to-right scan so already-converted Unicode characters (like "ò") are never
        // re-matched by single-character VNI codes (like U+00F2 -> "ị").
        let chars = Array(text)
        var out = ""
        out.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            if i + 1 < chars.count {
                let two = String([chars[i], chars[i + 1]])
                if let mapped = vniTwoChar[two] {
                    out.append(mapped)
                    i += 2
                    continue
                }
            }
            out.append(vniOneChar[chars[i]] ?? chars[i])
            i += 1
        }
        return out.precomposedStringWithCanonicalMapping
    }
}
