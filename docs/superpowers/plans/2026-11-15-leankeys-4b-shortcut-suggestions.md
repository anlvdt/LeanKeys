# LeanKeys 4B: Gợi ý gõ tắt — Kế hoạch triển khai

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gõ tắt bung ra được với cả hai engine. LeanKeys đếm các cụm người dùng gõ lặp lại (địa chỉ, SĐT, MST, email, câu hay dùng) và đề xuất thêm vào danh sách gõ tắt, chỉ cần một cú bấm.

**Architecture:**
- `EngineRouter` giữ một bản sao của chữ vừa gõ (`TextMirror`), cập nhật từ kết quả của cả hai engine. Kết quả của Gõ Nhanh đi vào qua điểm gắn `engine-dispatch` ở cuối `RustBridge.processKey`; kết quả của Vikey có sẵn trong router.
- Khi gặp phím kết thúc từ, mirror cung cấp:
  - từ vừa chốt, để bung gõ tắt khi dùng Vikey (Gõ Nhanh đã tự bung);
  - cụm vừa chốt, để `PhraseLearner` đếm.
- Bộ đếm lưu HMAC trong một file mã hoá, khoá giữ trong Keychain. Đề xuất hiện trong ô nổi trên menu bar. Mỗi lần "Thêm" ghi vào kho gõ tắt có sẵn của Gõ Nhanh qua điểm gắn `shortcut-store`.

**Tech Stack:** Swift 5.9 / SwiftUI (macOS 13), CryptoKit (HMAC-SHA256, AES-GCM), Security.framework (Keychain), C shim của Vikey cho điểm từ.

**Spec:** `docs/superpowers/specs/2026-11-15-leankeys-design.md` — mục 11.1, 11.3, 11.4, 13.2 (4B hỏi một lần), 14 (ô nổi).

## Global Constraints

- **Ngưỡng đề xuất:** ≥ 3 lần trong 30 ngày, dài ≥ 8 ký tự; chỉnh được ở Cài đặt → Nâng cao.
- **Tên tắt:**
  - SĐT `sdt`, MST `mst`, địa chỉ `dc`, email `em`;
  - cụm khác: chữ cái đầu mỗi từ, bỏ dấu, viết thường;
  - trùng tên đã có thì thêm số (`sdt2`…);
  - loại mọi tên tắt trùng một từ tiếng Việt hay tiếng Anh có thật.
- **Nhận dạng:**
  - SĐT: `0` + 9 số hoặc `+84` + 9 số, chấp nhận dấu cách, `.`, `-`;
  - MST: 10 số, hoặc 10 số + `-` + 3 số;
  - địa chỉ: ≥ 2 từ trong danh sách: số, đường, phố, phường, xã, quận, huyện, thị xã, TP, tỉnh;
  - email: theo định dạng email.
- **Bảo mật:**
  - Mặc định tắt. Bật lần đầu thì hiện màn giải thích.
  - Chỉ lưu trên máy.
  - Cụm chưa đạt ngưỡng chỉ lưu HMAC-SHA256 (khoá ngẫu nhiên trong Keychain) kèm số lần và các ngày gặp.
  - Chữ thật chỉ giữ khi đạt ngưỡng, và bị xoá sau khi người dùng bấm Thêm hoặc Bỏ qua.
  - File dữ liệu mã hoá AES-GCM, khoá trong Keychain. Có nút "Xoá toàn bộ dữ liệu đã học".
- **Không học từ:**
  - Secure Input và ô `AXSecureTextField`;
  - chuỗi 13–19 số đạt kiểm tra Luhn;
  - chuỗi 4–8 số đứng riêng (OTP);
  - app bị loại trừ. Mặc định: `com.1password.1password`, `com.bitwarden.desktop`, `com.apple.keychainaccess`, `com.apple.Passwords`.
- **Không tự thêm gõ tắt** khi người dùng chưa bấm Thêm.
- **Quy tắc code gốc:**
  - Mọi dòng sửa trong file gốc có `LEANKEYS-HOOK`.
  - Chỉ thêm đúng một tên hook mới, `shortcut-store`, thành 9 tên.
  - `sync/check-divergence.sh v1.0.165` thoát 0.
  - Không sửa `core/` hay `vendor/vikey/`.
- **Chữ hiển thị (cố định):**
  - Dòng trong ô nổi: `Có N gợi ý gõ tắt`.
  - Nút: `Thêm`, `Sửa`, `Bỏ qua`.
  - Công tắc: `Đề xuất gõ tắt`.
  - Mô tả công tắc, một dòng: `Gợi ý gõ tắt cho nội dung bạn hay gõ lại. Chỉ lưu trên máy.`
  - Màn giải thích lần đầu: `LeanKeys sẽ đếm các cụm bạn gõ lặp lại (địa chỉ, số điện thoại, mã số thuế…) để gợi ý gõ tắt. Dữ liệu chỉ nằm trên máy này, được mã hoá, và bạn xoá được bất cứ lúc nào. Không học trong ô mật khẩu.`
  - Nút xoá: `Xoá dữ liệu đã học`.

## Review Focus

1. **Mirror lệch với chữ thật**, do bấm chuột, phím mũi tên, Cmd+Z hay dán: mirror phải tự xoá, không được bung gõ tắt sai chỗ. Test: `testMirrorResetsOnNavigationAndBypass` (Task 1).
2. **Gõ tắt bung hai lần khi dùng Gõ Nhanh**: Gõ Nhanh đã tự bung, nên router không được bung thêm. Test: `testNoDoubleExpansionOnGoNhanh` (Task 2).
3. **Chữ thật lọt vào file trước ngưỡng**: test đọc file thô và tìm chuỗi. Test: `testPlaintextNeverStoredBelowThreshold` (Task 3).
4. **Học trong ô mật khẩu hay app bị loại trừ**: test với cờ secure và bundle id bị loại. Test: `testSecureAndExcludedNotLearned` (Task 3).
5. **Tên tắt trùng từ thật** (ví dụ "co", "an", "em" là từ tiếng Việt): bộ đặt tên phải bỏ qua và thử tên kế tiếp. "em" là đại từ tiếng Việt, nên email dùng `eml` khi `em` bị loại. Test: `testAbbreviationSkipsRealWords` (Task 4).

---

### Task 1: TextMirror — bản sao chữ vừa gõ cho cả hai engine

**Files:**
- Create: `leankeys/LeanKeysKit/Learn/TextMirror.swift`
- Modify: `leankeys/LeanKeysKit/Engine/EngineRouter.swift`. Router áp từng edit của Vikey và từng phím đi qua tự nhiên vào mirror.
- Modify: `platforms/macos/RustBridge.swift`, trong điểm gắn `engine-dispatch` ở cuối `processKey`: `EngineRouter.shared.observeGoNhanh(keyCode:shift:caps:result:)` với kết quả `(bs, chars, consumed)` của Gõ Nhanh, hoặc `nil`.
- Test: `leankeys/Tests/LeanKeysKitTests/TextMirrorTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct CommittedWord { public let text: String; public let breakChar: Character }
  public struct CommittedPhrase { public let text: String }          // kết thúc ở . ! ? Enter, hoặc khi mirror reset
  public final class TextMirror {
      public func apply(deleteCount: Int, insert: [Character])
      public func typed(_ c: Character)                                // phím đi qua tự nhiên
      public func reset()                                              // điều hướng, click, bypass, đổi app, secure input
      public var onWord: ((CommittedWord) -> Void)?
      public var onPhrase: ((CommittedPhrase) -> Void)?
      public var currentWord: String { get }
  }
  extension EngineRouter {
      public var mirror: TextMirror { get }
      public func observeGoNhanh(keyCode: UInt16, shift: Bool, caps: Bool, result: (Int, [Character], Bool)?)
  }
  ```
- Phím kết thúc từ: phím cách, `, . ; : ! ?`, Return/Enter, Tab. Kết thúc cụm: `. ! ?`, Return/Enter, reset. Giới hạn 500 ký tự mỗi cụm.

- [ ] **Step 1: Viết test hỏng:**
  - `testWordsAndPhrasesFromTypedKeys`: gõ "Số 12 đường Lê Lợi." thì nhận đúng các từ và một cụm `Số 12 đường Lê Lợi`.
  - `testAppliesEngineEdits`: `apply(1, ["ệ"])` sửa chữ cuối của mirror.
  - `testMirrorResetsOnNavigationAndBypass`: mũi tên, Tab, ctrl/cmd và click đều xoá từ và cụm đang gõ, không phát cụm dở.
  - `testPhraseCapped`: cụm dài hơn 500 ký tự bị bỏ.
- [ ] **Step 2:** Chạy `swift test --filter TextMirrorTests`. Mong đợi: FAIL.
- [ ] **Step 3:** Viết `TextMirror`, nối vào router và vào hook của Gõ Nhanh. Cả hai đường cùng phát `onWord`/`onPhrase` theo một chuẩn. `KeyboardHookManager` của Gõ Nhanh xử lý click chuột và đổi app ở đâu thì gọi `mirror.reset()` ở đó, bằng tên hook đã có cho file đó.
- [ ] **Step 4:** `swift test` (PASS), xcodebuild Debug, `check-divergence` (exit 0). Commit `"4B: TextMirror for both engines"`.

### Task 2: Gõ tắt bung với engine Vikey

**Files:**
- Create: `leankeys/LeanKeysKit/Learn/ShortcutExpander.swift`
- Modify: `EngineRouter.swift`. Khi dùng Vikey, gặp phím kết thúc từ mà `mirror.currentWord` khớp gõ tắt thì trả về edit thay thế.
- Modify: `platforms/macos/MainSettingsView.swift`, điểm gắn `shortcut-store` (tên mới) trong `syncShortcutsToEngine`: `EngineRouter.shared.setShortcuts(valid.map { ($0.key, $0.value) })`.
- Test: `leankeys/Tests/LeanKeysKitTests/ShortcutExpanderTests.swift`

**Interfaces:**
- Produces: `public func setShortcuts(_ items: [(trigger: String, replacement: String)])` trên `EngineRouter`, và `ShortcutExpander.expand(word: String) -> String?`. Quy tắc chữ hoa: trigger viết hoa chữ đầu thì kết quả viết hoa chữ đầu; trigger viết hoa hết thì kết quả viết hoa hết (như Gõ Nhanh).

- [ ] **Step 1: Viết test hỏng:**
  - `testExpandsOnSpaceWithVikey`: gõ `vn` + phím cách thì ra `Việt Nam `. Edit gồm xoá 2, chèn `Việt Nam`, và phím cách đi qua.
  - `testCaseRules`: `Vn` ra `Việt Nam`, `VN` ra `VIỆT NAM`.
  - `testNoExpansionMidWord`: `vnexpress` + phím cách không bung.
  - `testNoDoubleExpansionOnGoNhanh`: khi engine đang chạy là `.gonhanh`, router không bao giờ trả edit gõ tắt.
- [ ] **Step 2:** Chạy test. Mong đợi: FAIL.
- [ ] **Step 3:** Viết code. Edit bung ra dùng cơ chế `keyPassesThrough` đã có, để phím cách hay dấu câu đi như phím thật.
- [ ] **Step 4:** `swift test`, xcodebuild, `check-divergence` (9 tên). Thêm vào danh sách thử tay: "Vikey: gõ `vn` + cách trong Notes, Chrome, Slack → `Việt Nam`". Commit `"4B: shortcuts expand with the Vikey engine"`.

### Task 3: PhraseLearner — đếm an toàn

**Files:**
- Create: `leankeys/LeanKeysKit/Learn/PhraseLearner.swift`, `leankeys/LeanKeysKit/Learn/LearnStore.swift` (AES-GCM, Keychain), `leankeys/LeanKeysKit/Learn/Exclusions.swift`
- Test: `leankeys/Tests/LeanKeysKitTests/PhraseLearnerTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct LearnContext { public let bundleID: String?; public let secureInput: Bool; public let secureField: Bool; public let now: Date }
  public final class PhraseLearner {
      public init(store: LearnStore, threshold: Int = 3, windowDays: Int = 30, minLength: Int = 8)
      public var enabled: Bool
      public func observe(_ phrase: CommittedPhrase, context: LearnContext)
      public var ready: [Candidate] { get }           // đã đạt ngưỡng, có chữ thật, chưa xử lý
      public func dismiss(_ c: Candidate)             // nhớ mãi là đã bỏ qua (theo HMAC)
      public func accept(_ c: Candidate)              // xoá chữ thật, đánh dấu đã xử lý
      public func eraseAll()
  }
  public struct Candidate: Identifiable { public let id: String /* HMAC hex */; public let text: String; public let kind: PhraseKind; public let count: Int }
  public enum PhraseKind { case phone, taxCode, address, email, phrase }
  public protocol LearnStore { func load() throws -> Data?; func save(_ data: Data) throws; func erase() throws }
  public final class KeychainEncryptedFileStore: LearnStore { public init(url: URL, keychainService: String = "io.github.anlvdt.leankeys.learn") }
  ```
- Ngoài cụm nguyên văn, mỗi cụm còn được quét để lấy riêng các đoạn SĐT, MST, email, địa chỉ bên trong. Mỗi đoạn đếm như một mục riêng.

- [ ] **Step 1: Viết test hỏng** (dùng một `InMemoryStore` giả, cộng một test cho store thật đọc/ghi qua Keychain dùng service riêng cho test, xoá trong tearDown):
  - `testThresholdAndWindow`: 3 lần trong 30 ngày thì thành `ready`; 3 lần trải trên 40 ngày thì không.
  - `testPlaintextNeverStoredBelowThreshold`: sau 2 lần, dữ liệu thô của store, kể cả dạng plaintext trước khi mã hoá (`store.lastSavedPlaintext` trong store giả), không chứa chữ thật.
  - `testSecureAndExcludedNotLearned`: secure input, secure field và từng bundle bị loại trừ đều không học.
  - `testRejectsCardAndOTP`: `4111 1111 1111 1111` và `482913` không được đếm.
  - `testDetectsKinds`: `0912 345 678` là phone, `0312345678-001` là taxCode, `Số 12 đường Lê Lợi, phường Bến Nghé, quận 1` là address, `an@vidu.vn` là email.
  - `testDismissIsRemembered` và `testAcceptErasesPlaintext`.
  - `testEraseAll`.
- [ ] **Step 2:** Chạy test. Mong đợi: FAIL.
- [ ] **Step 3:** Viết code. HMAC-SHA256 trên chữ đã chuẩn hoá (NFC, viết thường, gộp khoảng trắng). Khoá HMAC và khoá AES nằm trong Keychain, mỗi khoá 32 byte ngẫu nhiên. Ngày gặp lưu theo ngày, và dữ liệu cũ hơn 30 ngày bị cắt bỏ.
- [ ] **Step 4:** `swift test`. Commit `"4B: privacy-preserving phrase learner"`.

### Task 4: Đặt tên tắt

**Files:**
- Create: `leankeys/LeanKeysKit/Learn/Abbreviation.swift`
- Modify: `leankeys/VikeyShim/include/lk_vikey.h`, `leankeys/VikeyShim/lk_vikey.cpp`. Thêm `int lk_vikey_word_score(int vietnamese, const char* letters)`, bọc `vAutoSwitchWordScore`.
- Test: `leankeys/Tests/LeanKeysKitTests/AbbreviationTests.swift`

**Interfaces:**
- Produces: `Abbreviation.suggest(for: Candidate, existing: Set<String>, isRealWord: (String) -> Bool) -> String`. Mặc định `isRealWord` gọi `lk_vikey_word_score` cho cả tiếng Việt lẫn tiếng Anh, điểm > 0 là từ có thật.

- [ ] **Step 1: Viết test hỏng:**
  - `testKindDefaults`: phone ra `sdt`, taxCode ra `mst`, address ra `dc`.
  - `testInitials`: "Cảm ơn anh chị đã quan tâm" ra `caacdqt`. Đây là chữ cái đầu của cả 7 từ; spec ví dụ `caqt`, nhưng quy tắc spec là "chữ cái đầu mỗi từ", nên dùng đủ 7 chữ.
  - `testNumbering`: đã có `sdt` thì ra `sdt2`.
  - `testAbbreviationSkipsRealWords`: email mà `em` là từ thật thì ra `eml`; cụm có chữ đầu tạo thành từ thật thì thêm số.
  - `testIsRealWordUsesVikey`: `isRealWord("khong")` hoặc `isRealWord("the")` là true, `isRealWord("sdt")` là false.
- [ ] **Step 2:** Chạy test. Mong đợi: FAIL.
- [ ] **Step 3:** Viết code.
- [ ] **Step 4:** `swift test`. Commit `"4B: abbreviation suggestions"`.

### Task 5: Giao diện đề xuất, công tắc và đồng ý

**Files:**
- Create: `leankeys/LeanKeysKit/UI/ShortcutSuggestionsView.swift` (danh sách Thêm/Sửa/Bỏ qua), `leankeys/LeanKeysKit/UI/LearnSettingsSection.swift` (công tắc, ngưỡng, danh sách app loại trừ, nút xoá dữ liệu, màn giải thích lần đầu)
- Modify: `leankeys/LeanKeysKit/UI/StatusPopoverView.swift`. Dòng `Có N gợi ý gõ tắt` chỉ hiện khi N > 0, bấm vào mở danh sách.
- Modify, điểm gắn `shortcut-store` trong `MainSettingsView.swift`: một hàm cho LeanKeysKit thêm gõ tắt, `appState.shortcuts.append(ShortcutItem(key:value:))`. Gọi qua closure truyền vào view, nên kho của Gõ Nhanh tự lưu và tự đồng bộ.
- Modify, điểm gắn `settings-engine`: chèn `LearnSettingsSection` vào trang Chung (công tắc) và trang Nâng cao (ngưỡng, danh sách app loại trừ, nút xoá).
- Modify: nối router với learner. `mirror.onPhrase` gọi `learner.observe` với `LearnContext` lấy từ bundle id của app đang dùng, trạng thái Secure Input (`IsSecureEventInputEnabled()`), và subrole AX của ô đang focus.
- Test: `leankeys/Tests/LeanKeysKitTests/ShortcutSuggestionsModelTests.swift`

- [ ] **Step 1: Viết test hỏng** (cho model):
  - `testAcceptAddsShortcutAndClearsCandidate`: closure thêm được gọi với `(sdt, 0912 345 678)`, và candidate biến mất khỏi danh sách.
  - `testEditChangesTrigger`.
  - `testDismissHides`.
  - `testToggleOffStopsObserving`.
  - `testFirstEnableRequiresConsent`: lần bật đầu tiên trả về trạng thái "cần đồng ý" và chưa bật cho tới khi gọi `confirmConsent()`.
- [ ] **Step 2:** Chạy test. Mong đợi: FAIL.
- [ ] **Step 3:** Viết UI theo phong cách mục 14: dùng `SettingsLayout`, `controlSize(.mini)` cho công tắc, chữ phụ màu `secondaryLabelColor`.
- [ ] **Step 4:** `swift test`, xcodebuild, `check-divergence` (9 tên), `zsh tests/build/test_build_output.sh`. Dựng ảnh chụp ô nổi có gợi ý và trang Cài đặt có công tắc, ở chế độ sáng và tối, vào `docs/ui/`, bằng script `ImageRenderer` đã có ở mục 14 nếu có.
- [ ] **Step 5:** Thêm vào danh sách thử tay:
  - bật "Đề xuất gõ tắt" thì hiện màn giải thích;
  - gõ cùng một SĐT 3 lần trong Notes thì ô nổi hiện "Có 1 gợi ý gõ tắt"; bấm Thêm, gõ `sdt` + cách thì bung ra đúng, với cả hai engine;
  - gõ trong ô mật khẩu Safari không tạo gợi ý;
  - bấm "Xoá dữ liệu đã học" thì danh sách trống.
- [ ] **Step 6:** Commit `"4B: shortcut suggestions UI, consent and settings"`. Chạy `.githooks/pre-push --all`, mong đợi thoát 0.
