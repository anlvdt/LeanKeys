# 4D: Auto-capitalised proper nouns and stray keys at Enter — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the Vikey path, capitalise place names, full names and learned names when a word is committed (spec §17.1); drop a key next to Enter that was hit together with Enter (§17.2); add settings for both (§17.3).

**Architecture:**
- **Rules:** a pure Swift rule engine (`ProperNounRules`) reads its lists from a JSON resource that the Python `tools/capbench` shares, so the measured rules and the shipped rules are the same data.
- **Router:** `EngineRouter.intercept` composes Vikey's edit at a break key with a capitalisation edit, and handles ⌫-undo of a capitalisation.
- **Learning:** learned names live in their own encrypted store.
- **Stray Enter:** a pure filter (`StrayEnterFilter`) decides at Enter and right after it; the router applies its decision.

**Tech Stack:** Swift 5 / SwiftUI / XCTest (`swift test` at repo root); Python 3 for capbench.

**Spec:** `docs/superpowers/specs/2026-11-15-leankeys-design.md` §17 (it builds on §12 for the 4C rule book and settings card, and §11.1 for exclusions).

## Global Constraints
- Never modify `vendor/vikey/`, `core/`, `README.md`, `CONTRIBUTORS.md`. Edited upstream lines carry `// LEANKEYS-HOOK: <name>` registered in `sync/hooks.txt`; `sync/check-divergence.sh v1.0.165` exits 0. This plan should need no new upstream edits.
- Vikey path only. With Gõ Nhanh active, nothing in this plan runs.
- Never log typed text.
- Defaults ON. UserDefaults keys: `LeanKeys.autoCapitalize` and `LeanKeys.strayEnter` (absent = true).
- Stray window: **100 ms**, inclusive, as one named constant. Adjacent keys: keyCodes 42 `\`, 30 `]`, 39 `'` (with Shift: `|` `}` `"`). Enter keyCodes 36 and 76.
- Learned names: threshold **2**; below threshold store only HMAC-SHA256 (key from `KeychainEncryptedFileStore.hmacKey()` of the names store); cap **2,000**, LRU; file `~/Library/Application Support/LeanKeys/learned-names.bin`; Keychain service `io.github.anlvdt.leankeys.names`.
- Capitalisation undo rules go into `UndoRuleBook` with the text prefixed `cap:` (lowercased phrase), the previous word as context, and the 4C counting semantics.
- No learning under Secure Input, in password fields, or in excluded apps. Reuse the context check in `UndoLearning`.
- UI copy, exact: toggles `Tự viết hoa tên riêng`, `Bỏ ký tự gõ dính khi Enter`; list header `Tên đã học`; capitalisation rules shown with suffix ` (viết hoa)`.
- Before each commit `swift test` passes; at the end `.githooks/pre-push --all` passes.

## Review Focus
1. **Capitalisation right after a Vikey auto-fix at the same break key** (for example `cos ` → `có`): no capitalisation happens at that key, so Vikey's own ⌫⌫ undo stays consistent. (Task 3 test.)
2. **Punctuation as the break** (`ha noi.`): the replacement lands before the `.`, and the `.` is still typed by the key itself. (Task 3 test.)
3. **Words already capitalised by the user** (`Hà nội`): the result is `Hà Nội`, and the user's own capitals are never lowered. (Task 1 test.)
4. **A sentence-initial word** is never learned as a name, and a word LeanKeys capitalised itself is never learned. (Task 2 and Task 3 tests.)
5. **Stray key with a modifier other than Shift** (⌘\, ⌥\): never dropped. (Task 4 test.)

---

### Task 1: Proper-noun data, rule engine, capbench

**Files:**
- Create:
  - `leankeys/LeanKeysKit/Resources/ProperNouns.json`: lists `places`, `ambiguousPlaces`, `placeCues`, `surnames`, `sureSurnames`, `middleNames`, `givenNames`, `titles`, `singleWords` (exact values from spec §17.1.1–17.1.2; given names from the prototype `data.py`, see dispatch).
  - `leankeys/LeanKeysKit/Learn/ProperNounRules.swift`
  - `tools/capbench/capbench.py`, plus a README section in `tools/mixbench/README.md` or a new `tools/capbench/README.md`.
- Modify: `Package.swift` only if the resource needs declaring (check how `Versions.json` is bundled).
- Test: `leankeys/Tests/LeanKeysKitTests/ProperNounRulesTests.swift`

**Interfaces:**
- Produces:
```swift
public struct ProperNounData: Decodable { /* the JSON lists */ public static let bundled: ProperNounData }
public protocol LearnedNameLookup { func name(after previous: String?, word: String) -> String? }  // cased form or nil
public struct Capitalization: Equatable { public let wordCount: Int; public let words: [String] } // replace the last `wordCount` words
public struct ProperNounRules {
    public init(data: ProperNounData = .bundled, learned: LearnedNameLookup? = nil)
    /// `words`: the current phrase's words as on screen, oldest first, ending with the word just committed
    /// (no punctuation; the phrase starts after the last . ! ? or newline). nil = nothing to change.
    public func capitalization(for words: [String]) -> Capitalization?
}
```
- **Rule order:** place phrases (longest first; ambiguous ones need a cue word or two-word cue right before), then name rules (spec §17.1.2), then learned names. Matching is case-insensitive.
  - The output capitalises the first letter of each affected word and keeps the user's existing capitals.
  - Return nil when nothing would change.
  - A word whose letters are not all lowercase or capitalised (`iPhone`, `FOMO`) is never touched.

- [ ] **Step 1: Failing tests:**
  - `testPlaces`: `["tôi","ở","hà","nội"]` → `(2, ["Hà","Nội"])`; `["thừa","thiên","huế"]` → `(3, …)`; `["huế"]` → `(1, ["Huế"])`.
  - `testAmbiguousNeedsCue`: `["hòa","bình"]` → nil; `["ở","hòa","bình"]` → `(2, ["Hòa","Bình"])`; `["thành","phố","hòa","bình"]` → capitalised.
  - `testNames`:
    - `["nguyễn"]` → `(1, ["Nguyễn"])`;
    - `["Nguyễn","văn"]` → `(2, ["Nguyễn","Văn"])`;
    - `["Nguyễn","Văn","tèo"]` → `(1, ["Tèo"])`;
    - `["trần","thị"]` → `(2, ["Trần","Thị"])`;
    - `["lê","hùng"]` → `(2, ["Lê","Hùng"])`;
    - `["Nguyễn","đi"]` → nil.
  - `testStaysLowercase`: `["vi","phạm"]`, `["khai","trương"]`, `["hòa","bình","thế","giới"]` (checked at each word), `["anh","hùng"]` with no learned names → nil.
  - `testKeepsUserCapitals`: `["Hà","nội"]` → `(2, ["Hà","Nội"])`; `["iphone"]` untouched.
  - `testLearnedLookupUsed`: a fake lookup returning `"Hùng"` for previous `"anh"` → `["anh","hùng"]` → `(1, ["Hùng"])`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement. Port the prototype rules exactly (see dispatch); the prototype's name chain is the reference.
- [ ] **Step 4:** `swift test` → pass.
- [ ] **Step 5:** Port the prototype harness into `tools/capbench/capbench.py`, reading `ProperNouns.json`. Run it on `vendor/vikey/Tools/autoswitch/sim/corpus/chat_messages.txt` and `synthetic_val.txt`.
  - Expected: fixed rules give FP 0 and TP ≥ 300.
  - If FP > 0, stop and report BLOCKED with the list.
  - Record the numbers in the README.
- [ ] **Step 6:** Commit: `4D: proper-noun rules and data, capbench (spec 17.1.1-17.1.2)`.

### Task 2: Learned names store

**Files:**
- Create: `leankeys/LeanKeysKit/Learn/LearnedNames.swift`
- Test: `leankeys/Tests/LeanKeysKitTests/LearnedNamesTests.swift`

**Interfaces:**
- Consumes: `LearnStore`, `KeychainEncryptedFileStore`, `LearnedNameLookup` (Task 1), `lk_vikey_word_score` (via a static on `VikeyEngine` or an injected closure `isDictionaryWord: (String) -> Bool`).
- Produces:
```swift
public struct LearnedName: Codable, Equatable, Identifiable { public var id: String { form.lowercased() }
    public let form: String; public var afterTitleOnly: Bool; public var count: Int; public var lastUsed: Date }
public final class LearnedNames: LearnedNameLookup {   // thread-safe, one lock, no I/O under the lock
    public static let capacity = 2_000, threshold = 2
    public init(store: LearnStore?, hmacKey: Data?, titles: Set<String>, isDictionaryWord: @escaping (String) -> Bool,
                now: @escaping () -> Date = Date.init)
    /// A word the user typed with a capital (Shift or Caps Lock), mid-sentence, not all caps, at least 2 letters,
    /// not capitalised by LeanKeys. `previous` = the word before it (lowercased) or nil.
    public func observe(word: String, previous: String?)
    public func name(after previous: String?, word: String) -> String?
    public func undone(word: String)                 // the 2nd undo anywhere removes the name
    public var names: [LearnedName] { get }          // learned (≥ threshold) only, most recent first
    public func remove(_ name: LearnedName); public func removeAll()
    public var onChange: (() -> Void)?               // main queue
}
```
- **Semantics** (spec §17.1.3):
  - A word observed after a title counts toward "after title".
  - A word whose ASCII-folded letters are not a dictionary word (both languages) counts toward "anywhere".
  - At 2 observations the name is learned with its cased form.
  - `afterTitleOnly = false` only for non-dictionary words.
  - `name(after:word:)` returns the form when learned and either `!afterTitleOnly` or `previous` is a title.
  - Below the threshold, keep only `HMAC(lowercased word) → (count, afterTitleSeen)`.

- [ ] **Step 1: Failing tests:**
  - `testThresholdAfterTitle`: observe("Hùng", "anh") twice → `name(after: "anh", word: "hùng") == "Hùng"`, and `name(after: "ăn", word: "hùng") == nil`.
  - `testAnywhereForNonDictionaryWords`: `isDictionaryWord` false for "shopee"; observe("Shopee", "mua") twice → `name(after: nil, word: "shopee") == "Shopee"`.
  - `testDictionaryWordNotAnywhere`: observe("Store", "app") twice → nil anywhere.
  - `testRejects`: all caps "FOMO"; one letter "A".
  - `testUndoneTwiceRemoves`
  - `testLRU`: 2,001 names → 2,000.
  - `testBelowThresholdNotStoredInClear`: memory store fake; after one observe of "Hùng" the saved bytes don't contain "Hùng" or "hùng".
  - `testPersists`
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `swift test` → pass.
- [ ] **Step 5:** Commit: `4D: learned names (spec 17.1.3)`.

### Task 3: Router — capitalise at word commit, ⌫ undo, learn

**Files:**
- Modify:
  - `leankeys/LeanKeysKit/Engine/EngineRouter.swift`
  - `leankeys/LeanKeysKit/Learn/TextMirror.swift`: add `public var phraseWords: [String]`, the current phrase's words before the cursor (letters/digits runs, punctuation dropped), plus `public var atPhraseStart: Bool`.
  - `leankeys/LeanKeysKit/Learn/UndoLearning.swift`: owns `LearnedNames.shared` setup, the `autoCapitalize` switch and the exclusion check reuse.
- Create: `leankeys/LeanKeysKit/Learn/AutoCapitalizer.swift`. It is the router's helper: it holds `ProperNounRules`, decides, and remembers the last capitalisation for undo.
- Test: `leankeys/Tests/LeanKeysKitTests/AutoCapitalizerTests.swift`, using real `VikeyEngine` through `EngineRouter.intercept` with injected memory-only stores.

**Interfaces:**
- Consumes: Task 1 `ProperNounRules`, Task 2 `LearnedNames`, the 4C `UndoRuleBook` (`record(before:previous:reverse:)`, `shouldKeep(before:previous:)`) and `UndoLearning` (injected into the router as in 4C).
- **Behaviour at a break key** (Space, Return/Enter, punctuation; the same set `expandShortcut` uses):
  - Vikey processes the key first. If Vikey's edit fixed the word (`deleteCount > 0` or `languageChanged`), do nothing more.
  - Otherwise compute the words, which are the mirror's phrase words with the just-committed word. Ask the rules. Skip if `autoCapitalize` is off, or `UndoRuleBook.shouldKeep(before: "cap:" + lowercased phrase of the affected words, previous: word before them)`.
  - Compose the result into one `(deleteCount, text, consumed)`:
    - Space: delete the affected words' characters, then type capitalised words plus `" "`, consumed.
    - Punctuation or Return: delete and type the capitalised words, not consumed, so the key follows.
  - Remember `lastCapitalization` (original words, new words, the break character, the previous word).
- **⌫ right after** (the very next key is Backspace):
  - Return one edit: delete break char plus new words, type original words.
  - Record `UndoRuleBook.record(before: "cap:…", previous:, reverse: false)`, and `LearnedNames.undone(word:)` when the capitalisation came from a learned name.
  - Any other key clears `lastCapitalization`.
- **Learning:** at each word commit, if the committed word was typed by the user with a leading capital, call `LearnedNames.observe` off the key path (serial queue), unless the context is excluded:
  - the word is not at phrase start;
  - it is not all caps;
  - it was not produced by LeanKeys' capitalisation or a gõ tắt expansion.
  - Track "typed by the user with a capital" via the caps flag of the word's first letter key.

- [ ] **Step 1: Failing tests:**
  - `testCapitalisesPlaceAtSpace`: type `toi o ha noi ` (Telex: `tooi owr haf nooij `) → screen `tôi ở Hà Nội `.
  - `testPunctuationBreak`: `… haf nooij.` → `Hà Nội.`
  - `testNoCapitaliseAfterVikeyFix` (Review Focus 1)
  - `testBackspaceUndoes`: after `haf nooij `, ⌫ → `hà nội`, and retyping the same context does not capitalise (context rule after 1 undo).
  - `testNameChain`: `nguyeenx vawn an ` → `Nguyễn Văn An `.
  - `testLearnsFromUserCapitalsOnly`: typing `anh Hùng` twice (Shift on H) learns; typing `ha noi` (capitalised by LeanKeys) twice does not create a learned name; a sentence-initial `Hùng` is not counted.
  - `testSwitchOff`
  - `testGoNhanhUnaffected`: router with Gõ Nhanh active returns `.passToGoNhanh`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `swift test` → pass.
- [ ] **Step 5:** Commit: `4D: capitalise proper nouns on the Vikey path, undo with Backspace (spec 17.1)`.

### Task 4: Stray key at Enter

**Files:**
- Create: `leankeys/LeanKeysKit/Engine/StrayEnterFilter.swift`
- Modify: `leankeys/LeanKeysKit/Engine/EngineRouter.swift`. Call the filter at the top of the Vikey path, after the Ctrl check. Pass time with an injectable clock (default `ProcessInfo.processInfo.systemUptime`) and the frontmost bundle ID with an injectable provider (default `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`).
- Test: `leankeys/Tests/LeanKeysKitTests/StrayEnterFilterTests.swift`

**Interfaces:**
```swift
public struct StrayEnterFilter {
    public static let window: TimeInterval = 0.100
    public static let excludedBundleIDs: Set<String>     // spec §17.2 list; plus prefix "com.jetbrains."
    public enum Decision: Equatable { case none, deleteBeforeEnter, dropKey }
    public mutating func decide(keyCode: UInt16, shift: Bool, otherModifiers: Bool, time: TimeInterval,
                                lineBeforeCursor: String, bundleID: String?) -> Decision
}
```
- **Decisions.**
  - At Enter: `deleteBeforeEnter` when the previous key was adjacent (same `shift` meaning), within the window, its character is the last character of `lineBeforeCursor`, and it does not close an open pair on that line. The router returns `(1, [], false)` so Enter follows.
  - At an adjacent key within the window after Enter: `dropKey`. The router returns `.handled((0, [], true))`.
  - Otherwise `.none`.
- **Never** when `otherModifiers` (⌘ ⌥ ⌃) is set, when the bundle is excluded, or when the switch is off.
- **Line text:** the router needs `TextMirror` text since the last newline. Add `public var lineBeforeCursor: String` to `TextMirror` if Task 3 didn't.

- [ ] **Step 1: Failing tests:**
  - `testDeletesStrayBackslashBeforeEnter` (gap 0.040)
  - `testKeepsWhenSlow` (gap 0.101 → none; gap 0.100 → delete)
  - `testDropsStrayAfterEnter`
  - `testOpenPairKept`: line `nói 'xin chào'` + `'`: an odd count before means closing, so keep; also `[ghi chú]`.
  - `testExcludedApps`: `com.apple.Terminal`, `com.jetbrains.intellij`.
  - `testModifiersNeverDropped` (Review Focus 5)
  - Router-level `testRouterDeletesBeforeEnter` through `intercept`, with an injected clock.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `swift test` → pass.
- [ ] **Step 5:** Commit: `4D: drop a key hit together with Enter (spec 17.2)`.

### Task 5: Settings, screenshots, checklist

**Files:**
- Modify:
  - `leankeys/LeanKeysKit/UI/UndoLearningSection.swift`: two toggles; the `Tên đã học` list with delete buttons; ` (viết hoa)` labels for `cap:` rules (show the phrase without the prefix); "Xoá tất cả" also clears learned names.
  - `leankeys/LeanKeysKit/Learn/UndoLearning.swift`: published `autoCapitalize`, `strayEnter`, `names`.
  - `leankeys/Tests/LeanKeysKitTests/UISnapshotTests.swift`: re-render `settings-undo-learning-{light,dark}.png` with fake rules, a `cap:` rule and fake names.
  - `sync/manual-checklist.md`: section "4D" with the six manual checks of spec §17.4. Update the closing count.

- [ ] **Step 1:** Write a failing snapshot test, plus a unit test that "Xoá tất cả" empties both rules and names, and that the `cap:` display text is `hà nội (viết hoa)`.
- [ ] **Step 2:** Implement.
- [ ] **Step 3:** `swift test` → pass; `LEANKEYS_SNAPSHOTS=1 swift test --filter UISnapshotTests` → look at both PNGs.
- [ ] **Step 4:** Update the checklist.
- [ ] **Step 5:** Commit: `4D: settings, screenshots, manual checks`.

### Final verification (controller)
- `.githooks/pre-push --all` → 6/6.
- `sync/check-divergence.sh v1.0.165` → exit 0.
- capbench: fixed rules FP 0.
