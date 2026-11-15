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

// How common `letters` is as a word, from Vikey's built-in dictionaries (vAutoSwitchWordScore).
// letters: plain ASCII letters, under 39 of them; case is ignored. Anything else (digits, spaces,
// accented letters) scores LK_VIKEY_NOT_A_WORD.
//   vietnamese = 0: the English word list, plus the SCOWL forms it lacks (those score -8).
//   vietnamese = 1: letters are Telex keys, replayed through the engine: "dduowcj" is được.
//     Keys that type no mark ("em", "an", "co", "cam") are looked up as the unaccented word.
//     Teencode words count too (vTeencode is on by default).
// Returns LK_VIKEY_NOT_A_WORD (-1000) when it is not a word. Otherwise 10*log10(occurrences per million):
// a positive score is a word seen more than once per million words; 0 or below is a real but rare word.
// The Vietnamese path runs the engine and restores its state, so call it on the key-handling thread only.
#define LK_VIKEY_NOT_A_WORD (-1000)
int  lk_vikey_word_score(int vietnamese, const char* letters);

#ifdef __cplusplus
}
#endif

#endif
