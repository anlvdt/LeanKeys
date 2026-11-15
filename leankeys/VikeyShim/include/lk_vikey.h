// lk_vikey.h: plain C view of Vikey's VikeyDriver (vendor/vikey/Engine/Driver.h) for Swift.
// One engine per process: Vikey keeps its state in globals.
#ifndef LK_VIKEY_H
#define LK_VIKEY_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { int deleteCount; int length; uint16_t text[256]; int languageChanged; } lk_edit;

int  lk_vikey_init(void);                       // 1 = ok
void lk_vikey_press(uint16_t macKeyCode, int shift, double now, lk_edit* out);
void lk_vikey_reset_context(void);
void lk_vikey_set_language(int vietnamese);     // 1 = Việt, 0 = Anh
int  lk_vikey_language(void);
void lk_vikey_set_options(int modernOrthography, int autoSwitch, int telexStyle);

#ifdef __cplusplus
}
#endif

#endif
