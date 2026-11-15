// lk_vikey.cpp: the C API in lk_vikey.h over Vikey's VikeyDriver. vendor/vikey stays untouched.
#include "lk_vikey.h"
#include "Driver.h"

extern vKeyHookState HookState;   // Engine.cpp: the engine's output for the last key

// Settings the engine leaves to the platform, with the defaults Vikey's own driver test uses
// (vendor/vikey/Tools/autoswitch/driver/undo_test.cpp). vTelexStyle is defined by Engine.cpp.
int vLanguage = 1, vSwitchKeyStatus = 0, vCheckSpelling = 1, vUseModernOrthography = 1, vRestoreIfWrongSpelling = 1,
    vFixRecommendBrowser = 1, vUseSmartSwitchKey = 1, vOtherLanguage = 1, vAutoSwitchByTyping = 1;

// One driver: the engine keeps its state in globals (vKeyInit), so a second driver would share it anyway.
static VikeyDriver* driver = nullptr;

extern "C" {

int lk_vikey_init(void) {
    if (!driver) driver = new VikeyDriver();
    return driver ? 1 : 0;
}

void lk_vikey_press(uint16_t macKeyCode, int shift, double now, lk_edit* out) {
    if (!out) return;
    out->deleteCount = 0; out->length = 0; out->languageChanged = 0;
    if (!driver) return;
    VKEdit e = driver->press(macKeyCode, shift != 0, now);
    out->deleteCount = e.deleteCount;
    const int cap = (int)(sizeof(out->text) / sizeof(out->text[0]));
    const int n = e.text.size() < (size_t)cap ? (int)e.text.size() : cap;
    for (int i = 0; i < n; i++) out->text[i] = (uint16_t)e.text[i];
    out->length = n;
    out->languageChanged = e.languageChanged ? 1 : 0;
}

void lk_vikey_reset_context(void) {
    if (driver) driver->resetContext();
}

void lk_vikey_set_language(int vietnamese) {
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
    static const Uint16 keys[26] = {KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I, KEY_J, KEY_K, KEY_L,
                                    KEY_M, KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T, KEY_U, KEY_V, KEY_W, KEY_X,
                                    KEY_Y, KEY_Z};
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
    return ok ? 1 : 0;
}

}
