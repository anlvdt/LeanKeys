// lk_vikey.cpp: the C API in lk_vikey.h over Vikey's VikeyDriver. vendor/vikey stays untouched.
#include "lk_vikey.h"
#include "Driver.h"
#include "telex_map.h"
#include <cstring>
#include <string>

extern vKeyHookState HookState;   // Engine.cpp: the engine's output for the last key

// Settings the engine leaves to the platform, with the defaults Vikey's own driver test uses
// (vendor/vikey/Tools/autoswitch/driver/undo_test.cpp). vTelexStyle is defined by Engine.cpp.
int vLanguage = 1, vSwitchKeyStatus = 0, vCheckSpelling = 1, vUseModernOrthography = 1, vRestoreIfWrongSpelling = 1,
    vFixRecommendBrowser = 1, vUseSmartSwitchKey = 1, vOtherLanguage = 1, vAutoSwitchByTyping = 1;

// One driver: the engine keeps its state in globals (vKeyInit), so a second driver would share it anyway.
static VikeyDriver* driver = nullptr;

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
};

static ScreenModel model;
static bool doubleKeyFix = true;

static void resetModel() { model = ScreenModel(); }

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

// The previous finished word, lower case: the letters before the current word and the break after them.
[[maybe_unused]] static std::u16string previousWord() {
    size_t i = model.line.size() - currentWord().size();
    while (i > 0 && !isWordLetter(model.line[i - 1])) i--;
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
    driver->setLanguage(1);
    driver->resetContext();
    for (size_t i = 0; i < keys.size(); i++) driver->press(kLetterKeys[keys[i] - 'a'], i == 0 && isUpper(snapshot[0]), now);

    model.wordStartLanguage = 1;
    model.lastKey = model.keyBefore = kNoKey;
    model.lastKeyReplaced = false;
    model.languageAfterLastKey = 1;
    return true;
}

extern "C" {

int lk_vikey_init(void) {
    if (!driver) driver = new VikeyDriver();
    return driver ? 1 : 0;
}

void lk_vikey_press(uint16_t macKeyCode, int shift, double now, lk_edit* out) {
    if (!out) return;
    out->deleteCount = 0; out->length = 0; out->languageChanged = 0;
    if (!driver) return;
    const ScreenModel before = model;
    VKEdit e = pressTracked(macKeyCode, shift != 0, now);
    if (macKeyCode == KEY_DELETE && doubleKeyFix) repairDoubleKey(before, now, e);
    out->deleteCount = e.deleteCount;
    const int cap = (int)(sizeof(out->text) / sizeof(out->text[0]));
    const int n = e.text.size() < (size_t)cap ? (int)e.text.size() : cap;
    for (int i = 0; i < n; i++) out->text[i] = (uint16_t)e.text[i];
    out->length = n;
    out->languageChanged = e.languageChanged ? 1 : 0;
}

void lk_vikey_reset_context(void) {
    if (driver) driver->resetContext();
    resetModel();
}

void lk_vikey_set_double_key_fix(int on) {
    doubleKeyFix = on != 0;
}

void lk_vikey_set_language(int vietnamese) {
    resetModel();
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
    return ok ? 1 : 0;
}

}
