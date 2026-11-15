// lk_vikey.cpp: the C API in lk_vikey.h over Vikey's VikeyDriver. vendor/vikey stays untouched.
#include "lk_vikey.h"
#include "Driver.h"

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

}
