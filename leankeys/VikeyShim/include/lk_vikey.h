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
void lk_vikey_reset_context(void);              // also clears the shim's copy of the current line
// Caps Lock is on for the next lk_vikey_press (a capital typed without Shift). When every letter of a word was typed
// with Caps Lock and Vikey puts its raw capitals back at the break, the shim keeps the Vietnamese word when it is a
// common syllable with no English reading ("BUIF " -> "BÙI ", "USA " stays), as a veto (Backspace twice gives the
// keys back): Vikey alone keeps the marks of all capitals only inside a run.
void lk_vikey_set_caps_lock(int on);
// The next lk_vikey_press, when it is Return/Enter, may finish the word being typed as Space would (Vikey's auto
// switch either way: "dduowcj" -> "được" and back to Vietnamese, "púh" -> "push"), then Return is typed. Off, the
// default, is Vikey D62: Return sends what is on screen (a fix there would remove an address bar's autocompletion).
// Consumed by the next press, like lk_vikey_set_caps_lock.
void lk_vikey_set_fix_at_return(int on);
// Vietnamese words (one per line, any case) that a Caps Lock word keeps even though Vikey's dictionary scores them
// low: family, middle and given names ("bùi", "nguyễn"). Replaces the previous list.
void lk_vikey_set_caps_words(const uint16_t* units, int count);

// Spec 12.1, on by default: Backspace right after a doubled key that undid a mark (Telex "hocjj" shows "hocj")
// gives back the word from before the doubled key ("học") and keeps Vietnamese, in one edit (delete the word,
// type the old one; languageChanged when the language comes back to Vietnamese). Off: Vikey's own Backspace.
void lk_vikey_set_double_key_fix(int on);
// Spec 12.2: Vikey's own fix of a finished word at a break key (English -> Vietnamese "cos " -> "có ", or back to
// English "ít " -> "its "), which Vikey lets the user undo with Backspace twice.
typedef struct {
    uint16_t before[64]; int beforeLength;     // the word on screen before Vikey changed it ("cos", "ít")
    uint16_t after[64];  int afterLength;      // the word Vikey made ("có", "its")
    uint16_t previous[64]; int previousLength; // the word before it on the same line, lower case; may be empty
} lk_fix;
// Called when Vikey has just fixed a word (words over 64 UTF-16 units are never reported). Return 1 to keep `before`:
// the shim undoes the fix inside the engine and types the break key again, all in the one edit the key returns, with
// the language as it was before the key. 0 lets the fix stand.
typedef int (*lk_fix_filter)(const lk_fix* fix);
void lk_vikey_set_fix_filter(lk_fix_filter filter); // NULL = never veto (the default)
// An undo: the user pressed Backspace twice right after a fix (Vikey puts `before` back; reverse = 0), or right after
// a veto (the shim applies the fix after all: `after` comes back with its language; reverse = 1).
typedef struct { lk_fix fix; int reverse; } lk_undo;
// 1 and fills `out` once per undo; 0 when there is none. One slot: a newer undo replaces one not yet taken.
// No lock: call it on the thread that calls lk_vikey_press, right after the press.
int  lk_vikey_take_undo(lk_undo* out);

void lk_vikey_set_language(int vietnamese);     // 1 = Việt, 0 = Anh; a change clears the copy of the line too (same language: no-op)
int  lk_vikey_language(void);
void lk_vikey_set_options(int modernOrthography, int autoSwitch, int telexStyle);
// On by default: a word with a wrong spelling that ends at a break key comes back as typed ("push", "user").
// Off (pure Telex, together with auto switch off): the keys stay Telex ("push " -> "púh ").
void lk_vikey_set_restore_wrong_spelling(int on);

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

// 1 when typing `letters` (plain ASCII letters, under 31, case ignored) in Vietnamese Telex shows exactly
// those letters: no aa/dd/w/tone transform ("sdt" -> 1, "dd" -> 0 (đ), "as" -> 0 (á), "w" -> 0 (ư) in Telex).
// Uses the current Telex style; auto switch is off for the replay. 0 for anything else.
// Main (key-handling) thread only: it replays through the engine's global state. The engine cannot restore
// its private per-word state from outside vendor/, so afterwards the typing context is reset, as after a click
// (lk_vikey_reset_context): the word being typed, Backspace history and look-back are forgotten.
int  lk_vikey_types_as_is(const char* letters);

#ifdef __cplusplus
}
#endif

#endif
