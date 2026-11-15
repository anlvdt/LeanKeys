// stdin: keys<TAB>... per message. stdout: what Vikey's Driver produces (Telex, auto switch on, starts in Vietnamese).
#include "Driver.h"
#include <iostream>
#include <string>
#include <codecvt>
#include <locale>
int vLanguage = 1, vSwitchKeyStatus = 0, vCheckSpelling = 1, vUseModernOrthography = 1, vRestoreIfWrongSpelling = 1,
    vFixRecommendBrowser = 1, vUseSmartSwitchKey = 1, vOtherLanguage = 1, vAutoSwitchByTyping = 1;
static int code(char c, bool& shift) {
    static const char* L = "asdfhgzxcv bqweryt123465=97-80]ou[ip lj'k;\\,/nm.";
    shift = false;
    if (c >= 'A' && c <= 'Z') { shift = true; c = c - 'A' + 'a'; }
    static const char* S = "?!@#$%^&*()_+:\"<>{}|~";   // shifted symbols -> base key + Shift
    static const char* U = "/1234567890-=;',.[]\\`";
    if (const char* q = strchr(S, c)) { shift = true; c = U[q - S]; }
    const char* p = strchr(L, c); if (c == ' ') return 49; if (!p) return -1; return (int)(p - L);
}
int main() {
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> cv;
    std::string line;
    while (std::getline(std::cin, line)) {
        std::string keys = line.substr(0, line.find('\t')) + " ";
        VikeyDriver d; vLanguage = 1; d.setLanguage(1); d.resetContext(); std::u16string t;
        for (char c : keys) {
            bool sh; int k = code(c, sh); if (k < 0) { t += (char16_t)c; d.resetContext(); continue; }
            VKEdit e = d.press((Uint16)k, sh, 0);
            for (int i = 0; i < e.deleteCount && !t.empty(); i++) t.pop_back();
            t += e.text;
        }
        std::cout << cv.to_bytes(t) << "\n";
    }
}
