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
//   --convert-wrong  a typist who presses ⌃⌫ (lk_vikey_convert_last_word) once when the word just finished shows
//                  something other than its target (as score.py's `same`: case and tone placement ignored). The check is
//                  at the word's break key (Space , . ; ? ! ) ] " '), and before Return for the last word with --end
//                  return (with return-fix the typist trusts Return to finish the word). Needs the target column.
//   --learn        an in-process rule book with the thresholds of spec 12.2 and the convert kind of the ⌃⌫ design,
//                  fed by lk_vikey_take_undo after every press and answering the shim's keep filter
//                  (lk_vikey_set_fix_filter) and convert filter (lk_vikey_set_convert_filter). With --convert-wrong,
//                  the ⌃⌫ presses per 500 messages are printed.
// Counts for --undo-bad-fix, --convert-wrong and --learn go to stderr.
#include "lk_vikey.h"
#include <algorithm>
#include <cstring>
#include <map>
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

// Same as score.py's `same`: equal apart from case and where the tone mark sits (hoà/hòa).
static std::pair<std::u16string, std::u16string> toneSplit(const std::u16string& w) {
    static const char16_t* T[] = {u"aàáãảạ", u"ăằắẵẳặ", u"âầấẫẩậ", u"eèéẽẻẹ", u"êềếễểệ", u"iìíĩỉị", u"oòóõỏọ", u"ôồốỗổộ",
                                  u"ơờớỡởợ", u"uùúũủụ", u"ưừứữửự", u"yỳýỹỷỵ"};
    std::u16string base, tones;
    for (char16_t c : lower(w)) {
        bool found = false;
        for (auto row : T) for (int k = 0; k < 6 && !found; k++) if (row[k] == c) {
            base += row[0]; if (k) tones += (char16_t)(u'0' + k); found = true;
        }
        if (!found) base += c;
    }
    std::sort(tones.begin(), tones.end());
    return {base, tones};
}
static bool sameWord(const std::u16string& a, const std::u16string& b) { return toneSplit(a) == toneSplit(b); }
// The letter run at the end of the line, ignoring the break characters after it.
static std::u16string lastWord(const std::u16string& t) {
    size_t i = t.size(); while (i > 0 && !isLetter(t[i - 1])) i--;
    size_t j = i; while (j > 0 && isLetter(t[j - 1])) j--;
    return t.substr(j, i - j);
}

// A convert rule carries its direction (Ruling 5): toRaw when it was learned on a Telex form (the conversion gives the raw
// keys), toTelex when learned on a word shown as its raw keys. It applies only to a word shown in its from-form.
static const std::u16string kRaw = u"|raw", kTelex = u"|telex";
static std::u16string convertKey(const std::u16string& keys, bool toRaw) { return keys + (toRaw ? kRaw : kTelex); }
// ONE rule for both sides: a word shown as its raw keys (case-insensitive) is in the toTelex from-form, anything else in
// the toRaw from-form. The filter asks about the word shown; an event's direction is where the conversion went.
static bool shownAsKeys(const std::u16string& shown, const std::u16string& keys) { return lower(shown) == lower(keys); }
static bool ruleToRawForShown(const std::u16string& shown, const std::u16string& keys) { return !shownAsKeys(shown, keys); }
static bool eventToRaw(const std::u16string& after, const std::u16string& keys) { return shownAsKeys(after, keys); }

// The rule book of spec 12.2 (UndoRuleBook.swift) with the convert kind of the ⌃⌫ design (spec 5.3): one table per kind,
// keyed (previous, text); text is the word before Vikey's fix (keep) or the raw keys (convert). A context rule
// (previous not empty) applies after 1 event; the contextless count of a text after 2; a reverse drops the text's rules
// of that kind and blocks it until 2 more events of that kind; recording one kind for a key removes the other kind there.
struct Book {
    typedef std::pair<std::u16string, std::u16string> Key;   // (previous, text)
    std::map<Key, int> table[2];                              // 0 keep, 1 convert
    std::map<std::u16string, int> blocked[2];
    long events[2] = {0, 0}, reverses[2] = {0, 0}, hits[2] = {0, 0};
    void record(int kind, std::u16string text, std::u16string prev, bool reverse) {
        text = lower(text); prev = lower(prev);
        if (text.empty()) return;
        if (reverse) {
            reverses[kind]++;
            for (auto it = table[kind].begin(); it != table[kind].end();) it = it->first.second == text ? table[kind].erase(it) : std::next(it);
            blocked[kind][text] = 2;
            return;
        }
        events[kind]++;
        // One kind per (previous, text): a keep erases the convert rules there (both directions), a convert the keep.
        std::u16string base = text;
        if (kind == 1) {
            for (const std::u16string* suf : {&kRaw, &kTelex})
                if (text.size() > suf->size() && text.compare(text.size() - suf->size(), suf->size(), *suf) == 0) base = text.substr(0, text.size() - suf->size());
        }
        for (const Key& k : {Key(prev, base), Key(u"", base)}) {
            if (kind == 0) { table[1].erase(Key(k.first, convertKey(k.second, true))); table[1].erase(Key(k.first, convertKey(k.second, false))); }
            else table[0].erase(k);
        }
        if (!prev.empty()) table[kind][Key(prev, text)]++;
        table[kind][Key(u"", text)]++;
        auto b = blocked[kind].find(text);
        if (b != blocked[kind].end() && --b->second <= 0) blocked[kind].erase(b);
    }
    bool applies(int kind, std::u16string text, std::u16string prev) {
        text = lower(text); prev = lower(prev);
        if (blocked[kind].count(text)) return false;
        bool hit = false;
        if (!prev.empty() && table[kind].count(Key(prev, text))) hit = true;
        else { auto it = table[kind].find(Key(u"", text)); hit = it != table[kind].end() && it->second >= 2; }
        if (hit) hits[kind]++;
        return hit;
    }
};
static bool learn = false;
static Book book;
static bool vetoed = false;
static std::u16string u16(const uint16_t* p, int n) { return std::u16string((const char16_t*)p, n); }

// The last fix Vikey reported through the filter (which never vetoes, so the shim behaves as with no filter).
static bool fixSeen = false;
static std::u16string fixBefore, fixAfter;
static int recordFix(const lk_fix* f) {
    fixSeen = true;
    fixBefore.assign((const char16_t*)f->before, f->beforeLength);
    fixAfter.assign((const char16_t*)f->after, f->afterLength);
    vetoed = learn && book.applies(0, fixBefore, u16(f->previous, f->previousLength));
    if (vetoed) fixSeen = false;   // the fix did not happen
    return vetoed ? 1 : 0;
}
static int keepFilter(const lk_fix* f) { return recordFix(f); }
static int convertFilter(const lk_fix* f) {
    std::u16string keys = u16(f->keys, f->keysLength);
    return book.applies(1, convertKey(keys, ruleToRawForShown(u16(f->before, f->beforeLength), keys)), u16(f->previous, f->previousLength)) ? 1 : 0;
}
// Feed the learner what the shim reports (spec 5.3): kinds 0 and 1 are held by the shim until the next key.
static void pump() {
    lk_undo u;
    while (lk_vikey_take_undo(&u)) {
        if (!learn) continue;
        std::u16string prev = u16(u.fix.previous, u.fix.previousLength);
        if (u.kind == LK_UNDO_BACKSPACE) book.record(0, u16(u.fix.before, u.fix.beforeLength), prev, u.reverse);
        else {
            std::u16string k = u16(u.fix.keys, u.fix.keysLength);
            // after = what the conversion made (kinds 1 and 2).
            book.record(1, convertKey(k, eventToRaw(u16(u.fix.after, u.fix.afterLength), k)), prev, u.kind == LK_UNDO_RULE_REVERSE || u.reverse);
        }
    }
}

int main(int argc, char** argv) {
    bool fix = true, chain = false, undoBadFix = false, startEn = false, convertWrong = false;
    std::string end = "space", langsPath;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--no-fix") fix = false;
        else if (a == "--chain") chain = true;
        else if (a == "--undo-bad-fix") undoBadFix = true;
        else if (a == "--convert-wrong") convertWrong = true;
        else if (a == "--learn") learn = true;
        else if (a == "--start-en") startEn = true;
        else if (a == "--end" && i + 1 < argc) end = argv[++i];
        else if (a == "--langs" && i + 1 < argc) langsPath = argv[++i];
        else { std::cerr << "unknown option " << a << "\n"; return 2; }
    }
    if (end != "space" && end != "return" && end != "return-fix") { std::cerr << "--end space|return|return-fix\n"; return 2; }
    std::setlocale(LC_CTYPE, "en_US.UTF-8");
    lk_vikey_init();
    lk_vikey_set_double_key_fix(fix);
    if (undoBadFix || learn) lk_vikey_set_fix_filter(keepFilter);
    if (learn) lk_vikey_set_convert_filter(convertFilter);
    std::ofstream langs; if (!langsPath.empty()) langs.open(langsPath);
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> cv;
    long fixes = 0, wrongFixes = 0, undone = 0, undoRestored = 0;
    long cwPresses = 0, cwFixed = 0, cwStill = 0, messages = 0, blockPresses = 0, printedUpTo = 0;
    std::string line;
    bool first = true;
    while (std::getline(std::cin, line)) {
        std::istringstream fields(line);
        std::string keys, targetText;
        std::getline(fields, keys, '\t'); std::getline(fields, targetText, '\t');
        std::vector<std::u16string> target;
        { std::istringstream w(targetText); std::string s; while (w >> s) target.push_back(lower(cv.from_bytes(s))); }
        if (end == "space") keys += " ";
        if (learn && convertWrong && messages > 0 && messages % 500 == 0) {
            std::cerr << "learn: messages " << messages - 499 << "-" << messages << "  presses " << blockPresses << "\n";
            blockPresses = 0; printedUpTo = messages;
        }
        messages++;
        if (!chain || first) { lk_vikey_set_language(startEn ? 0 : 1); pump(); }
        if (!chain) { lk_vikey_reset_context(); pump(); }
        first = false;
        if (langs.is_open()) langs << (lk_vikey_language() ? 'V' : 'E') << "\n";
        std::u16string t;
        size_t mark = 0;
        int words = 0;   // letter runs started so far in the keys: the target index of the word being typed is words-1
        auto press = [&](int k, bool sh) {
            lk_edit e; lk_vikey_press((uint16_t)k, sh, 0, &e);
            for (int i = 0; i < e.deleteCount && !t.empty(); i++) t.pop_back();
            t.append((const char16_t*)e.text, e.length);
            pump();
        };
        // The typist's ⌃⌫: when the word just finished shows something other than the target, press it once.
        auto convertCheck = [&](int wi) {
            if (!convertWrong || wi < 0 || wi >= (int)target.size()) return;
            if (sameWord(lastWord(t), target[wi])) return;
            lk_edit e; cwPresses++; blockPresses++;
            if (lk_vikey_convert_last_word(0, &e)) {
                for (int i = 0; i < e.deleteCount && !t.empty(); i++) t.pop_back();
                t.append((const char16_t*)e.text, e.length);
            }
            pump();
            if (sameWord(lastWord(t), target[wi])) cwFixed++; else cwStill++;
        };
        bool inWord = false;
        bool pending = false;   // a word was typed and no break key has ended it yet (digits and / do not end it)
        auto type = [&](char c) {
            bool letter = (c | 32) >= 'a' && (c | 32) <= 'z';
            if (letter && !inWord) words++;
            if (letter) pending = true;
            // The break characters of the shim (lk_vikey_convert_last_word): the key that ends the word for the typist.
            bool ended = pending && c != '\0' && strchr(" ,.;?!)]\"'", c);
            if (ended) pending = false;
            inWord = letter;
            bool sh; int k = code(c, sh);
            if (k < 0) { t += (char16_t)c; lk_vikey_reset_context(); pump(); return; }
            fixSeen = false;
            press(k, sh);
            if (!undoBadFix || !fixSeen) { if (ended) convertCheck(words - 1); return; }
            fixes++;
            // The fix was of the word just finished (index words-1). Broke it: the word as typed was the target.
            int wi = words - 1;
            if (wi < 0 || wi >= (int)target.size()) return;
            if (lower(fixBefore) != target[wi] || lower(fixAfter) == target[wi]) { if (ended) convertCheck(wi); return; }
            wrongFixes++;
            press(kBackspace, false); press(kBackspace, false);
            undone++;
            std::u16string tail = t.substr(t.size() - std::min(t.size(), fixBefore.size()));
            if (lower(tail) == target[wi]) undoRestored++;
            fixSeen = false;
            press(k, sh);   // the break key again
            if (ended) convertCheck(wi);
        };
        for (char c : keys) {
            if (c == '|') { mark = wordLength(t); continue; }
            if (c == '^') { for (int guard = 0; wordLength(t) > mark && guard < 40; guard++) press(kBackspace, false); continue; }
            type(c);
        }
        if (end != "space") {
            // The last word has no break key: ⌃⌫ before Return, as the typist sees it. Not with return-fix: there Return
            // finishes the word, which the typist trusts (a check here would press ⌃⌫ on words Return was about to fix).
            if (pending && end == "return") convertCheck(words - 1);
            if (end == "return-fix") lk_vikey_set_fix_at_return(1);
            fixSeen = false;
            press(kReturn, false);
            // As VikeyEngine does after Return: the next word starts fresh, Việt/Anh stays.
            lk_vikey_reset_context(); pump();
            if (undoBadFix && fixSeen) fixes++;   // a fix at Return is sent with the message: too late for ⌫⌫
        }
        std::u16string out;
        for (char16_t c : t) if (c != u'\r' && c != u'\n') out += c;
        std::cout << cv.to_bytes(out) << "\n";
    }
    if (learn && convertWrong && messages > printedUpTo)
        std::cerr << "learn: messages " << printedUpTo + 1 << "-" << messages << "  presses " << blockPresses << "\n";
    if (convertWrong)
        std::cerr << "convert-wrong: presses " << cwPresses << "  fixed " << cwFixed << "  still wrong " << cwStill << "\n";
    if (learn)
        std::cerr << "learn: keep events " << book.events[0] << " (reverse " << book.reverses[0] << ", applied " << book.hits[0]
                  << ")  convert events " << book.events[1] << " (reverse " << book.reverses[1] << ", applied " << book.hits[1] << ")\n";
    if (undoBadFix)
        std::cerr << "undo-bad-fix: fixes " << fixes << "  broke a word " << wrongFixes << "  undone with ⌫⌫ " << undone
                  << "  word back as typed " << undoRestored << "\n";
}
