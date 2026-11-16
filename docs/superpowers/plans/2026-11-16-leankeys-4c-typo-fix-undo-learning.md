# 4C: Double-key Backspace fix and undo learning — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Backspace right after an accidental double key gives back the Vietnamese word (spec §12.1), and LeanKeys learns from the user's ⌫⌫ undo of Vikey's auto-fixes (§12.2), with a settings card (§12.3).

**Architecture:**
- **Shim:** both behaviours live in the C++ shim `leankeys/VikeyShim/lk_vikey.cpp`. It wraps `VikeyDriver::press`, keeps a model of the word on screen, and returns one composite `lk_edit` per key. `vendor/vikey` stays untouched.
- **Swift:** a rule book (`UndoRuleBook`) decides through a C callback the shim calls when Vikey is about to fix a word. Swift drains undo events after each press and records them, persisting through the 4B `KeychainEncryptedFileStore`.
- **Settings:** a new card on Nâng cao.

**Tech Stack:** C++17 shim, Swift 5 / SwiftUI / XCTest (`swift test` at repo root), Python 3 + clang++ for mixbench.

**Spec:** `docs/superpowers/specs/2026-11-15-leankeys-design.md` §12 (also read §11.1 Bảo mật for exclusions).

## Global Constraints
- Never modify `vendor/vikey/`, `core/`, `README.md`, `CONTRIBUTORS.md`. Every edited upstream line (`platforms/macos/…`) carries `// LEANKEYS-HOOK: <name>` with a name already registered for that file in `sync/hooks.txt`; `sync/check-divergence.sh v1.0.165` must pass.
- Never log typed text (no `print`/`NSLog`/`os_log` of words, rules or edits).
- Defaults: both features ON. UserDefaults keys: `LeanKeys.doubleKeyFix` and `LeanKeys.undoLearning` (absent = true).
- Context rule applies after **1** undo; contextless after **2** undos of the same text; a reverse undo drops every rule for that text and blocks it until **2** more same-direction undos. Cap **5,000** rules, LRU.
- Store: `~/Library/Application Support/LeanKeys/undo-rules.bin`, Keychain service `io.github.anlvdt.leankeys.undo`, via `KeychainEncryptedFileStore(url:keychainService:)`.
- No learning under Secure Input, in an `AXSecureTextField`, or in apps from `Exclusions.defaultBundleIDs` ∪ UserDefaults `LeanKeys.learn.excludedApps`. Learned rules apply everywhere.
- Code that runs on the key path (filter callback, event drain) does no I/O and takes at most one short lock.
- UI copy (Vietnamese, exact): card title `Tự sửa và tự học`; toggles `⌫ sửa phím gõ đúp` and `Tự học từ hoàn tác`; list header `Từ đã học`; button `Xoá tất cả`; empty list `Chưa có từ nào`.
- Before every commit: `swift test` passes. At the end: `.githooks/pre-push --all` passes.

## Review Focus
1. **Capitals.** `Hocjj⌫` must give `Học` and `HOCJJ⌫` give `HỌC`. The case of the restored word follows the screen. (Task 1 test.)
2. **Repeated ⌫ (held key).** The second ⌫ after a repair is a plain Backspace: `hocjj⌫⌫` → `họ`. (Task 1 test.)
3. **Something between the doubled key and ⌫.** A click or arrow (`lk_vikey_reset_context`) cancels the repair, and Vikey's own behaviour applies. (Task 1 test.)
4. **Case of a rule match.** `Cos` at the start of a sentence matches a rule learned from `cos`. (Task 4 test.)
5. **Feature switches.** With learning off, the filter returns 0 and nothing is recorded. With the double-key fix off, Vikey's ⌫ behaviour is unchanged. (Task 1 and Task 5 tests.)

---

### Task 1: Shim — double-key Backspace repair (§12.1)

**Files:**
- Create: `leankeys/VikeyShim/telex_map.h` — static table: every Vietnamese letter (lower and upper, including đ/Đ) → its Telex base keys plus tone key. Generated once; the generator command goes in a header comment.
- Modify: `leankeys/VikeyShim/lk_vikey.cpp`, `leankeys/VikeyShim/include/lk_vikey.h`
- Test: `leankeys/Tests/LeanKeysKitTests/DoubleKeyFixTests.swift`

**Interfaces:**
- Produces:
  - `void lk_vikey_set_double_key_fix(int on);` (default on).
  - The shim's internal screen model: the current word, the previous finished word (lowercase), the language at word start, and the last two non-Backspace keys. Task 3 reuses it.
  - `lk_vikey_reset_context` and `lk_vikey_set_language` clear the model.

**Algorithm.** It is pinned by the prototype measured in spec §12, so follow it exactly. After `driver->press(key)`, apply the edit to the model. Then, when `key == Backspace(51)` and the fix is on, repair if all hold:
- (a) the previous key equals the key before it, and both are non-Backspace;
- (b) the previous key's edit had `deleteCount > 0`;
- (c) the word shown after the previous key (`screenBefore`) is not a valid Vietnamese word, i.e. `vAutoSwitchWordScore(1, telexKeys(screenBefore), rendered, …)` is not a word, or renders differently;
- (d) the previous key moved the language from 1 to 0 while the word had started in Vietnamese, **or** `snapshot` (the word before the previous key) is all ASCII;
- (e) if `screenBefore` is all ASCII and an English word (`vAutoSwitchWordScore(0, lower)`), the Vietnamese score of `snapshot` exists and is ≥ that English score.

The repair:
- Return one edit: `deleteCount` = length of the word currently shown, `text` = `snapshot`.
- Put the language back to 1 (`languageChanged = 1` if it was 0).
- Rebuild the engine: `driver->setLanguage(1)`, `driver->resetContext()`, then press `telexKeys(snapshot)`, with Shift on the first key when `snapshot` starts with a capital, discarding the output.
- Clear the "previous key" state so the next ⌫ is plain.

- [ ] **Step 1: Write failing tests** in `DoubleKeyFixTests` using a `Field` helper like `VikeyEngineTests`, with `"⌫"` meaning Backspace:
  - `testToneDoubledThenBackspace`: `hocjj⌫` → `học`; `tieengss⌫` → `tiếng`; `ddaxx⌫` → `đã`.
  - `testPlainLettersDoubled`: `quaa⌫` → `qua`.
  - `testLanguageStaysVietnamese`: after `hocjj⌫`, `engine.isVietnamese == true`, and typing ` ddi` gives `học đi`.
  - `testEnglishWordWins`: `userr⌫` → `use`; `coss⌫` → `có`; `carr⌫` → `cả`.
  - `testCapitals`: `Hocjj⌫` → `Học`; `HOCJJ⌫` → `HỌC`.
  - `testSecondBackspaceIsPlain`: `hocjj⌫⌫` → `họ`.
  - `testNotDoubledUnchanged`: `rofif⌫` gives exactly what Vikey gives with the fix off (compute it in the test with `lk_vikey_set_double_key_fix(0)`).
  - `testResetBetweenCancels`: `hocjj`, `resetContext()`, `⌫` → Vikey's own result.
  - `testSwitchOff`: with the fix off, `hocjj⌫` → `hoc` (Vikey today).
  - **Note:** the `Field` helper must pass `caps: shift` (the macOS key path passes caps = Shift ∨ Caps Lock).
- [ ] **Step 2:** `swift test --filter DoubleKeyFixTests` → FAIL (symbol missing).
- [ ] **Step 3:** Implement `telex_map.h`, the model, the repair and `lk_vikey_set_double_key_fix` as above.
- [ ] **Step 4:** `swift test` → all pass, including the existing `VikeyEngineTests`.
- [ ] **Step 5:** Commit: `Shim: Backspace after a double key gives the Vietnamese word back (spec 12.1)`.

### Task 2: mixbench through the real shim

**Files:**
- Create:
  - `tools/mixbench/lk.cpp`: like `vk.cpp`, but drives `lk_vikey_press` from `leankeys/VikeyShim/lk_vikey.cpp`. `` ` `` means Backspace; `|` marks the word length; `^` presses Backspace until the word is back to the marked length.
  - `tools/mixbench/typo.py`: the injector for modes `dbl extra mid endbl enextra enmid`, as in spec §12's table. VN modes touch 30% of Vietnamese words, EN modes 50% of English words. Seed is the third argument.
- Modify: `tools/mixbench/README.md`, adding a section "Lỗi rồi sửa bằng ⌫ (4C)" with the build/run commands and a table of Vikey (`vk`) vs LeanKeys (`lk`) per mode on `mine.txt` and `chat_messages.txt`, seed 5.

**Interfaces:** Consumes `lk_vikey_set_double_key_fix` (Task 1). `lk` accepts `--no-fix` to measure Vikey's behaviour through the same harness.

- [ ] **Step 1:** Write `typo.py` and `lk.cpp`. Build `lk` with the same `clang++` flags as `vk` plus `-I leankeys/VikeyShim/include`.
- [ ] **Step 2:** Run every mode on both corpora with `lk` and `lk --no-fix`, and score with `score.py`.
  - Expected: clean is identical; no mode has more wrong words with the fix.
  - On chat with `dbl`, VN errors fall from about 28.6% to about 1%.
  - If any mode gets worse, stop and report it as BLOCKED with the numbers.
- [ ] **Step 3:** Write the README table from the actual output.
- [ ] **Step 4:** Commit: `mixbench: typo modes through the shim (4C numbers)`.

### Task 3: Shim — fix filter, undo events, reverse undo (§12.2, C side)

**Files:**
- Modify: `leankeys/VikeyShim/lk_vikey.cpp`, `leankeys/VikeyShim/include/lk_vikey.h`
- Test: `leankeys/Tests/LeanKeysKitTests/UndoShimTests.swift`

**Interfaces:**
- Produces (C, in the header):
```c
typedef struct {
    uint16_t before[64]; int beforeLength;     // word on screen before Vikey changed it ("cos", "ít")
    uint16_t after[64];  int afterLength;      // the word Vikey made ("có", "its")
    uint16_t previous[64]; int previousLength; // previous word, lowercase, may be empty
} lk_fix;
typedef int (*lk_fix_filter)(const lk_fix* fix);  // return 1 to keep `before` (veto the change)
void lk_vikey_set_fix_filter(lk_fix_filter filter); // NULL = never veto
typedef struct { lk_fix fix; int reverse; } lk_undo; // reverse = 1: the user undid a veto (wants `after`)
int  lk_vikey_take_undo(lk_undo* out);           // 1 and fills `out` once per undo; 0 otherwise
```
- **Detecting a fix.** After `driver->press`, `driver->undoActive && !driver->undoBreakGone` with an edit that has `deleteCount > 0`. `before` = `driver->undoText`; `after` = the model's word just before the break character; `previous` = the model's previous word.
- **Veto.** If the filter returns 1:
  - Press Backspace twice and the same key again on the driver.
  - Compose the four edits into one `lk_edit`. Composition rule: applying `(d1,t1)` then `(d2,t2)` gives `d2 ≤ |t1| ? (d1, t1[0..|t1|-d2] + t2) : (d1 + d2 - |t1|, t2)`; `languageChanged` is the OR.
  - Remember the veto: fix and language.
- **Reverse.** ⌫ then ⌫ as the next two keys after a veto: the second returns `deleteCount = |before|`, `text = after`, sets the driver's language to the one after the fix (`languageChanged = 1` if it changed), and queues `lk_undo{fix, reverse = 1}`. Any other key clears the veto memory.
- **Vikey's own undo.** `driver->undos` incremented during the press → queue `lk_undo{lastFix, reverse = 0}`.
- **Queue.** One slot; a newer event replaces an older one.

- [ ] **Step 1: Failing tests** (Swift, real engine; a C filter function reading a test global):
  - `testUndoEventCarriesBeforeAfterPrevious`: type `toi thich ` then `cos ` (Vikey makes `có`), then ⌫⌫ → `take_undo` returns 1 with before `cos`, after `có`, previous `thich`, reverse 0. A second call returns 0.
  - `testVetoKeepsTypedWordInOneEdit`: filter returns 1 for before `cos` → typing `cos ` yields screen `cos `, the `cos` key path produced exactly one edit for the space key, and the language is the same as before the space.
  - `testVetoOtherDirection`: in an English sentence `I like ` + `its `. Find the case where Vikey's fix makes `ít`/`its` with a probe, and use whichever direction Vikey produces. The veto keeps `before`.
  - `testReverseUndoAfterVeto`: after the veto, ⌫⌫ → screen shows `after`, and `take_undo` gives reverse 1.
  - `testNoFilterNoChange`: with the filter `NULL`, output is identical to Vikey for a sentence containing `cos`.
- [ ] **Step 2:** `swift test --filter UndoShimTests` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `swift test` → all pass.
- [ ] **Step 5:** Commit: `Shim: fix filter, undo events and reverse undo (spec 12.2)`.

### Task 4: `UndoRuleBook` — rules, counts, LRU, persistence

**Files:**
- Create: `leankeys/LeanKeysKit/Learn/UndoRuleBook.swift`
- Test: `leankeys/Tests/LeanKeysKitTests/UndoRuleBookTests.swift`

**Interfaces:**
- Produces:
```swift
public struct UndoRule: Codable, Equatable, Identifiable {
    public var id: String { previous + "\u{1F}" + text }
    public let text: String        // lowercase `before`
    public let previous: String    // lowercase; "" = contextless
    public var count: Int
    public var lastUsed: Date
}
public final class UndoRuleBook {   // thread-safe (one NSLock); no I/O inside the lock
    public static let capacity = 5_000
    public init(store: LearnStore?, now: @escaping () -> Date = Date.init)
    public func record(before: String, previous: String, reverse: Bool)
    public func shouldKeep(before: String, previous: String) -> Bool   // marks the matching rule used
    public var rules: [UndoRule] { get }        // shown rules: context rules + contextless with count ≥ 2
    public func remove(_ rule: UndoRule)
    public func removeAll()
    public var onChange: (() -> Void)?          // called on the main queue after a change
}
```
- **Semantics.** Matching is case-insensitive.
  - `record(reverse: false)` bumps the context rule `(previous, text)` when `previous` is non-empty, and the contextless count for `text`.
  - `shouldKeep` is true if the context rule exists with count ≥ 1, or the contextless count is ≥ 2 and `text` is not blocked.
  - `record(reverse: true)` deletes every rule for `text` and sets `blocked[text] = 2`. While blocked, same-direction records decrement the block instead of counting; when it reaches 0 the next record counts normally.
  - When over capacity, drop the least recently used.
  - Persistence: JSON of rules plus blocks, saved through `store` on a private serial queue after each change and loaded in `init` (synchronously, on the caller's thread). `store == nil` means memory only.

- [ ] **Step 1: Failing tests:**
  - `testContextRuleAfterOneUndo`
  - `testContextlessAfterTwoUndos`
  - `testCaseInsensitive` (`Cos` matches `cos`)
  - `testReverseDropsAndBlocks`: after a reverse, needs 2 records to unblock, plus 2 more contextless records to reach count 2.
  - `testLRUCap`: 5,001 distinct texts → 5,000 rules, oldest `lastUsed` gone.
  - `testRemoveAndRemoveAll`
  - `testPersistsThroughStore`: in-memory `LearnStore` fake; a new book loads the same rules.
  - `testSavedDataEncryptedOnDisk`: uses `KeychainEncryptedFileStore` with a temp URL and a unique service; the file bytes contain no `cos`. Skip when Keychain is unavailable, the same way the 4B tests do (`LEANKEYS_NO_KEYCHAIN_TESTS`).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `swift test` → pass.
- [ ] **Step 5:** Commit: `UndoRuleBook: learned keep-as-typed rules (spec 12.2)`.

### Task 5: Wire learning into the Vikey path

**Files:**
- Create: `leankeys/LeanKeysKit/Learn/UndoLearning.swift`
- Modify: `leankeys/LeanKeysKit/Engine/VikeyEngine.swift` (add `func takeUndo() -> (before: String, after: String, previous: String, reverse: Bool)?` and `static func setDoubleKeyFix(_ on: Bool)`); `leankeys/LeanKeysKit/Engine/EngineRouter.swift` (after `vikey.process`, call `UndoLearning.shared.afterPress(engine:)`)
- Test: `leankeys/Tests/LeanKeysKitTests/UndoLearningTests.swift`

**Interfaces:**
- Consumes: Task 3's C API; Task 4's `UndoRuleBook`; `LearnContextReader.current()` and `Exclusions.defaultBundleIDs`.
- Produces:
```swift
public final class UndoLearning: ObservableObject {
    public static let shared: UndoLearning           // book on undo-rules.bin, keys from UserDefaults.standard
    public static let doubleKeyFixKey = "LeanKeys.doubleKeyFix", learningKey = "LeanKeys.undoLearning"
    init(book: UndoRuleBook, defaults: UserDefaults, context: @escaping () -> LearnContext)
    @Published public private(set) var rules: [UndoRule]
    @Published public var doubleKeyFix: Bool          // writes the key and calls VikeyEngine.setDoubleKeyFix
    @Published public var learning: Bool              // writes the key; off = filter keeps nothing, nothing recorded
    public func install()                             // registers the C filter; idempotent
    func afterPress(engine: VikeyEngine)             // drains takeUndo; records unless the context is excluded
    public func remove(_ rule: UndoRule); public func removeAll()
}
```
- **C filter.** A `@convention(c)` function reading `UndoLearning.shared`, returning `learning && book.shouldKeep(...)`. Tests inject a book through `init` and call a `filterDecision(before:previous:)` method that the C function forwards to.
- **When to install.** `EngineRouter` calls `install()` when it creates the Vikey engine.
- **Exclusion.** `context()` gives `secureInput || secureField`, or a bundle ID in `Exclusions.defaultBundleIDs` ∪ `LeanKeys.learn.excludedApps`, and the record is skipped. The context is read only when an undo event exists, never per key.

- [ ] **Step 1: Failing tests:**
  - `testRecordsUndoOutsideExclusions`
  - `testSkipsSecureFieldAndExcludedApp`
  - `testLearningOffKeepsNothingRecordsNothing`
  - `testDoubleKeyFixToggleReachesShim` (toggle off → `hocjj⌫` → `hoc`)
  - `testEndToEndContextRule`: real `VikeyEngine` plus a memory-only book. Type `toi thich cos `, ⌫⌫, `afterPress`; then retype `cos ` after `thich ` and the screen keeps `cos`.
  - `testDefaultsOnWhenUnset`
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `swift test` → pass.
- [ ] **Step 5:** Commit: `4C: learn from undo on the Vikey path`.

### Task 6: Settings card, screenshots, checklist

**Files:**
- Create: `leankeys/LeanKeysKit/UI/UndoLearningSection.swift`. It copies the card look of `LearnSettingsSection`'s advanced card.
- Modify:
  - `platforms/macos/AdvancedSettingsView.swift`: add one line after line 18, `UndoLearningSection(model: .shared) // LEANKEYS-HOOK: settings-engine`.
  - `leankeys/Tests/LeanKeysKitTests/UISnapshotTests.swift`: render the card with fake rules, light and dark.
  - `sync/manual-checklist.md`: add a section "4C" with the four manual checks of spec §12.4.
- Create: `docs/ui/settings-undo-learning-light.png`, `docs/ui/settings-undo-learning-dark.png`, using fake data only.

**Interfaces:** Consumes `UndoLearning` (Task 5).

**Card content.** Title, the two toggles (exact copy from Global Constraints), then the list header `Từ đã học`. Each row shows `text`, and `sau "previous"` in secondary color when there is context, the count, and a trash button calling `remove`. Then `Xoá tất cả`, behind a confirmation alert ("Xoá mọi từ đã học?" / "Xoá" / "Huỷ"), and `Chưa có từ nào` when the list is empty. Secondary text uses `NSColor.secondaryLabelColor`.

- [ ] **Step 1:** Write a snapshot test that renders the card with 3 fake rules and asserts the PNGs are written. Run it → FAIL.
- [ ] **Step 2:** Implement the view and the hook line. Run `sync/check-divergence.sh v1.0.165` → exit 0.
- [ ] **Step 3:** `swift test` → pass. Look at the two PNGs: text is readable in both modes and nothing is clipped.
- [ ] **Step 4:** Update `sync/manual-checklist.md`.
- [ ] **Step 5:** Commit: `4C: settings card, screenshots, manual checks`.

### Final verification (controller)
- `.githooks/pre-push --all` → 6/6.
- `sync/check-divergence.sh v1.0.165` → exit 0.
- `LEANKEYS_REQUIRE_STABLE_SIGNING=1 leankeys/build.sh` builds `dist/LeanKeys.app`.
