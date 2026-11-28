// stdin: keys<TAB>... per message. stdout: what Vikey's Driver produces (Telex, auto switch on, starts in Vietnamese).
// Options as lk.cpp's: --end space|return (Vikey has no fix at Return), --chain, --start-en, --langs FILE.
#include "Driver.h"
#include <fstream>
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
int main(int argc, char** argv) {
    bool chain = false, startEn = false;
    std::string end = "space", langsPath;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--chain") chain = true;
        else if (a == "--start-en") startEn = true;
        else if (a == "--end" && i + 1 < argc) end = argv[++i];
        else if (a == "--langs" && i + 1 < argc) langsPath = argv[++i];
        else { std::cerr << "unknown option " << a << "\n"; return 2; }
    }
    if (end != "space" && end != "return") { std::cerr << "--end space|return\n"; return 2; }
    std::ofstream langs; if (!langsPath.empty()) langs.open(langsPath);
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> cv;
    std::string line;
    VikeyDriver d;
    bool first = true;
    while (std::getline(std::cin, line)) {
        std::string keys = line.substr(0, line.find('\t'));
        if (end == "space") keys += " ";
        if (!chain || first) { vLanguage = startEn ? 0 : 1; d.setLanguage(vLanguage); }
        if (!chain) d.resetContext();
        first = false;
        if (langs.is_open()) langs << (vLanguage ? 'V' : 'E') << "\n";
        std::u16string t;
        auto press = [&](int k, bool sh) {
            VKEdit e = d.press((Uint16)k, sh, 0);
            for (int i = 0; i < e.deleteCount && !t.empty(); i++) t.pop_back();
            t += e.text;
        };
        for (char c : keys) {
            bool sh; int k = code(c, sh); if (k < 0) { t += (char16_t)c; d.resetContext(); continue; }
            press(k, sh);
        }
        if (end == "return") { press(36, false); d.resetContext(); }
        std::u16string out;
        for (char16_t c : t) if (c != u'\r' && c != u'\n') out += c;
        std::cout << cv.to_bytes(out) << "\n";
    }
}
