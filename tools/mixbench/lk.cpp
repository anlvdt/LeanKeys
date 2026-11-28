// stdin: keys<TAB>target<TAB>flags per message (prep2.py or typo.py). stdout: what LeanKeys' shim (leankeys/VikeyShim,
// Vikey with LeanKeys' fixes) produces, one line per message: Telex, auto switch on, starts in Vietnamese.
// Keys as in vk.cpp, plus typo.py's: '`' is Backspace, '|' marks the current word's length, '^' presses Backspace
// until the word is back to the marked length.
//
// Options (any order):
//   --no-fix       the double-key Backspace repair (spec 12.1) off, which leaves Vikey's own behaviour.
//   --end KIND     how a message ends: space (default: a Space after the last word), return (Return, as in a
//                  one-line field or an address bar: Vikey D62 leaves the last word as typed), return-fix (Return
//                  in a text area, where LeanKeys lets Return finish the word: lk_vikey_set_fix_at_return).
//   --chain        one conversation: the language carries over from one message to the next, as in the app (after
//                  Return the app resets the typing context but keeps Việt/Anh). Default: every message starts
//                  fresh in Vietnamese.
//   --undo-bad-fix a typist who presses Backspace twice right after every fix of Vikey's that broke a word (the
//                  word before the fix is the target), then types the break key again. Needs the target column.
//                  On clean text Vikey's wrong words are almost all words it left alone, not fixes: see README.
//   --start-en     every message (or, with --chain, the first) starts in English instead of Vietnamese.
//   --langs FILE   write V or E per message: the language when its first key was typed.
// Counts for --undo-bad-fix go to stderr.
#include "lk_vikey.h"
#include <cstring>
#include <cwctype>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
#include <codecvt>
#include <locale>
static const int kBackspace = 51, kReturn = 36;
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
static std::u16string lower(std::u16string s) { for (auto& c : s) c = (char16_t)std::towlower((wint_t)c); return s; }

// The last fix Vikey reported through the filter (which never vetoes, so the shim behaves as with no filter).
static bool fixSeen = false;
static std::u16string fixBefore, fixAfter;
static int recordFix(const lk_fix* f) {
    fixSeen = true;
    fixBefore.assign((const char16_t*)f->before, f->beforeLength);
    fixAfter.assign((const char16_t*)f->after, f->afterLength);
    return 0;
}

int main(int argc, char** argv) {
    bool fix = true, chain = false, undoBadFix = false, startEn = false;
    std::string end = "space", langsPath;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--no-fix") fix = false;
        else if (a == "--chain") chain = true;
        else if (a == "--undo-bad-fix") undoBadFix = true;
        else if (a == "--start-en") startEn = true;
        else if (a == "--end" && i + 1 < argc) end = argv[++i];
        else if (a == "--langs" && i + 1 < argc) langsPath = argv[++i];
        else { std::cerr << "unknown option " << a << "\n"; return 2; }
    }
    if (end != "space" && end != "return" && end != "return-fix") { std::cerr << "--end space|return|return-fix\n"; return 2; }
    std::setlocale(LC_CTYPE, "en_US.UTF-8");
    lk_vikey_init();
    lk_vikey_set_double_key_fix(fix);
    if (undoBadFix) lk_vikey_set_fix_filter(recordFix);
    std::ofstream langs; if (!langsPath.empty()) langs.open(langsPath);
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> cv;
    long fixes = 0, wrongFixes = 0, undone = 0, undoRestored = 0;
    std::string line;
    bool first = true;
    while (std::getline(std::cin, line)) {
        std::istringstream fields(line);
        std::string keys, targetText;
        std::getline(fields, keys, '\t'); std::getline(fields, targetText, '\t');
        std::vector<std::u16string> target;
        { std::istringstream w(targetText); std::string s; while (w >> s) target.push_back(lower(cv.from_bytes(s))); }
        if (end == "space") keys += " ";
        if (!chain || first) lk_vikey_set_language(startEn ? 0 : 1);
        if (!chain) lk_vikey_reset_context();
        first = false;
        if (langs.is_open()) langs << (lk_vikey_language() ? 'V' : 'E') << "\n";
        std::u16string t;
        size_t mark = 0;
        int words = 0;   // letter runs started so far in the keys: the target index of the word being typed is words-1
        auto press = [&](int k, bool sh) {
            lk_edit e; lk_vikey_press((uint16_t)k, sh, 0, &e);
            for (int i = 0; i < e.deleteCount && !t.empty(); i++) t.pop_back();
            t.append((const char16_t*)e.text, e.length);
        };
        bool inWord = false;
        auto type = [&](char c) {
            bool letter = (c | 32) >= 'a' && (c | 32) <= 'z';
            if (letter && !inWord) words++;
            inWord = letter;
            bool sh; int k = code(c, sh);
            if (k < 0) { t += (char16_t)c; lk_vikey_reset_context(); return; }
            fixSeen = false;
            press(k, sh);
            if (!undoBadFix || !fixSeen) return;
            fixes++;
            // The fix was of the word just finished (index words-1). Broke it: the word as typed was the target.
            int wi = words - 1;
            if (wi < 0 || wi >= (int)target.size()) return;
            if (lower(fixBefore) != target[wi] || lower(fixAfter) == target[wi]) return;
            wrongFixes++;
            press(kBackspace, false); press(kBackspace, false);
            undone++;
            std::u16string tail = t.substr(t.size() - std::min(t.size(), fixBefore.size()));
            if (lower(tail) == target[wi]) undoRestored++;
            fixSeen = false;
            press(k, sh);   // the break key again
        };
        for (char c : keys) {
            if (c == '|') { mark = wordLength(t); continue; }
            if (c == '^') { for (int guard = 0; wordLength(t) > mark && guard < 40; guard++) press(kBackspace, false); continue; }
            type(c);
        }
        if (end != "space") {
            if (end == "return-fix") lk_vikey_set_fix_at_return(1);
            fixSeen = false;
            press(kReturn, false);
            // As VikeyEngine does after Return: the next word starts fresh, Việt/Anh stays.
            lk_vikey_reset_context();
            if (undoBadFix && fixSeen) fixes++;   // a fix at Return is sent with the message: too late for ⌫⌫
        }
        std::u16string out;
        for (char16_t c : t) if (c != u'\r' && c != u'\n') out += c;
        std::cout << cv.to_bytes(out) << "\n";
    }
    if (undoBadFix)
        std::cerr << "undo-bad-fix: fixes " << fixes << "  broke a word " << wrongFixes << "  undone with ⌫⌫ " << undone
                  << "  word back as typed " << undoRestored << "\n";
}
