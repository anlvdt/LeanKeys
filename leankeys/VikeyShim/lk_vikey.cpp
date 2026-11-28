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
    std::u16string wordKeys;             // the letter keys the user pressed for the current word, with Shift case
    bool wordKeysKnown = false;          // false once a Backspace or a shim edit inside the word makes them unknown
};

static ScreenModel model;
static bool doubleKeyFix = true;
static bool capsLockForNextKey = false;   // lk_vikey_set_caps_lock, for the next lk_vikey_press
static bool fixAtNextReturn = false;      // lk_vikey_set_fix_at_return, for the next lk_vikey_press
static bool doubledKeyFlip = false;       // the current word switched to English mid-word (Vikey D19)
// Scores are 10*log10(occurrences per million): 15 = the Vietnamese reading is at least about 30 times as common.
static const int kComebackMargin = 15;

static void resetModel() { model = ScreenModel(); doubledKeyFlip = false; }

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
    std::u16string before, after, previous, keys;   // keys: the raw keys, lower case; empty when unknown
};

static lk_fix_filter fixFilter = nullptr;
static lk_convert_filter convertFilter = nullptr;
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
// Spec 5.3: a word a learned convert rule changed at its break key ("beer " shown "bể " by Vikey, typed "beer "),
// which ⌫⌫ or ⌃⌫ right after gives back as Vikey had it. Like Veto it counts the Backspaces since; any other key, a
// reset or a language change ends it. The event it makes (kind 2) is queued at once, never held (spec 8.4).
struct RuleConvert {
    bool active = false;
    Fix fix;                           // before: what Vikey showed, after: what the rule made
    std::u16string breaks;             // the break character typed after the word
    int languageBefore = 1;            // vLanguage before the rule converted
    int backspaces = 0;                // Backspaces since the conversion
};
static RuleConvert ruleConvert;
static bool hasPendingUndo = false;
static lk_undo pendingUndo;
static Uint16 lastFixKey = 0;         // the break key that made `lastFix` (⌃⌫ on the fixed word types it again)
static bool lastFixShift = false;
// Spec 12.2a: Vikey's ⌫⌫ undo of an English word it put back at the break ("tét" -> "test ", ⌫⌫ shows "tét"; a
// doubled letter: "trafic" -> "traffic "), held until the next key tells an undo from an edit (editAfterUndo): a
// letter means the user was deleting the Space and the last letter to change the word; any other key, a reset or a
// language change lets the undo stand, and only then does the learner hear of it.
struct HeldUndo {
    bool active = false;
    Fix fix;
    int backspaces = 0;                // further Backspaces after the undo
};
static HeldUndo heldUndo;
// The learning event of a ⌃⌫ (kind 1: a word Vikey left alone; kind 0: a word Vikey had just fixed, which ⌃⌫ undoes),
// held as 12.2a's: the next key the user presses, a reset or a language change releases it (the learner may take it
// then); ⌃⌫ again (a change of mind) drops it.
struct HeldConvert {
    bool active = false;
    Fix fix;
    int kind = LK_UNDO_BACKSPACE;
};
static HeldConvert heldConvert;
// The ⌃⌫ key's last conversion ("cos " -> "cos ", `shownBefore` "có", `shownAfter` "cos", `breaks` " "), kept so that ⌃⌫
// again with no other key between gives the word back as it was (`languageBefore` too). Cleared by every key the user
// presses (pressUser), by a reset and by a language change (forgetFixes). `keys` and `previous` (the word before it,
// lower case) are for the learner that hears of a conversion.
struct LastConvert {
    bool active = false;
    std::u16string shownBefore, shownAfter, breaks, keys, previous;
    int languageBefore = 1;
};
static LastConvert lastConvert;

static void copyWord(const std::u16string& w, uint16_t* out, int* length) {
    const size_t n = w.size() <= kFixWordMax ? w.size() : kFixWordMax;
    for (size_t i = 0; i < n; i++) out[i] = (uint16_t)w[i];
    *length = (int)n;
}

static lk_fix toC(const Fix& f) {
    lk_fix c;
    memset(&c, 0, sizeof(c));
    copyWord(f.before, c.before, &c.beforeLength);
    copyWord(f.after, c.after, &c.afterLength);
    copyWord(f.previous, c.previous, &c.previousLength);
    if (f.keys.size() <= kFixWordMax) copyWord(f.keys, c.keys, &c.keysLength);   // longer: unknown
    return c;
}

static void queueUndo(const Fix& f, bool reverse, int kind = LK_UNDO_BACKSPACE) {
    pendingUndo.fix = toC(f);
    pendingUndo.reverse = reverse ? 1 : 0;
    pendingUndo.kind = kind;
    hasPendingUndo = true;
}

// A held undo stands: the learner may take it now.
static void releaseHeldUndo() {
    if (heldUndo.active) queueUndo(heldUndo.fix, false);
    heldUndo = HeldUndo();
}

// A held ⌃⌫ event stands: the learner may take it now.
static void releaseHeldConvert() {
    if (heldConvert.active) queueUndo(heldConvert.fix, false, heldConvert.kind);
    heldConvert = HeldConvert();
}

static void forgetFixes() {
    hasLastFix = false;
    veto = Veto();
    ruleConvert = RuleConvert();
    releaseHeldUndo();
    releaseHeldConvert();
    lastConvert = LastConvert();
}

static void rememberLastFix(const Fix& fix, Uint16 key, bool shift) {
    lastFix = fix;
    hasLastFix = true;
    lastFixKey = key;
    lastFixShift = shift;
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
    fix.keys.clear();
    if (model.wordKeysKnown) {
        for (char16_t c : model.wordKeys) fix.keys += toLower(c);
    }
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

// MARK: - A doubled tone key inside an unknown word
//
// Telex users double a tone key to type the letter itself: "dess" shows "des", and the word goes on in English
// ("desskin" shows "deskin"). At the break Vikey (D19, vAutoSwitchFixDoubledKey) puts every key back ("desskin ")
// when neither spelling is an English word and the keys have two vowel groups, which it reads as a literal it must
// keep as typed. For a lower-case word (a capital first letter at most) that turns the user's "ss" into two letters,
// so LeanKeys keeps what the screen showed, as Gõ Nhanh does. English words ("boss", "classic"), identifiers with an
// inner capital ("getUserss") and words typed in capitals stay as Vikey decides. Backspace twice still gives the keys
// back (the veto's reverse undo).

static bool isToneKey(char16_t c) {
    c = (char16_t)(c | 32);
    return c == 's' || c == 'f' || c == 'r' || c == 'x' || c == 'j';
}

// Vikey's fix `fix` of the word just finished, right after a doubled key, put back the doubled tone key the screen
// showed once: keep the word as shown instead?
static bool doubledToneKeyKeeps(const Fix& fix) {
    const std::u16string& shown = fix.before, &keys = fix.after;
    if (keys.size() != shown.size() + 1 || shown.size() < 2) return false;
    for (size_t i = 0; i < keys.size(); i++) {
        if (!isAsciiLetter(keys[i])) return false;
        if (i > 0 && isUpper(keys[i])) return false;
    }
    size_t i = 0;
    while (i < shown.size() && shown[i] == keys[i]) i++;
    if (keys.compare(i + 1, std::u16string::npos, shown, i, std::u16string::npos) != 0) return false;
    // The key that went is a tone key next to the same letter: one of a doubled pair.
    if (!isToneKey(keys[i])) return false;
    // The pair: keys[pair] and keys[pair + 1]. The scan above stops at the first of two equal letters.
    size_t pair;
    if (i + 1 < keys.size() && (keys[i + 1] | 32) == (keys[i] | 32)) pair = i;
    else if (i > 0 && (keys[i - 1] | 32) == (keys[i] | 32)) pair = i - 1;
    else return false;
    if (englishScore(keys) != LK_VIKEY_NOT_A_WORD || englishScore(shown) != LK_VIKEY_NOT_A_WORD) return false;
    // An English word with both letters of the pair inside the keys ("mirror" in "mirrorless", "miss" in
    // "missworld"): an English compound Vikey does not list, typed as spelled. Vikey keeps it.
    for (size_t start = 0; start <= pair; start++) {
        for (size_t end = pair + 2; end <= keys.size(); end++) {
            if (end - start >= 4 && englishScore(keys.substr(start, end - start)) != LK_VIKEY_NOT_A_WORD) return false;
        }
    }
    return true;
}

// MARK: - Final k in place names
//
// Central Highlands names write final c as k: Đắk Lắk, Đắk Nông, Đăk Glei, Krông Búk. Vikey has no syllable with a
// final k (only teencode "ừk"), so at the break it puts the keys back as a wrong spelling ("ddawsk ", "lawsk "),
// staying in Vietnamese and arming no ⌫⌫ undo. LeanKeys keeps the word on screen when its keys are no English word
// and the same word with c ("đắc", "lắc"; with a sắc tone when it has none: "đăk" -> "đắc") is Vietnamese.
// Backspace twice still gives the keys back (the veto's reverse undo).

static bool hasTone(const std::u16string& word) {
    for (char16_t c : word) {
        const LKTelexLetter* m = telexLetter(c);
        if (m && m->tone) return true;
    }
    return false;
}

// `shown` (the word on screen before the break) came back as `keys`: keep `shown`?
static bool finalKKeeps(const std::u16string& shown, const std::u16string& keys) {
    if (shown.size() < 2 || shown.size() > kFixWordMax || keys.size() > kFixWordMax || isAscii(shown)) return false;
    if ((shown.back() | 32) != 'k' || !isAscii(keys) || englishScore(keys) != LK_VIKEY_NOT_A_WORD) return false;
    // The syllable is well formed: with another stop final in place of k it is a word ("búk" -> "bút"; Vikey's
    // dictionary has no "búc").
    for (const char16_t* final : {u"c", u"t", u"p", u"ch"}) {
        std::u16string word = shown.substr(0, shown.size() - 1) + final;
        std::string telex;
        if (!telexKeys(word, telex) || telex.size() + 1 > kMaxScoredKeys) continue;
        if (vAutoSwitchWordScore(1, telex.c_str(), nullptr, nullptr) != LK_VIKEY_NOT_A_WORD) return true;
        if (hasTone(word)) continue;
        telex += 's';
        if (vAutoSwitchWordScore(1, telex.c_str(), nullptr, nullptr) != LK_VIKEY_NOT_A_WORD) return true;
    }
    return false;
}

// A tone key typed after the final k ("ddawks", "lawks", "bukj"): Vikey cannot put the tone on the word any more and
// shows it as a letter ("đăks"). The word with the tone on its last vowel ("đắk", as every closed syllable takes it),
// or empty when `shown` is not a consonant, a vowel, a final k and one tone key.
static std::u16string toneAfterFinalK(const std::u16string& shown) {
    if (shown.size() < 3) return u"";
    const char16_t toneKey = shown.back();
    const char tone = (char)(toneKey | 32);
    if (toneKey > 127 || (tone != 's' && tone != 'f' && tone != 'r' && tone != 'x' && tone != 'j')) return u"";
    std::u16string base = shown.substr(0, shown.size() - 1);
    if ((base.back() | 32) != 'k' || hasTone(base)) return u"";
    // A consonant first, as in every such name ("oks" is no word to mark).
    const char16_t first = (char16_t)(isAsciiLetter(base[0]) ? (base[0] | 32) : 'd');   // đ/Đ is the one non-ASCII
    if (first == 'a' || first == 'e' || first == 'i' || first == 'o' || first == 'u' || first == 'y' ||
        (!isAsciiLetter(base[0]) && base[0] != 0x111 && base[0] != 0x110)) return u"";
    for (size_t i = base.size(); i-- > 0;) {
        const char16_t c = base[i];
        std::string keys;
        if (isAsciiLetter(c)) keys = std::string(1, (char)c);
        else if (const LKTelexLetter* m = telexLetter(c)) keys = m->keys;
        else return u"";
        const char first = (char)(keys[0] | 32);
        if (first != 'a' && first != 'e' && first != 'i' && first != 'o' && first != 'u' && first != 'y') continue;
        for (const LKTelexLetter& m : kTelexMap) {
            if (m.tone == tone && keys == m.keys) { base[i] = m.c; return base; }
        }
        return u"";
    }
    return u"";
}

// The break key's edit `e` (made after the model `before`) ends with `word` on screen in place of the word `shown`
// there before the key, then the break characters `breakText`. Backspace twice gives `keys` back, in English.
static void showAtBreak(const ScreenModel& before, VKEdit& e, const std::u16string& shown, const std::u16string& word,
                        const std::u16string& keys, const std::u16string& breakText) {
    e.deleteCount = word == shown ? 0 : (int)shown.size();
    e.text = (word == shown ? u"" : word) + breakText;
    model.line = before.line;
    applyToModel(e);
    veto = Veto();
    veto.fix.before = word;
    veto.fix.after = keys;
    veto.fix.previous = previousWordBefore(before.line.size() - shown.size());
    veto.languageAfterFix = 0;   // the keys come back as typed, in English (as Vikey types them there)
    veto.active = true;
    veto.capsLock = true;   // the shim's own rule: no undo event on reverse
}

// A break key in Vietnamese replaced the word on screen with its keys: keep a place name with a final k instead.
// `before` is the model before the key, `e` Vikey's edit for it. Returns true and rewrites `e` when it keeps.
static bool keepFinalK(const ScreenModel& before, VKEdit& e) {
    const std::u16string shown = wordOf(before.line);
    if (shown.empty() || e.deleteCount != (int)shown.size()) return false;
    size_t n = 0;
    while (n < e.text.size() && isAsciiLetter(e.text[n])) n++;
    const std::u16string keys = e.text.substr(0, n), rest = e.text.substr(n);
    for (char16_t c : rest) if (isWordLetter(c)) return false;
    if (keys.empty()) return false;
    // "đăks" (tone typed after the k) becomes "đắk".
    const std::u16string word = (shown.back() | 32) == 'k' ? shown : toneAfterFinalK(shown);
    if (word.empty() || !finalKKeeps(word, keys)) return false;
    showAtBreak(before, e, shown, word, keys, rest);
    return true;
}

// Vikey left a word with a tone key after the final k as plain letters ("bukj "): put the tone on it ("bụk ").
static bool toneFinalKAtBreak(const ScreenModel& before, VKEdit& e) {
    const std::u16string shown = wordOf(before.line);
    if (shown.empty() || e.deleteCount != 0 || !isAscii(shown)) return false;
    for (char16_t c : e.text) if (isWordLetter(c)) return false;
    const std::u16string word = toneAfterFinalK(shown);
    if (word.empty() || !finalKKeeps(word, shown)) return false;
    showAtBreak(before, e, shown, word, shown, e.text);
    return true;
}

// MARK: - Initial kr in place names
//
// Krông Búk, Krông Pắc, Krông Ana: Vikey has no initial kr, so it types the rest of the word as plain letters
// ("kroong") and leaves it at the break. LeanKeys types the rest at the break as it would after c ("coong" ->
// "công") and puts kr back in front: "Krông". Only for keys that are no English word, a lower-case rest, and a rest
// that the Telex keys change.
static bool typeInitialKr(const ScreenModel& before, VKEdit& e) {
    const std::u16string shown = wordOf(before.line);
    if (shown.size() < 3 || shown.size() > kFixWordMax || e.deleteCount != 0 || !isAscii(shown)) return false;
    if ((shown[0] | 32) != 'k' || (shown[1] | 32) != 'r') return false;
    for (char16_t c : e.text) if (isWordLetter(c)) return false;
    if (englishScore(shown) != LK_VIKEY_NOT_A_WORD) return false;
    std::string telex = "c";
    for (size_t i = 2; i < shown.size(); i++) {
        if (shown[i] < 'a' || shown[i] > 'z') return false;
        telex += (char)shown[i];
    }
    if (telex.size() > kMaxScoredKeys) return false;
    Uint16 rendered[64];
    int length = 0;
    if (vAutoSwitchWordScore(1, telex.c_str(), rendered, &length) == LK_VIKEY_NOT_A_WORD || length < 2) return false;
    if (rendered[0] != u'c') return false;
    const std::u16string word = shown.substr(0, 2) + std::u16string(rendered + 1, rendered + length);
    if (word == shown) return false;
    showAtBreak(before, e, shown, word, shown, e.text);
    return true;
}

// MARK: - The word after Krông, or after M' / H' / R'
//
// Telex joins a vowel typed after a final consonant to the vowel before it ("ana" -> "ân"), and Vikey keeps "Ân"
// (more common than "ana"); after an apostrophe it starts a new word and reads "gar" as "gả". Right after a word with
// the initial kr (Krông, which the shim typed), or glued to one letter and an apostrophe (Cư M'gar, Ea H'Leo, Đắk
// R'Lấp), the word is part of a place or people's name: Krông Ana, M'gar. When the keys of that word are an English
// (or name) word and the screen shows something else, the keys come back ("laaps" is none, so R'Lấp stays).
// Backspace twice gives Vikey's word back.

// The word starting at `start` in `line` is glued to one letter and an apostrophe at the start of a word ("M'gar").
static bool afterLetterApostrophe(const std::u16string& line, size_t start) {
    if (start < 2 || (line[start - 1] != u'\'' && line[start - 1] != u'\u2019') || !isAsciiLetter(line[start - 2]))
        return false;
    return start == 2 || !isWordLetter(line[start - 3]);
}

static bool keepKeysAfterKr(const ScreenModel& before, VKEdit& e) {
    const std::u16string shown = wordOf(before.line);
    if (shown.empty() || e.deleteCount != 0 || !before.wordKeysKnown) return false;
    for (char16_t c : e.text) if (isWordLetter(c)) return false;
    const std::u16string& keys = before.wordKeys;
    if (keys.empty() || keys == shown || keys.size() > kFixWordMax || shown.size() > kFixWordMax) return false;
    const size_t start = before.line.size() - shown.size();
    const std::u16string previous = previousWordBefore(start);
    const bool afterKr = previous.size() >= 3 && previous[0] == u'k' && previous[1] == u'r' && !isAscii(previous);
    if (!afterKr && !afterLetterApostrophe(before.line, start)) return false;
    if (englishScore(keys) == LK_VIKEY_NOT_A_WORD) return false;
    showAtBreak(before, e, shown, keys, keys, e.text);
    veto.fix.after = shown;      // Backspace twice gives "Ân" back, in Vietnamese
    veto.languageAfterFix = 1;
    return true;
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

// The last word on the line, before any break characters after it: a Return that just ended the word counts as its
// break (one newline), an earlier line does not.
static std::u16string lastWord() {
    size_t end = model.line.size();
    if (end > 0 && model.line[end - 1] == u'\n') end--;
    while (end > 0 && !isWordLetter(model.line[end - 1]) && model.line[end - 1] != u'\n') end--;
    return wordEndingAt(model.line, end);
}

// Vikey D19: a doubled tone key switches to English mid-word and shows the Telex result ("lamff" -> "lamf", "verr"
// -> "ver"). The screen stays as D19 shows it; only the language is the shim's business. When the word ends and what
// it shows is no English word ("lamf", "bij", "nguowif"), the doubled key was a Vietnamese typo, not English, so
// Vietnamese comes back: the words after it are no longer typed in English. "ver", "boss", "mix" stay English.
static void comeBackAfterDoubledKey(uint16_t key, int shift, int languageBefore, VKEdit& e) {
    if (key == KEY_DELETE) {
        // The user is correcting: what the word shows is no longer D19's result and tells nothing (an English word
        // with an extra letter, "thiss" ⌫ -> "thi", is not a Vietnamese typo). Vikey's language stands.
        doubledKeyFlip = false;
        return;
    }
    if (isLetterKey(key)) {
        if (languageBefore == 1 && vLanguage == 0) doubledKeyFlip = true;
        return;
    }
    // A digit glued to the word ("cass1") is part of an identifier, not the end of a word (as in Driver.cpp).
    if (!shift && (key == KEY_0 || key == KEY_1 || key == KEY_2 || key == KEY_3 || key == KEY_4 || key == KEY_5 ||
                   key == KEY_6 || key == KEY_7 || key == KEY_8 || key == KEY_9)) {
        doubledKeyFlip = false;
        return;
    }
    const bool flipped = doubledKeyFlip;
    doubledKeyFlip = false;
    if (!flipped || vLanguage != 0 || !currentWord().empty()) return;
    const std::u16string word = lastWord();
    if (word.empty()) return;
    // An English word too stays English, unless its Telex reading is far more common Vietnamese ("cos" / "có",
    // "nos" / "nó"): the doubled key was then a typo, not English. "its" / "ít", "mix" / "mĩ" stay English.
    const int english = englishScore(word);
    if (english != LK_VIKEY_NOT_A_WORD) {
        const int vietnamese = vietnameseScore(word, nullptr, nullptr);
        if (vietnamese == LK_VIKEY_NOT_A_WORD || vietnamese - english < kComebackMargin) return;
    }
    // As VikeyDriver::switchTo does at its own switches (private there): the next word starts fresh, in Vietnamese.
    // Not driver->setLanguage, whose resetContext would drop a ⌫⌫ undo Vikey armed at this break (D19's dictionary
    // fix): that undo still gives the keys back, in English.
    vLanguage = 1;
    startNewSession();
    vAutoSwitchForget();
    e.languageChanged = true;
    model.languageAfterLastKey = 1;
}

// A letter right after Vikey's ⌫⌫ undo of an English word it put back (`heldUndo`): the user was not undoing but
// deleting the Space and the word's last letter (and one more letter per further Backspace) to change the word.
// "test " ⌫⌫ shows "tét" and "t" would give "tétt"; plain Backspaces give "tes", and the letter goes on from it in
// English, the word's language after the fix. `e` becomes the edit that puts that word on screen; the learner never
// hears of the undo. false (nothing done) when the word on screen is not the undone word Backspace left.
static bool editAfterUndo(double now, VKEdit& e) {
    const HeldUndo held = heldUndo;
    const std::u16string& typed = held.fix.after;
    const size_t deleted = 1 + (size_t)held.backspaces;
    const std::u16string word = currentWord();
    const size_t shown = held.fix.before.size() > (size_t)held.backspaces ? held.fix.before.size() - held.backspaces : 0;
    if (typed.size() <= deleted || word.size() != shown) return false;
    const std::u16string kept = typed.substr(0, typed.size() - deleted);
    heldUndo = HeldUndo();
    const int languageBefore = vLanguage;
    e = VKEdit();
    e.deleteCount = (int)word.size();
    e.text = kept;
    applyToModel(e);
    rebuildEngineWord(kept, 0, now);
    e.languageChanged = vLanguage != languageBefore;
    model.wordStartLanguage = 0;
    model.lastKey = model.keyBefore = kNoKey;
    model.lastKeyReplaced = false;
    model.languageAfterLastKey = vLanguage;
    model.wordBeforeLastKey.clear();
    model.wordKeys = kept;
    model.wordKeysKnown = true;
    doubledKeyFlip = false;
    return true;
}

// MARK: - ⌃⌫: convert the last word
//
// ⌃⌫ turns the last word into its raw keys when it shows a Telex form ("có" -> "cos", "bể" -> "beer", "mĩ" -> "mix") and
// into the Telex form of its keys when it shows them as typed ("pus" -> "pú"). The word after a break or being typed
// alike: the break characters after it are typed again.

static bool isBreakChar(char16_t c) {
    switch (c) {
        case u' ': case u',': case u'.': case u';': case u'?': case u'!': case u')': case u']': case u'"': case u'\'':
        case u'”': return true;
        default: return false;
    }
}

// What typing `keys` (Telex, lower case = no Shift) shows in Vietnamese with auto switch off, as lk_vikey_types_as_is
// replays it: "pus" -> "pú", "Cos" -> "Có", "sdt" -> "sdt". false when the engine's output cannot be followed. The
// driver (⌫⌫ undo, English look-back) is copied and put back, and the engine's globals are kept; the engine's own
// per-word state is out of reach (vendor/ is untouched), so it starts a fresh word, which is what it holds after a
// break. A caller with no break (the word being typed) puts its word back with rebuildEngineWord.
static bool renderTelex(const std::u16string& keys, std::u16string& shown) {
    shown.clear();
    if (keys.empty() || keys.size() >= (size_t)MAX_BUFF - 2) return false;
    std::vector<std::pair<Uint16, bool>> presses;
    for (char16_t c : keys) {
        if (!isAsciiLetter(c)) return false;
        presses.push_back({kLetterKeys[(c | 32) - 'a'], c >= 'A' && c <= 'Z'});
    }
    const VikeyDriver savedDriver = *driver;
    const vKeyHookState hook = HookState;
    const int language = vLanguage, byTyping = vAutoSwitchByTyping, request = vAutoSwitchRequest,
              lastSide = vAutoSwitchLastSide, undoCount = vAutoSwitchUndoCount, restoredCount = vAutoSwitchRestoredCount;
    vLanguage = 1;
    vAutoSwitchByTyping = 0;
    startNewSession();
    char16_t screen[MAX_BUFF * 2];
    int len = 0;
    bool ok = true;
    for (const auto& p : presses) {
        vAutoSwitchRequest = -1;
        vKeyHandleEvent(vKeyEvent::Keyboard, vKeyEventState::KeyDown, p.first, p.second ? 1 : 0, false);
        const Uint32 caps = p.second ? CAPS_MASK : 0;
        if (HookState.code == vDoNothing) {
            if (len >= (int)(sizeof(screen) / sizeof(screen[0]))) { ok = false; break; }
            screen[len++] = (char16_t)keyCodeToCharacter(p.first | caps);
            continue;
        }
        len -= HookState.backspaceCount;
        if (len < 0 || len + HookState.newCharCount + 1 > (int)(sizeof(screen) / sizeof(screen[0]))) { ok = false; break; }
        for (int c = HookState.newCharCount - 1; c >= 0; c--) {
            const Uint32 d = HookState.charData[c];
            screen[len++] = (d & CHAR_CODE_MASK) ? (char16_t)(d & 0xFFFF) : (char16_t)keyCodeToCharacter(d);
        }
        if (HookState.code == vRestore || HookState.code == vRestoreAndStartNewSession)
            screen[len++] = (char16_t)keyCodeToCharacter(p.first | caps);
    }
    if (ok) shown.assign(screen, screen + len);
    HookState = hook;
    vLanguage = language; vAutoSwitchByTyping = byTyping; vAutoSwitchRequest = request;
    vAutoSwitchLastSide = lastSide; vAutoSwitchUndoCount = undoCount; vAutoSwitchRestoredCount = restoredCount;
    *driver = savedDriver;
    startNewSession();
    return ok;
}

// `e` replaces `target` and the `breaks` after it by `newWord` and the same breaks, in `newLanguage`, and the engine
// and the model follow. Without breaks the word is still being typed, so the engine holds it in the new language
// (rebuildEngineWord); after breaks it is finished, and the language switch is Vikey's own (comeBackAfterDoubledKey:
// the next word starts fresh, nothing dropped). A fix Vikey armed for ⌫⌫ is dropped: it belongs to the old word.
static void moveWord(const std::u16string& target, const std::u16string& newWord, const std::u16string& breaks,
                     int newLanguage, double now, VKEdit& e) {
    const int languageBefore = vLanguage;
    e = VKEdit();
    e.deleteCount = (int)(target.size() + breaks.size());
    e.text = newWord + breaks;
    applyToModel(e);
    if (breaks.empty()) {
        rebuildEngineWord(newWord, newLanguage, now);
    } else {
        driver->*member(UndoActiveTag()) = false;
        vLanguage = newLanguage;
        startNewSession();
        vAutoSwitchForget();
    }
    e.languageChanged = vLanguage != languageBefore;
    hasLastFix = false;
    veto = Veto();
    ruleConvert = RuleConvert();
    heldUndo = HeldUndo();
    doubledKeyFlip = false;
    model.wordStartLanguage = newLanguage;
    model.lastKey = model.keyBefore = kNoKey;
    model.lastKeyReplaced = false;
    model.languageAfterLastKey = vLanguage;
    model.wordBeforeLastKey.clear();
    model.wordCapsLock = false;
}

static std::u16string lowerCase(std::u16string s) {
    for (char16_t& c : s) c = toLower(c);
    return s;
}

// What converting `target` (the word on screen, `breaks` after it) gives, from the raw `keys` that typed it: the keys
// when it shows something else, the Telex form of the keys when it shows them as typed. false when that makes no other
// word (the engine is then at a fresh word, or holds `target` again when there are no breaks).
static bool decideConvert(const std::u16string& target, const std::u16string& keys, const std::u16string& breaks,
                          double now, std::u16string& newWord, int& newLanguage) {
    newLanguage = 0;
    if (lowerCase(target) == lowerCase(keys)) {
        newLanguage = 1;
        const bool rendered = renderTelex(keys, newWord);
        if (!rendered || newWord == target) {
            // renderTelex left the engine at a fresh word; with no break the word still on screen is the one it holds.
            if (breaks.empty()) rebuildEngineWord(target, vLanguage, now);
            return false;
        }
    } else {
        newWord = keys;
    }
    return newWord != target;
}

// Convert `target` as decideConvert says, and move the engine and the model. `hold`: the conversion is a learning
// event (kind 1), held for the next key.
static bool convertWord(const std::u16string& target, const std::u16string& keys, const std::u16string& breaks,
                        bool hold, double now, VKEdit& e) {
    if (target.size() > kFixWordMax || keys.size() > kFixWordMax) {
        if (breaks.empty()) rebuildEngineWord(target, vLanguage, now);
        return false;
    }
    std::u16string newWord;
    int newLanguage = 0;
    if (!decideConvert(target, keys, breaks, now, newWord, newLanguage)) return false;
    if (newWord.size() > kFixWordMax) {
        if (breaks.empty()) rebuildEngineWord(target, vLanguage, now);
        return false;
    }
    const int languageBefore = vLanguage;
    LastConvert done;
    done.active = true;
    done.shownBefore = target;
    done.shownAfter = newWord;
    done.breaks = breaks;
    done.keys = keys;
    done.previous = previousWordBefore(model.line.size() - breaks.size() - target.size());
    done.languageBefore = languageBefore;
    moveWord(target, newWord, breaks, newLanguage, now, e);
    lastConvert = done;
    releaseHeldConvert();
    if (hold) {
        heldConvert.active = true;
        heldConvert.kind = LK_UNDO_CONVERT;
        heldConvert.fix.before = target;
        heldConvert.fix.after = newWord;
        heldConvert.fix.previous = done.previous.size() <= kFixWordMax ? done.previous : std::u16string();
        heldConvert.fix.keys = lowerCase(keys);
    }
    return true;
}

// ⌃⌫ or the second Backspace right after a rule converted a word: Vikey's word comes back in its language, and the
// learner hears of the change of mind (kind 2) at once. `e` is the edit, with `deleteExtra` characters of the word's
// tail already off the screen (the break character a Backspace took). false when the screen is not as the rule left it.
static bool reverseRuleConvert(double now, size_t deleteExtra, VKEdit& e) {
    if (!ruleConvert.active) return false;
    const RuleConvert r = ruleConvert;
    ruleConvert = RuleConvert();
    const std::u16string tail = r.fix.after + r.breaks.substr(0, r.breaks.size() - deleteExtra);
    if (model.line.size() < tail.size() || model.line.compare(model.line.size() - tail.size(), tail.size(), tail) != 0)
        return false;
    // The breaks still on screen go with the word and come back with it.
    const std::u16string kept = r.breaks.substr(0, r.breaks.size() - deleteExtra);
    moveWord(r.fix.after, r.fix.before, kept, r.languageBefore, now, e);
    // Any held ⌃⌫ event was released before a rule could convert, so this is the one event in the slot (spec 8.4).
    queueUndo(r.fix, true, LK_UNDO_RULE_REVERSE);
    return true;
}

// The raw keys of the word just typed (model.wordKeys), each with the case of the letter it types. Caps Lock gives
// lower-case keys for capitals on screen ("COS" is c, o, s with Caps Lock), so every key of a word typed with it is a
// capital; otherwise a key takes the case of the letter shown at its position.
static std::u16string casedWordKeys(const std::u16string& target) {
    std::u16string keys = model.wordKeys;
    for (size_t i = 0; i < keys.size(); i++) {
        if (model.wordCapsLock || (i < target.size() && isUpper(target[i]))) keys[i] = (char16_t)(keys[i] & ~32);
    }
    return keys;
}

// ⌃⌫ on the word Vikey fixed at the last key ("cos " -> "có "): Vikey's own undo, inside the engine as vetoFix does it
// (Backspace twice: the break character goes, then the typed word and its language come back), and the break typed
// again; one edit. Vikey's fix is a ⌫⌫ undo to the learner: a kind 0 event for `lastFix`, held for the next key, and
// ⌃⌫ again gives the fix back like any conversion. false (nothing done) when the word is not the one Vikey fixed.
static bool undoLastFix(const std::u16string& target, const std::u16string& breaks, bool hold, double now, VKEdit& e) {
    if (!hasLastFix || breaks.size() != 1 || target != lastFix.after) return false;
    const Fix fix = lastFix;
    const Uint16 key = lastFixKey;
    const bool shift = lastFixShift;
    const int languageBefore = vLanguage;
    const std::u16string previous = fix.previous;
    e = VKEdit();
    for (int i = 0; i < 2; i++) e = composeEdits(e, pressTracked(KEY_DELETE, false, now));
    e = composeEdits(e, pressTracked(key, shift, now));
    e.languageChanged = vLanguage != languageBefore;
    // The undo is done: nothing of Vikey's armed for ⌫⌫ belongs to the word any more.
    driver->*member(UndoActiveTag()) = false;
    hasLastFix = false;
    veto = Veto();
    heldUndo = HeldUndo();
    doubledKeyFlip = false;
    model.lastKey = model.keyBefore = kNoKey;
    model.lastKeyReplaced = false;
    model.languageAfterLastKey = vLanguage;
    model.wordBeforeLastKey.clear();
    LastConvert done;
    done.active = true;
    done.shownBefore = fix.after;
    done.shownAfter = fix.before;
    done.breaks = breaks;
    done.keys = fix.keys;
    done.previous = previous;
    done.languageBefore = languageBefore;
    lastConvert = done;
    releaseHeldConvert();
    if (hold) {
        heldConvert.active = true;
        heldConvert.kind = LK_UNDO_BACKSPACE;
        heldConvert.fix = fix;
    }
    return true;
}

// ⌃⌫: the word before the break characters at the end of the line, converted as above. false when there is none.
static bool convertLastWord(double now, VKEdit& e) {
    // Right after a learned rule converted the word: ⌃⌫ is a change of mind (spec 5.3).
    if (ruleConvert.active && reverseRuleConvert(now, 0, e)) return true;
    ruleConvert = RuleConvert();
    if (lastConvert.active) {
        // Again, no key between: back to the word and language from before.
        const LastConvert c = lastConvert;
        const std::u16string tail = c.shownAfter + c.breaks;
        if (model.line.size() >= tail.size() && model.line.compare(model.line.size() - tail.size(), tail.size(), tail) == 0) {
            moveWord(c.shownAfter, c.shownBefore, c.breaks, c.languageBefore, now, e);
            lastConvert = LastConvert();
            heldConvert = HeldConvert();   // a change of mind: nothing to learn
            return true;
        }
        lastConvert = LastConvert();
    }
    size_t end = model.line.size();
    while (end > 0 && isBreakChar(model.line[end - 1])) end--;
    const std::u16string breaks = model.line.substr(end);
    const std::u16string target = wordEndingAt(model.line, end);
    if (target.empty() || target.size() > kFixWordMax || breaks.size() > kFixWordMax) return false;
    // While a 12.2a undo is held, ⌃⌫ drops it (moveWord clears it) and nothing is held in its place.
    const bool hold = !heldUndo.active;
    if (undoLastFix(target, breaks, hold, now, e)) return true;

    // The keys that typed it: the record of the last word typed, else the word itself when it is plain letters, else
    // its Telex keys, each with the case of the letter it types.
    std::u16string keys;
    if (heldUndo.active && heldUndo.backspaces == 0 && target == heldUndo.fix.before) {
        // ⌫⌫ just showed the word as Vikey had it ("tét"): the keys are the word it put back ("test").
        keys = heldUndo.fix.after;
    } else if (model.wordKeysKnown && !model.wordKeys.empty()) {
        keys = casedWordKeys(target);
    } else if (isAscii(target)) {
        keys = target;
    } else {
        std::vector<std::pair<Uint16, bool>> presses;
        if (!keyPresses(target, 1, presses)) return false;
        for (const auto& p : presses) {
            for (size_t k = 0; k < 26; k++) if (kLetterKeys[k] == p.first) keys += (char16_t)((p.second ? 'A' : 'a') + k);
        }
    }
    if (keys.empty() || keys.size() > kFixWordMax) return false;
    return convertWord(target, keys, breaks, hold, now, e);
}

// The break key `e` just typed ended a word Vikey left alone: ask the convert filter (spec 5.2) and, on 1, make `e` the
// one edit that types the converted word and the break (the break is not on screen yet, so one character less is
// deleted than moveWord counts) and arm ruleConvert. `languageBefore`: vLanguage before the key. Nothing happens
// (the engine untouched) unless the keys of a plain word before a single break character are known.
static void convertAtBreak(int languageBefore, double now, VKEdit& e) {
    if (e.deleteCount != 0 || e.text.size() != 1 || model.line.empty() || !model.wordKeysKnown ||
        model.wordKeys.empty() || model.line.back() != e.text[0] || !isBreakChar(e.text[0])) return;
    const size_t end = model.line.size() - 1;
    const std::u16string target = wordEndingAt(model.line, end);
    if (target.empty() || target.size() > kFixWordMax) return;
    const std::u16string keys = casedWordKeys(target);
    if (keys.size() > kFixWordMax) return;
    const std::u16string breaks = e.text;
    // The engine is never replayed to ask the filter (renderTelex cannot give back the engine's own state, which ⌫ over
    // the break still needs): `after` is the keys when the word shows something else, and left empty when the
    // conversion is the Telex form of the keys, which only renders once the filter said 1.
    const bool toTelex = lowerCase(target) == lowerCase(keys);
    Fix fix;
    fix.before = target;
    if (!toTelex) fix.after = keys;
    fix.previous = previousWordBefore(end - target.size());
    fix.keys = lowerCase(keys);
    if (fix.previous.size() > kFixWordMax) fix.previous.clear();
    const lk_fix c = toC(fix);
    if (convertFilter(&c) != 1) return;
    std::u16string newWord;
    int newLanguage = 0;
    if (!decideConvert(target, keys, breaks, now, newWord, newLanguage) || newWord.size() > kFixWordMax) return;
    fix.after = newWord;
    const int languageNow = vLanguage;
    const bool capsLock = model.wordCapsLock;
    moveWord(target, newWord, breaks, newLanguage, now, e);
    e.deleteCount -= (int)breaks.size();
    e.languageChanged = vLanguage != languageBefore;
    model.wordCapsLock = capsLock;
    ruleConvert.active = true;
    ruleConvert.fix = fix;
    ruleConvert.breaks = breaks;
    ruleConvert.languageBefore = languageNow;
}

static VKEdit pressUserKey(uint16_t macKeyCode, int shift, double now);

// One key the user pressed: Vikey's edit with the shim's repairs, vetoes and undo bookkeeping.
static VKEdit pressUser(uint16_t macKeyCode, int shift, double now) {
    lastConvert = LastConvert();
    releaseHeldConvert();
    if (heldUndo.active) {
        VKEdit edit;
        if (macKeyCode == KEY_DELETE) heldUndo.backspaces++;
        else if (isLetterKey(macKeyCode) && editAfterUndo(now, edit)) return composeEdits(edit, pressUserKey(macKeyCode, shift, now));
        else releaseHeldUndo();
    }
    return pressUserKey(macKeyCode, shift, now);
}

static VKEdit pressUserKey(uint16_t macKeyCode, int shift, double now) {
    const ScreenModel before = model;
    const bool backspace = macKeyCode == KEY_DELETE;
    VKEdit e;
    if (backspace && reverseVeto(now, e)) {
        hasLastFix = false;
    } else if (backspace && ruleConvert.active && ruleConvert.backspaces == 1 && ruleConvert.breaks.size() == 1 &&
               reverseRuleConvert(now, 1, e)) {
        // ⌫⌫ after a rule's conversion: Vikey's word is back (the first Backspace took the break character).
    } else {
        if (backspace && veto.active) veto.backspaces++;
        else veto = Veto();
        if (backspace && ruleConvert.active) ruleConvert.backspaces++;
        else ruleConvert = RuleConvert();
        if (!backspace) hasLastFix = false;
        const int undosBefore = driver->undos;
        const bool letterKey = isLetterKey(macKeyCode);
        const int languageBefore = vLanguage;
        const bool afterDoubledKey = doubledKeyFlip;
        e = pressTracked(macKeyCode, shift != 0, now);
        if (!backspace) keepSwitchBackUnlessEnglish(languageBefore);
        comeBackAfterDoubledKey(macKeyCode, shift, languageBefore, e);
        if (letterKey) {
            const bool wordStarted = wordOf(before.line).empty();
            model.wordCapsLock = (wordStarted || before.wordCapsLock) && capsLockForNextKey;
            if (wordStarted) { model.wordKeys.clear(); model.wordKeysKnown = true; }
            for (size_t k = 0; k < 26; k++) {
                if (kLetterKeys[k] != macKeyCode) continue;
                if (model.wordKeys.size() >= kFixWordMax) {
                    model.wordKeysKnown = false;
                    model.wordKeys.clear();
                } else if (model.wordKeysKnown) {
                    model.wordKeys += (char16_t)((shift ? 'A' : 'a') + k);
                }
            }
        } else if (backspace) {
            model.wordKeysKnown = false;
        }
        if (driver->undos != undosBefore) {
            // An undo of an English word Vikey put back ("tét" -> "test", "trafic" -> "traffic") waits for the next
            // key (editAfterUndo).
            if (hasLastFix && isAscii(lastFix.after) && lastFix.after != lastFix.before) {
                heldUndo = HeldUndo();
                heldUndo.active = true;
                heldUndo.fix = lastFix;
            } else if (hasLastFix) {
                queueUndo(lastFix, false);
            }
            hasLastFix = false;
        }
        Fix fix;
        if (backspace) {
            if (doubleKeyFix) repairDoubleKey(before, now, e);
        } else if (!letterKey && languageBefore == 1 && vLanguage == 1 &&
                   !(driver->*member(UndoActiveTag())) && (keepFinalK(before, e) || toneFinalKAtBreak(before, e) || typeInitialKr(before, e) ||
                                                           keepKeysAfterKr(before, e))) {
            // kept or typed a place name; nothing for the fix filter
        } else if (fixOfLastKey(e, fix)) {
            if (capsLockKeeps(before, fix)) {
                vetoFix(before, macKeyCode, shift != 0, now, e, fix);
                veto.capsLock = true;
            } else if (languageBefore == 1 && finalKKeeps(fix.before, fix.after)) {
                // A place name with a final k that Vikey switched to English instead ("búk " -> "busk ").
                vetoFix(before, macKeyCode, shift != 0, now, e, fix);
                veto.capsLock = true;   // the shim's own rule: no undo event on reverse
            } else if (afterDoubledKey && doubledToneKeyKeeps(fix)) {
                vetoFix(before, macKeyCode, shift != 0, now, e, fix);
                veto.capsLock = true;   // the shim's own rule, as for Caps Lock: no undo event on reverse
                veto.languageAfterFix = 0;   // the keys come back as typed, in English (Vikey's language for them)
                // The undo inside vetoFix put English back; the word was no English word, so Vietnamese comes back
                // for the next one, as comeBackAfterDoubledKey does.
                if (vLanguage != 1) {
                    vLanguage = 1;
                    startNewSession();
                    vAutoSwitchForget();
                }
                e.languageChanged = languageBefore != 1;
                model.languageAfterLastKey = 1;
            } else if (fixFilter) {
                const lk_fix c = toC(fix);
                if (fixFilter(&c) == 1) vetoFix(before, macKeyCode, shift != 0, now, e, fix);
                else rememberLastFix(fix, macKeyCode, shift != 0);
            } else { rememberLastFix(fix, macKeyCode, shift != 0); }
        } else if (convertFilter && !letterKey) {
            // Vikey left the finished word alone: a learned rule may still convert it (spec 5.2).
            convertAtBreak(languageBefore, now, e);
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
    const int cap = (int)(sizeof(out->text) / sizeof(out->text[0]));
    if (e.text.size() > (size_t)cap) {
        // Cut short, the edit would leave the screen and the shim's copy of the line apart: let the key through
        // as typed instead (nothing deleted, nothing inserted) and start over, as a click would. A language switch
        // still reaches the app, so its Việt/Anh state stays Vikey's.
        lk_vikey_reset_context();
        out->languageChanged = e.languageChanged ? 1 : 0;
        return;
    }
    out->deleteCount = e.deleteCount;
    const int n = (int)e.text.size();
    for (int i = 0; i < n; i++) out->text[i] = (uint16_t)e.text[i];
    out->length = n;
    out->languageChanged = e.languageChanged ? 1 : 0;
}

int lk_vikey_convert_last_word(double now, lk_edit* out) {
    if (!out) return 0;
    out->deleteCount = 0; out->length = 0; out->languageChanged = 0;
    if (!driver) return 0;
    VKEdit e;
    if (!convertLastWord(now, e)) {
        // The key goes to the app, which edits the text itself; rendering to decide may have disturbed the engine, so
        // the typing context starts over.
        lk_vikey_reset_context();
        return 0;
    }
    const int cap = (int)(sizeof(out->text) / sizeof(out->text[0]));
    if (e.text.size() > (size_t)cap) {
        // Too long for one edit: the screen and the shim's copy would part, so start over, as lk_vikey_press does.
        lk_vikey_reset_context();
        out->languageChanged = e.languageChanged ? 1 : 0;
        return 0;
    }
    out->deleteCount = e.deleteCount;
    const int n = (int)e.text.size();
    for (int i = 0; i < n; i++) out->text[i] = (uint16_t)e.text[i];
    out->length = n;
    out->languageChanged = e.languageChanged ? 1 : 0;
    return 1;
}

void lk_vikey_set_last_word_case(const uint16_t* units, int length) {
    if (!units || length <= 0 || (size_t)length > kFixWordMax) return;
    const std::u16string cased((const char16_t*)units, (size_t)length);
    size_t end = model.line.size();
    while (end > 0 && isBreakChar(model.line[end - 1])) end--;
    const std::u16string word = wordEndingAt(model.line, end);
    if (word.size() != cased.size() || lowerCase(word) != lowerCase(cased)) return;
    model.line.replace(end - word.size(), word.size(), cased);
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

void lk_vikey_set_convert_filter(lk_convert_filter filter) {
    convertFilter = filter;
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
    // The app echoes each of Vikey's own switches back here, asynchronously, with the language Vikey already has:
    // that echo must not wipe the copy of the line or the word's state (the double-key repair, D19's comeback, a fix
    // ⌫⌫ may still undo). Starting over is lk_vikey_reset_context's job.
    if (driver && vLanguage == (vietnamese ? 1 : 0)) return;
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

void lk_vikey_set_restore_wrong_spelling(int on) {
    vRestoreIfWrongSpelling = on ? 1 : 0;
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
            if (len >= (int)(sizeof(screen) / sizeof(screen[0]))) { ok = false; break; }
            screen[len++] = (char16_t)keyCodeToCharacter(key);
            continue;
        }
        len -= HookState.backspaceCount;
        if (len < 0 || len + HookState.newCharCount + 1 > (int)(sizeof(screen) / sizeof(screen[0]))) { ok = false; break; }
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

int lk_vikey_completions(int vietnamese, const char* prefix, char out[][32], int* scores, int maxOut) {
    if (!prefix || !prefix[0] || !out || !scores || maxOut <= 0) return 0;
    const int capped = maxOut > 16 ? 16 : maxOut;
    char clean[30];
    int n = 0;
    for (; prefix[n]; n++) {
        if (n >= (int)sizeof(clean) - 1) return 0;
        char c = prefix[n];
        if (c >= 'A' && c <= 'Z') c = (char)(c - 'A' + 'a');
        if (c < 'a' || c > 'z') return 0;
        clean[n] = c;
    }
    if (n == 0) return 0;
    clean[n] = 0;
    return vAutoSwitchCompletions(vietnamese ? 1 : 0, clean, out, scores, capped);
}

int lk_vikey_render_telex(const char* letters, uint16_t* out, int maxOut) {
    if (!letters || !out || maxOut <= 0) return 0;
    char key[40];
    int n = 0;
    for (; letters[n]; n++) {
        if (n >= (int)sizeof(key) - 1) return 0;
        char c = letters[n];
        if (c >= 'A' && c <= 'Z') c = (char)(c - 'A' + 'a');
        if (c < 'a' || c > 'z') return 0;
        key[n] = c;
    }
    if (n == 0) return 0;
    key[n] = 0;
    lk_vikey_init();
    Uint16 rendered[64];
    int renderedLen = 0;
    int score = vAutoSwitchWordScore(1, key, rendered, &renderedLen);
    if (score == LK_VIKEY_NOT_A_WORD || renderedLen <= 0 || renderedLen > maxOut) return 0;
    for (int i = 0; i < renderedLen; i++) out[i] = rendered[i];
    return renderedLen;
}

}
