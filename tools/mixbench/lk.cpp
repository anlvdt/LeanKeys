// stdin: keys<TAB>... per message (prep2.py or typo.py). stdout: what LeanKeys' shim (leankeys/VikeyShim, Vikey with
// LeanKeys' fixes) produces: Telex, auto switch on, starts in Vietnamese. --no-fix turns the double-key Backspace
// repair (spec 12.1) off, which leaves Vikey's own behaviour.
// Keys as in vk.cpp, plus typo.py's: '`' is Backspace, '|' marks the current word's length, '^' presses Backspace
// until the word is back to the marked length.
#include "lk_vikey.h"
#include <cstring>
#include <iostream>
#include <string>
#include <codecvt>
#include <locale>
static const int kBackspace = 51;
static int code(char c, bool& shift) {
    static const char* L = "asdfhgzxcv bqweryt123465=97-80]ou[ip lj'k;\\,/nm.";
    shift = false;
    if (c == '`') return kBackspace;
    if (c >= 'A' && c <= 'Z') { shift = true; c = c - 'A' + 'a'; }
    static const char* S = "?!@#$%^&*()_+:\"<>{}|~";   // shifted symbols -> base key + Shift
    static const char* U = "/1234567890-=;',.[]\\`";
    if (const char* q = strchr(S, c)) { shift = true; c = U[q - S]; }
    const char* p = strchr(L, c); if (c == ' ') return 49; if (!p) return -1; return (int)(p - L);
}
// Letters of a word: ASCII letters, and the accented letters the engine types (all at U+00C0 and above).
static bool isLetter(char16_t c) { return ((c | 32) >= 'a' && (c | 32) <= 'z') || c >= 0xC0; }
static size_t wordLength(const std::u16string& t) {
    size_t i = t.size(); while (i > 0 && isLetter(t[i - 1])) i--; return t.size() - i;
}
int main(int argc, char** argv) {
    bool fix = !(argc > 1 && !strcmp(argv[1], "--no-fix"));
    lk_vikey_init();
    lk_vikey_set_double_key_fix(fix);
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> cv;
    std::string line;
    while (std::getline(std::cin, line)) {
        std::string keys = line.substr(0, line.find('\t')) + " ";
        lk_vikey_set_language(1); lk_vikey_reset_context(); std::u16string t;
        size_t mark = 0;
        auto press = [&](int k, bool sh) {
            lk_edit e; lk_vikey_press((uint16_t)k, sh, 0, &e);
            for (int i = 0; i < e.deleteCount && !t.empty(); i++) t.pop_back();
            t.append((const char16_t*)e.text, e.length);
        };
        for (char c : keys) {
            if (c == '|') { mark = wordLength(t); continue; }
            if (c == '^') { for (int guard = 0; wordLength(t) > mark && guard < 40; guard++) press(kBackspace, false); continue; }
            bool sh; int k = code(c, sh); if (k < 0) { t += (char16_t)c; lk_vikey_reset_context(); continue; }
            press(k, sh);
        }
        std::cout << cv.to_bytes(t) << "\n";
    }
}
