// lk_vikey.cpp: the C API in lk_vikey.h over Vikey's VikeyDriver. vendor/vikey stays untouched.
#include "lk_vikey.h"
#include "Driver.h"
#include "telex_map.h"
#include <cstring>
#include <string>
#include <unordered_set>
#include <utility>
#include <vector>

extern vKeyHookState HookState;   // Engine.cpp: the engine's output for the last key

// Settings the engine leaves to the platform, with the defaults Vikey's own driver test uses
// (vendor/vikey/Tools/autoswitch/driver/undo_test.cpp). vTelexStyle is defined by Engine.cpp.
int vLanguage = 1, vSwitchKeyStatus = 0, vCheckSpelling = 1, vUseModernOrthography = 1, vRestoreIfWrongSpelling = 1,
    vFixRecommendBrowser = 1, vUseSmartSwitchKey = 1, vOtherLanguage = 1, vAutoSwitchByTyping = 1;

// One driver: the engine keeps its state in globals (vKeyInit), so a second driver would share it anyway.
static VikeyDriver* driver = nullptr;

// Spec 12.2 reads three private members of VikeyDriver (Driver.h) to see a fix Backspace can undo: undoActive and
// undoBreakGone (set by rememberFix, Driver.cpp) and undoText (the word as typed). vendor/ stays untouched, so they
// are reached the one standard way: an explicit template instantiation may name a private member, and the friend
// function it defines hands the member pointer out.
template <typename Tag, typename Tag::type Member> struct PrivateAccess {
    friend typename Tag::type member(Tag) { return Member; }
};
struct UndoActiveTag { typedef bool VikeyDriver::*type; friend type member(UndoActiveTag); };
struct UndoBreakGoneTag { typedef bool VikeyDriver::*type; friend type member(UndoBreakGoneTag); };
struct UndoTextTag { typedef std::u16string VikeyDriver::*type; friend type member(UndoTextTag); };
template struct PrivateAccess<UndoActiveTag, &VikeyDriver::undoActive>;
template struct PrivateAccess<UndoBreakGoneTag, &VikeyDriver::undoBreakGone>;
template struct PrivateAccess<UndoTextTag, &VikeyDriver::undoText>;

static const Uint16 kLetterKeys[26] = {KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I, KEY_J, KEY_K, KEY_L,
                                       KEY_M, KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T, KEY_U, KEY_V, KEY_W, KEY_X,
                                       KEY_Y, KEY_Z};
static const int kNoKey = -1;
// vAutoSwitchWordScore takes fewer than 39 keys.
static const size_t kMaxScoredKeys = 38;

// MARK: - Screen model
//
// A copy of what the shim's edits put on the current line, built from the edits it returns, plus what the
// double-key repair (spec 12.1) needs to know about the last keys. Only the tail of the line is kept: words.

static const size_t kLineTail = 128;

struct ScreenModel {
    std::u16string line;                 // text since the last reset, as the returned edits built it (tail)
    int wordStartLanguage = 1;           // vLanguage before the key that started the current word
    int lastKey = kNoKey;                // the last non-Backspace key
    int keyBefore = kNoKey;              // the non-Backspace key before it
    int languageAfterLastKey = 1;        // vLanguage after the last non-Backspace key
    bool lastKeyReplaced = false;        // the last key was not Backspace and its edit deleted something
    std::u16string wordBeforeLastKey;    // the current word just before the last key (any key)
    bool wordCapsLock = false;           // every letter of the current word was typed with Caps Lock on
};

static ScreenModel model;
static bool doubleKeyFix = true;
static bool capsLockForNextKey = false;   // lk_vikey_set_caps_lock, for the next lk_vikey_press
static bool fixAtNextReturn = false;      // lk_vikey_set_fix_at_return, for the next lk_vikey_press

static void resetModel() { model = ScreenModel(); }

static bool isLetterKey(Uint16 key) {
    for (Uint16 k : kLetterKeys) if (k == key) return true;
    return false;
}

static const LKTelexLetter* telexLetter(char16_t c) {
    for (const LKTelexLetter& m : kTelexMap) if (m.c == c) return &m;
    return nullptr;
}

static bool isAsciiLetter(char16_t c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }
static bool isWordLetter(char16_t c) { return isAsciiLetter(c) || telexLetter(c) != nullptr; }

static bool isUpper(char16_t c) {
    if (c >= 'A' && c <= 'Z') return true;
    const LKTelexLetter* m = telexLetter(c);
    return m && m->keys[0] >= 'A' && m->keys[0] <= 'Z';
}

static char16_t toLower(char16_t c) {
    if (c >= 'A' && c <= 'Z') return (char16_t)(c - 'A' + 'a');
    const LKTelexLetter* m = telexLetter(c);
    if (!m || !isUpper(c)) return c;
    for (const LKTelexLetter& n : kTelexMap) {
        if (n.tone != m->tone || n.keys[0] < 'a' || strlen(n.keys) != strlen(m->keys)) continue;
        bool same = true;
        for (size_t i = 0; m->keys[i]; i++) if ((m->keys[i] | 32) != n.keys[i]) same = false;
        if (same) return n.c;
    }
    return c;
}

static bool isAscii(const std::u16string& s) {
    for (char16_t c : s) if (c > 127) return false;
    return true;
}

// The run of letters ending at `end` in `s`.
static std::u16string wordEndingAt(const std::u16string& s, size_t end) {
    size_t i = end;
    while (i > 0 && isWordLetter(s[i - 1])) i--;
    return s.substr(i, end - i);
}

static std::u16string wordOf(const std::u16string& line) { return wordEndingAt(line, line.size()); }

// The current word: the letters at the end of the line.
static std::u16string currentWord() { return wordOf(model.line); }

// The word before the one starting at `start` on the same line, lower case: the letters before the break that ends
// it. Empty at the start of the line (a Return, or a reset after a click, arrow or app switch).
static std::u16string previousWordBefore(size_t start) {
    size_t i = start;
    while (i > 0 && !isWordLetter(model.line[i - 1]) && model.line[i - 1] != u'\n') i--;
    std::u16string w = wordEndingAt(model.line, i);
    for (char16_t& c : w) c = toLower(c);
    return w;
}

static void applyToModel(const VKEdit& e) {
    for (int i = 0; i < e.deleteCount && !model.line.empty(); i++) model.line.pop_back();
    model.line += e.text;
    if (model.line.size() > kLineTail) model.line.erase(0, model.line.size() - kLineTail);
}

// Telex keys (lower case) that type `word`: base keys, then the tone key at the end. false when a character has no
// Telex spelling.
static bool telexKeys(const std::u16string& word, std::string& keys) {
    char tone = 0;
    keys.clear();
    for (char16_t c : word) {
        if (isAsciiLetter(c)) { keys += (char)(c | 32); continue; }
        const LKTelexLetter* m = telexLetter(c);
        if (!m) return false;
        for (const char* p = m->keys; *p; p++) keys += (char)(*p | 32);
        if (m->tone) tone = m->tone;
    }
    if (tone) keys += tone;
    return true;
}

// Vietnamese word score of `word`, typed with its Telex keys; LK_VIKEY_NOT_A_WORD when it has none.
static int vietnameseScore(const std::u16string& word, Uint16* rendered, int* renderedLength) {
    std::string keys;
    if (word.empty() || !telexKeys(word, keys) || keys.size() > kMaxScoredKeys) return LK_VIKEY_NOT_A_WORD;
    return vAutoSwitchWordScore(1, keys.c_str(), rendered, renderedLength);
}

// English word score of an ASCII word (case ignored); LK_VIKEY_NOT_A_WORD for anything else.
static int englishScore(const std::u16string& word) {
    std::string lower;
    for (char16_t c : word) {
        if (c > 127) return LK_VIKEY_NOT_A_WORD;
        lower += (char)((c >= 'A' && c <= 'Z') ? c - 'A' + 'a' : c);
    }
    if (lower.empty() || lower.size() > kMaxScoredKeys) return LK_VIKEY_NOT_A_WORD;
    return vAutoSwitchWordScore(0, lower.c_str(), nullptr, nullptr);
}

// The word is a Vietnamese word and typing its Telex keys renders it (case aside), as the measured prototype
// decides it: a rendering of the same length counts.
static bool isVietnameseWord(const std::u16string& word) {
    Uint16 rendered[64];
    int length = 0;
    if (vietnameseScore(word, rendered, &length) == LK_VIKEY_NOT_A_WORD) return false;
    std::u16string shown(rendered, rendered + length), lower = word;
    for (char16_t& c : lower) if (c >= 'A' && c <= 'Z') c = (char16_t)(c - 'A' + 'a');
    return shown == lower || shown.size() == word.size();
}

// The edit that applying `first` then `second` makes.
static VKEdit composeEdits(const VKEdit& first, const VKEdit& second) {
    VKEdit e;
    const int typed = (int)first.text.size();
    if (second.deleteCount <= typed) {
        e.deleteCount = first.deleteCount;
        e.text = first.text.substr(0, typed - second.deleteCount) + second.text;
    } else {
        e.deleteCount = first.deleteCount + second.deleteCount - typed;
        e.text = second.text;
    }
    e.languageChanged = first.languageChanged || second.languageChanged;
    return e;
}

// driver->press, with the screen model following. lk_vikey_press runs the double-key repair after it; presses the
// shim makes itself (not keys the user pressed) call this directly, so the repair never touches them.
static VKEdit pressTracked(Uint16 key, bool shift, double now) {
    const std::u16string wordBefore = currentWord();
    const int languageBefore = vLanguage;
    VKEdit e = driver->press(key, shift, now);
    // Backspace always deletes in Vikey: Driver.cpp gives deleteCount 1 for vDoNothing (Vietnamese) and in English,
    // and corrected >= 1 for its undo (rememberFix requires corrected > 0); when the engine itself answers Backspace
    // it is checkGrammar(1) (Engine.cpp), which adds the deleted letter to hBPC. Should an empty edit ever come, the
    // key's native effect (VikeyEngine passes it through) deletes one character, and the model must follow.
    if (key == KEY_DELETE && e.deleteCount == 0 && e.text.empty()) e.deleteCount = 1;
    applyToModel(e);
    if (wordBefore.empty() && !currentWord().empty()) model.wordStartLanguage = languageBefore;
    if (key != KEY_DELETE) {
        model.keyBefore = model.lastKey;
        model.lastKey = key;
        model.languageAfterLastKey = vLanguage;
    }
    model.lastKeyReplaced = key != KEY_DELETE && e.deleteCount > 0;
    model.wordBeforeLastKey = wordBefore;
    return e;
}

// The keys (with Shift) that type `word` in `language`, Telex for Vietnamese. A capital letter takes Shift on all of
// its keys, and the tone key takes Shift when the letter carrying the tone is a capital, so a tone key typed next
// keeps the word's case ("HỌC" is H O C J with Shift; + S gives "HÓC"). false when a character has no keys.
static bool keyPresses(const std::u16string& word, int language, std::vector<std::pair<Uint16, bool>>& presses) {
    presses.clear();
    char tone = 0;
    bool toneShift = false;
    for (char16_t c : word) {
        const bool upper = isUpper(c);
        if (isAsciiLetter(c)) { presses.push_back({kLetterKeys[(c | 32) - 'a'], upper}); continue; }
        const LKTelexLetter* m = language == 1 ? telexLetter(c) : nullptr;
        if (!m) return false;
        for (const char* p = m->keys; *p; p++) presses.push_back({kLetterKeys[(*p | 32) - 'a'], upper});
        if (m->tone) { tone = m->tone; toneShift = upper; }
    }
    if (tone) presses.push_back({kLetterKeys[tone - 'a'], toneShift});
    return true;
}

// The engine starts over in `language` and is fed the keys of `word`, which is already on screen: typing goes on from
// it (tones, English look-back). Its output is dropped. Without keys for the word, it just starts over.
static void rebuildEngineWord(const std::u16string& word, int language, double now) {
    driver->setLanguage(language);
    driver->resetContext();
    std::vector<std::pair<Uint16, bool>> presses;
    if (!keyPresses(word, language, presses)) return;
    for (const auto& p : presses) driver->press(p.first, p.second, now);
}

// Spec 12.1: Backspace right after a doubled key that undid a mark ("học" + j + j -> "hocj") gives back the word
// from before the doubled key and keeps Vietnamese. `before` is the model before this Backspace, `e` Vikey's edit
// for it. Ported from the measured prototype (level 1). Returns true and rewrites `e` when it repairs.
static bool repairDoubleKey(const ScreenModel& before, double now, VKEdit& e) {
    if (model.wordStartLanguage != 1) return false;
    // (a) and (b): the previous key repeated the key before it and replaced letters.
    if (!before.lastKeyReplaced || before.lastKey == kNoKey || before.lastKey != before.keyBefore) return false;
    const std::u16string& snapshot = before.wordBeforeLastKey;
    if (snapshot.empty()) return false;
    // (c): the word it left is not Vietnamese.
    const std::u16string screenBefore = wordOf(before.line);
    if (isVietnameseWord(screenBefore)) return false;
    // (d): it switched a word begun in Vietnamese to English, or it marked an all-ASCII word.
    const bool flipped = before.languageAfterLastKey == 0 && model.wordStartLanguage == 1;
    if (!flipped && !isAscii(snapshot)) return false;
    // (e): an English word on screen stays unless the word before is at least as common in Vietnamese.
    const int english = englishScore(screenBefore);
    if (english != LK_VIKEY_NOT_A_WORD) {
        const int vietnamese = vietnameseScore(snapshot, nullptr, nullptr);
        if (vietnamese == LK_VIKEY_NOT_A_WORD || vietnamese < english) return false;
    }

    std::string keys;
    if (!telexKeys(snapshot, keys)) return false;
    VKEdit repair;
    repair.deleteCount = (int)currentWord().size();
    repair.text = snapshot;
    repair.languageChanged = vLanguage != 1;
    e = composeEdits(e, repair);
    applyToModel(repair);

    // The engine holds the word on screen again, in Vietnamese; its output is already on screen.
    rebuildEngineWord(snapshot, 1, now);

    model.wordStartLanguage = 1;
    model.lastKey = model.keyBefore = kNoKey;
    model.lastKeyReplaced = false;
    model.languageAfterLastKey = 1;
    return true;
}

// MARK: - Spec 12.2: fix filter, undo events, reverse undo

static const size_t kFixWordMax = sizeof(((lk_fix*)nullptr)->before) / sizeof(uint16_t);

struct Fix {
    std::u16string before, after, previous;
};

static lk_fix_filter fixFilter = nullptr;
static bool hasLastFix = false;       // Vikey's fix of the last key, which Backspace twice may still undo
static Fix lastFix;
struct Veto {
    bool active = false;
    Fix fix;
    int languageAfterFix = 1;          // vLanguage right after Vikey's fix, before the veto undid it
    int backspaces = 0;                // Backspaces since the veto
    bool capsLock = false;             // the Caps Lock rule vetoed, not the fix filter: no undo event on reverse
};
static Veto veto;
static bool hasPendingUndo = false;
static lk_undo pendingUndo;

static void forgetFixes() {
    hasLastFix = false;
    veto = Veto();
}

static void copyWord(const std::u16string& w, uint16_t* out, int* length) {
    for (size_t i = 0; i < w.size(); i++) out[i] = (uint16_t)w[i];
    *length = (int)w.size();
}

static lk_fix toC(const Fix& f) {
    lk_fix c;
    memset(&c, 0, sizeof(c));
    copyWord(f.before, c.before, &c.beforeLength);
    copyWord(f.after, c.after, &c.afterLength);
    copyWord(f.previous, c.previous, &c.previousLength);
    return c;
}

static void queueUndo(const Fix& f, bool reverse) {
    pendingUndo.fix = toC(f);
    pendingUndo.reverse = reverse ? 1 : 0;
    hasPendingUndo = true;
}

// The fix Vikey made on this key, if Backspace can undo it: rememberFix (Driver.cpp) armed the undo on this very key
// (the next key clears it), and the edit replaced the word. `before` is the word as typed, `after` the word now
// before the break character, `previous` the word before that. false for words too long for lk_fix.
static bool fixOfLastKey(const VKEdit& e, Fix& fix) {
    if (!(driver->*member(UndoActiveTag())) || driver->*member(UndoBreakGoneTag()) || e.deleteCount <= 0) return false;
    size_t end = model.line.size();
    if (end > 0 && !isWordLetter(model.line[end - 1])) end--;   // the break character
    fix.before = driver->*member(UndoTextTag());
    fix.after = wordEndingAt(model.line, end);
    fix.previous = previousWordBefore(end - fix.after.size());
    return !fix.before.empty() && !fix.after.empty() && fix.before.size() <= kFixWordMax &&
           fix.after.size() <= kFixWordMax && fix.previous.size() <= kFixWordMax;
}

// The filter kept `before`: Backspace twice undoes the fix inside the engine (the first takes the break character,
// the second puts the typed word and its language back), then the key is pressed again. `e` becomes the one edit for
// the four. Only shim presses (pressTracked): never the double-key repair (ruling P1), never another filter call.
static void vetoFix(const ScreenModel& before, Uint16 key, bool shift, double now, VKEdit& e, const Fix& fix) {
    veto = Veto();
    veto.fix = fix;
    veto.languageAfterFix = vLanguage;
    veto.active = true;
    for (int i = 0; i < 2; i++) e = composeEdits(e, pressTracked(KEY_DELETE, false, now));
    e = composeEdits(e, pressTracked(key, shift, now));
    // The model saw one key from the user.
    model.keyBefore = before.lastKey;
}

// Backspace twice right after a veto: the second one applies Vikey's fix after all, in its language. The first went
// through as a plain Backspace (the break character), so `before` is the word at the end of the line.
static bool reverseVeto(double now, VKEdit& e) {
    if (!veto.active || veto.backspaces != 1 || currentWord() != veto.fix.before) return false;
    e = VKEdit();
    e.deleteCount = (int)veto.fix.before.size();
    e.text = veto.fix.after;
    e.languageChanged = vLanguage != veto.languageAfterFix;
    applyToModel(e);
    rebuildEngineWord(veto.fix.after, veto.languageAfterFix, now);
    model.wordStartLanguage = veto.languageAfterFix;
    model.lastKey = model.keyBefore = kNoKey;
    model.lastKeyReplaced = false;
    model.languageAfterLastKey = vLanguage;
    model.wordBeforeLastKey.clear();
    if (!veto.capsLock) queueUndo(veto.fix, true);   // the undo learner never saw a Caps Lock veto
    veto = Veto();
    return true;
}

// MARK: - A word typed with Caps Lock
//
// Vikey converts an all-caps word only inside a run of capitals or when its keys double a vowel or use w (Engine.cpp,
// D23/D41): typing "BUIF" shows "BÙI", and at the break Vikey puts the keys back ("BUIF "), so an all-caps word that
// is not inside a run (the first of a line, after a number) never keeps its marks ("BÙI", "NGUYỄN"). The rule below
// applies to every word typed with Caps Lock that Vikey puts back; inside a run Vikey has already kept it. Caps Lock on for every letter is the run of
// capitals Vikey looks for, so LeanKeys keeps the Vietnamese word on the terms Vikey applies inside a run: a common
// syllable (score >= 15, Vikey's AS_CAPS_VN_FLOOR) or a Vietnamese name LeanKeys knows (lk_vikey_set_caps_words:
// "bùi" scores 3 and "nguyễn" 5 in Vikey's chat-based dictionary, as low as the acronym IRS at 6), and whose keys
// have no English reading. Acronyms (USA, IRS) and words typed with Shift held stay as Vikey decides. Backspace twice
// still gives the keys back (the veto's reverse undo).

static const int kCapsVietnameseFloor = 15;
static std::unordered_set<std::u16string> capsWords;   // lower case

// Vikey's fix `fix` of the word just finished put its raw capitals back; keep the Vietnamese word instead?
static bool capsLockKeeps(const ScreenModel& before, const Fix& fix) {
    if (!before.wordCapsLock || before.wordStartLanguage != 1) return false;
    if (fix.after.size() < 2 || fix.after.size() > kMaxScoredKeys || isAscii(fix.before)) return false;
    std::string keys;
    for (char16_t c : fix.after) {
        if (c < 'A' || c > 'Z') return false;   // the fix gave back the typed capitals
        keys += (char)(c - 'A' + 'a');
    }
    if (englishScore(fix.after) != LK_VIKEY_NOT_A_WORD) return false;
    std::u16string lower = fix.before;
    for (char16_t& c : lower) c = toLower(c);
    if (capsWords.count(lower)) return true;
    const int score = vAutoSwitchWordScore(1, keys.c_str(), nullptr, nullptr);
    return score != LK_VIKEY_NOT_A_WORD && score >= kCapsVietnameseFloor;
}

extern "C" {

int lk_vikey_init(void) {
    if (!driver) driver = new VikeyDriver();
    return driver ? 1 : 0;
}

}  // extern "C"

// Vikey's ⌫⌫ undo (D61) of a switch from English back to Vietnamese is kept only when the keys are an English word
// too ("cos " -> "có ": ⌫⌫ gives "cos" back). Keys with no English reading ("vieejt", "dduowcj") meant the Vietnamese
// word: a user deleting its last letter ("việt " ⌫⌫ to type "việc") must not be sent back to English with the keys,
// so the undo is disarmed and Backspace deletes in Vietnamese. Run right after the key, before the fix is reported.
static void keepSwitchBackUnlessEnglish(int languageBefore) {
    if (languageBefore != 0 || vLanguage != 1 || !(driver->*member(UndoActiveTag()))) return;
    if (englishScore(driver->*member(UndoTextTag())) != LK_VIKEY_NOT_A_WORD) return;
    driver->*member(UndoActiveTag()) = false;
}

// One key the user pressed: Vikey's edit with the shim's repairs, vetoes and undo bookkeeping.
static VKEdit pressUser(uint16_t macKeyCode, int shift, double now) {
    const ScreenModel before = model;
    const bool backspace = macKeyCode == KEY_DELETE;
    VKEdit e;
    if (backspace && reverseVeto(now, e)) {
        hasLastFix = false;
    } else {
        if (backspace && veto.active) veto.backspaces++;
        else veto = Veto();
        if (!backspace) hasLastFix = false;
        const int undosBefore = driver->undos;
        const bool letterKey = isLetterKey(macKeyCode);
        const int languageBefore = vLanguage;
        e = pressTracked(macKeyCode, shift != 0, now);
        if (!backspace) keepSwitchBackUnlessEnglish(languageBefore);
        if (letterKey) {
            const bool wordStarted = wordOf(before.line).empty();
            model.wordCapsLock = (wordStarted || before.wordCapsLock) && capsLockForNextKey;
        }
        if (driver->undos != undosBefore) {
            if (hasLastFix) queueUndo(lastFix, false);
            hasLastFix = false;
        }
        Fix fix;
        if (backspace) {
            if (doubleKeyFix) repairDoubleKey(before, now, e);
        } else if (fixOfLastKey(e, fix)) {
            if (capsLockKeeps(before, fix)) {
                vetoFix(before, macKeyCode, shift != 0, now, e, fix);
                veto.capsLock = true;
            } else if (fixFilter) {
                const lk_fix c = toC(fix);
                if (fixFilter(&c) == 1) vetoFix(before, macKeyCode, shift != 0, now, e, fix);
                else { lastFix = fix; hasLastFix = true; }
            } else { lastFix = fix; hasLastFix = true; }
        }
    }
    return e;
}

extern "C" {

void lk_vikey_press(uint16_t macKeyCode, int shift, double now, lk_edit* out) {
    if (!out) return;
    out->deleteCount = 0; out->length = 0; out->languageChanged = 0;
    const bool fixAtReturn = fixAtNextReturn;
    fixAtNextReturn = false;
    if (!driver) return;
    VKEdit e;
    if (fixAtReturn && (macKeyCode == KEY_RETURN || macKeyCode == KEY_ENTER) && !currentWord().empty()) {
        // Return finishes the word as Space does (Vikey checks words at Space, never at Return: D62), the Space
        // goes again, then Return. The word gets Vikey's fix and the shim's vetoes exactly as at a real Space.
        e = pressUser(KEY_SPACE, 0, now);
        e = composeEdits(e, pressTracked(KEY_DELETE, false, now));
        e = composeEdits(e, pressUser(macKeyCode, shift, now));
    } else {
        e = pressUser(macKeyCode, shift, now);
    }
    out->deleteCount = e.deleteCount;
    const int cap = (int)(sizeof(out->text) / sizeof(out->text[0]));
    const int n = e.text.size() < (size_t)cap ? (int)e.text.size() : cap;
    for (int i = 0; i < n; i++) out->text[i] = (uint16_t)e.text[i];
    out->length = n;
    out->languageChanged = e.languageChanged ? 1 : 0;
}

void lk_vikey_set_caps_lock(int on) {
    capsLockForNextKey = on != 0;
}

void lk_vikey_set_fix_at_return(int on) {
    fixAtNextReturn = on != 0;
}

void lk_vikey_set_caps_words(const uint16_t* units, int count) {
    capsWords.clear();
    std::u16string word;
    for (int i = 0; units && i <= count; i++) {
        if (i == count || units[i] == u'\n') {
            if (!word.empty()) {
                for (char16_t& c : word) c = toLower(c);
                capsWords.insert(word);
            }
            word.clear();
        } else {
            word += (char16_t)units[i];
        }
    }
}

void lk_vikey_set_fix_filter(lk_fix_filter filter) {
    fixFilter = filter;
}

int lk_vikey_take_undo(lk_undo* out) {
    if (!out || !hasPendingUndo) return 0;
    *out = pendingUndo;
    hasPendingUndo = false;
    return 1;
}

void lk_vikey_reset_context(void) {
    if (driver) driver->resetContext();
    resetModel();
    forgetFixes();   // an undo not yet taken stays: VikeyEngine resets right after Return
}

void lk_vikey_set_double_key_fix(int on) {
    doubleKeyFix = on != 0;
}

void lk_vikey_set_language(int vietnamese) {
    resetModel();
    forgetFixes();
    if (driver) driver->setLanguage(vietnamese ? 1 : 0);
    else vLanguage = vietnamese ? 1 : 0;
}

int lk_vikey_language(void) {
    return vLanguage;
}

void lk_vikey_set_options(int modernOrthography, int autoSwitch, int telexStyle) {
    vUseModernOrthography = modernOrthography ? 1 : 0;
    vAutoSwitchByTyping = autoSwitch ? 1 : 0;
    vTelexStyle = telexStyle;
    if (driver) driver->autoSwitch = autoSwitch != 0;
}

int lk_vikey_word_score(int vietnamese, const char* letters) {
    if (!letters) return LK_VIKEY_NOT_A_WORD;
    // vAutoSwitchWordScore compares lowercase keys ("a"-"z") and rejects keys of 39 or more.
    char key[40];
    int n = 0;
    for (; letters[n]; n++) {
        if (n >= (int)sizeof(key) - 1) return LK_VIKEY_NOT_A_WORD;
        char c = letters[n];
        if (c >= 'A' && c <= 'Z') c = (char)(c - 'A' + 'a');
        if (c < 'a' || c > 'z') return LK_VIKEY_NOT_A_WORD;
        key[n] = c;
    }
    if (n == 0) return LK_VIKEY_NOT_A_WORD;
    key[n] = 0;
    // The Vietnamese path replays the keys through vKeyHandleEvent, which needs the hook state vKeyInit()
    // sets up in VikeyDriver's constructor (vendor/vikey/Engine/Driver.cpp). The English path only reads
    // static tables, but initialising is idempotent and cheap.
    if (vietnamese) lk_vikey_init();
    // rendered/renderedLen may be null: the engine checks (Vikey's own VKWordScore passes nullptr).
    return vAutoSwitchWordScore(vietnamese ? 1 : 0, key, nullptr, nullptr);
}

int lk_vikey_types_as_is(const char* letters) {
    const Uint16* keys = kLetterKeys;
    if (!letters) return 0;
    char word[32];
    int n = 0;
    for (; letters[n]; n++) {
        if (n >= MAX_BUFF - 2) return 0;   // the engine's word buffer holds MAX_BUFF keys
        char c = letters[n];
        if (c >= 'A' && c <= 'Z') c = (char)(c - 'A' + 'a');
        if (c < 'a' || c > 'z') return 0;
        word[n] = c;
    }
    if (n == 0) return 0;
    lk_vikey_init();

    // The engine's per-word state is file-static in Engine.cpp (asSaveState is static, vTestSaveState exists
    // only under AS_TESTING), so only the public globals are kept; the per-word state is reset afterwards.
    const vKeyHookState hook = HookState;
    const int language = vLanguage, byTyping = vAutoSwitchByTyping, request = vAutoSwitchRequest,
              lastSide = vAutoSwitchLastSide, undoCount = vAutoSwitchUndoCount, restoredCount = vAutoSwitchRestoredCount;
    vLanguage = 1;
    vAutoSwitchByTyping = 0;
    startNewSession();

    // What would be on screen, built from the engine's output the way VikeyDriver::press applies it.
    char16_t screen[MAX_BUFF * 2];
    int len = 0;
    bool ok = true;
    for (int i = 0; i < n && ok; i++) {
        const Uint16 key = keys[word[i] - 'a'];
        vAutoSwitchRequest = -1;
        vKeyHandleEvent(vKeyEvent::Keyboard, vKeyEventState::KeyDown, key, 0, false);
        if (HookState.code == vDoNothing) {
            screen[len++] = (char16_t)keyCodeToCharacter(key);
            continue;
        }
        len -= HookState.backspaceCount;
        if (len < 0) { ok = false; break; }
        for (int c = HookState.newCharCount - 1; c >= 0; c--) {
            const Uint32 d = HookState.charData[c];
            screen[len++] = (d & CHAR_CODE_MASK) ? (char16_t)(d & 0xFFFF) : (char16_t)keyCodeToCharacter(d);
        }
        if (HookState.code == vRestore || HookState.code == vRestoreAndStartNewSession)
            screen[len++] = (char16_t)keyCodeToCharacter(key);
    }
    if (ok && len != n) ok = false;
    for (int i = 0; ok && i < n; i++) if (screen[i] != (char16_t)word[i]) ok = false;

    HookState = hook;
    vLanguage = language; vAutoSwitchByTyping = byTyping; vAutoSwitchRequest = request;
    vAutoSwitchLastSide = lastSide; vAutoSwitchUndoCount = undoCount; vAutoSwitchRestoredCount = restoredCount;
    if (driver) driver->resetContext();
    else { startNewSession(); vAutoSwitchForget(); }
    resetModel();
    forgetFixes();
    return ok ? 1 : 0;
}

}
