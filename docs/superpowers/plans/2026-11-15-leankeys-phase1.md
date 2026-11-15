# LeanKeys Giai đoạn 1: Kế hoạch triển khai

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fork Gõ Nhanh thành app LeanKeys. Cho chọn engine Gõ Nhanh hoặc Vikey. Gắn job launchd tự kéo release gốc, chạy test, build sẵn bản phát hành, và có `release.sh` để bạn đăng bản.

**Architecture:** Repo là fork Gõ Nhanh (remote `upstream`). Engine Vikey nằm trong submodule `vendor/vikey`, được biên dịch nguyên bản qua một Swift package ở gốc repo (`Package.swift`). Package gồm target C++ `VikeyEngine`, target C shim `VikeyShim`, và target Swift `LeanKeysKit`. App Gõ Nhanh gọi `LeanKeysKit` tại các điểm `// LEANKEYS-HOOK: <tên>` được đăng ký trong `sync/hooks.txt`. Đổi tên app làm ở bước build (ghi đè biến xcodebuild, PlistBuddy, thay icon), không sửa file gốc.

**Tech Stack:** Swift 5.9+ / SwiftUI (macOS 13), C++17 (Vikey), Rust (Gõ Nhanh core, có sẵn), SwiftPM, xcodebuild, zsh, launchd, `gh` CLI.

**Spec:** `docs/superpowers/specs/2026-11-15-leankeys-design.md`

## Global Constraints

- Tag gốc ban đầu: Gõ Nhanh `v1.0.165`, Vikey `v1.0.33`. Sync luôn dùng **tag release**, không dùng nhánh.
- Không sửa `core/`, `vendor/vikey/`, `README.md`, `CONTRIBUTORS.md`. Mọi sửa đổi trong file gốc phải có `// LEANKEYS-HOOK: <tên>` (hoặc `<!-- -->` / `#` tuỳ ngôn ngữ) và nằm trong `sync/hooks.txt`. Tối đa 10 tên hook.
- Tên app `LeanKeys`. Bundle ID `io.github.anlvdt.leankeys`. Repo phát hành `github.com/anlvdt/LeanKeys`.
- Giấy phép GPL-3.0 ở `LICENSE`. Văn bản BSD-3 của Gõ Nhanh giữ ở `LICENSES/gonhanh-BSD-3.txt`.
- Ký ad-hoc (`codesign --force --deep -s -`). Nếu có `LEANKEYS_SIGN_IDENTITY` và `LEANKEYS_NOTARY_PROFILE` thì dùng Developer ID và notarize.
- Engine mặc định: `gonhanh`. Khoá UserDefaults: `LeanKeys.engine`, giá trị `"gonhanh"` hoặc `"vikey"`.
- VNI chỉ chạy với engine Gõ Nhanh.
- `sync.sh` không bao giờ push hay phát hành. `main` chỉ đổi khi mọi bước đều đạt.
- README công khai nằm ở `.github/README.md` (GitHub ưu tiên file này hơn `README.md` ở gốc). `README.md` gốc được bot của Gõ Nhanh sửa hằng ngày, nên không đụng vào.

## Review Focus

1. **Gõ trong ô mật khẩu / Secure Input khi dùng engine Vikey:** Gõ Nhanh có `SecureInputStateTracker`. Router phải đứng ngoài khi `ctrl`/bypass bật và không giữ ký tự. Test: `testBypassResetsAndPassesThrough` (Task 3).
2. **Đổi engine khi đang gõ dở một từ:** từ dở không được sinh xoá/chèn sai. Test: `testSwitchEngineMidWordClearsState` (Task 3).
3. **Phím Vikey không phải chữ (mũi tên, Tab, Return, click chuột):** phải gọi `resetContext()`, không tạo edit thừa. Test: `testNavigationKeyResetsContext` (Task 2).
4. **Vikey tự chuyển ngôn ngữ thì icon menu bar phải đổi theo**, không lệch với trạng thái engine. Test: `testLanguageChangeNotification` (Task 3), cộng mục thử tay ở Task 5.
5. **Upstream thêm file mới hay đổi project.pbxproj ngay chỗ hook gói package:** sync phải dừng có báo cáo, không phát hành bản hỏng. Test: `test_conflict_aborts` (Task 7).

---

### Task 1: Khởi tạo fork, submodule, giấy phép, kiểm tra hook

**Files:**
- Modify: repo `~/Desktop/01_DEV_PROJECTS/MyApps/LeanKeys` (đã có commit spec)
- Create: `LICENSE` (GPL-3.0 nguyên văn), `LICENSES/gonhanh-BSD-3.txt` (dùng `git mv LICENSE` trước khi tạo LICENSE mới)
- Create: `.gitmodules`, `vendor/vikey` (submodule)
- Create: `sync/hooks.txt`, `sync/check-divergence.sh`, `sync/upstream.json`
- Test: `tests/sync/test_check_divergence.sh`

**Interfaces:**
- Produces: `sync/upstream.json` = `{"gonhanh": "v1.0.165", "vikey": "v1.0.33"}`, lưu tag đang dùng. Task 6, 7 và 8 đọc và ghi file này.
- Produces: `sync/hooks.txt`, mỗi dòng `<tên-hook>\t<đường-dẫn-file>`. Dòng `FILE\t<đường-dẫn>` cho phép thay hẳn một file gốc (chỉ dùng cho `LICENSE`).
- Produces: `sync/check-divergence.sh <tag-gonhanh>`, thoát 0 nếu đạt. Thoát 1 và in `file:dòng` vi phạm nếu không.

- [ ] **Step 1:** `git remote add upstream https://github.com/khaphanspace/gonhanh.org.git && git fetch upstream --tags`, rồi `git merge v1.0.165 --allow-unrelated-histories -m "Fork Gõ Nhanh v1.0.165"`. Kiểm tra: `git log --oneline | head` có cả commit spec lẫn lịch sử Gõ Nhanh.
- [ ] **Step 2:** `git submodule add https://github.com/tonyminibot/Vikey.git vendor/vikey && git -C vendor/vikey checkout v1.0.33`.
- [ ] **Step 3:** Chạy `cd core && cargo test`. Kết quả mong đợi: mọi test PASS. Đây là mốc gốc trước khi sửa gì.
- [ ] **Step 4: Viết test hỏng** `tests/sync/test_check_divergence.sh` (zsh, tự tạo repo tạm bằng `git init`). Các trường hợp:
  - `test_clean_passes`: không sửa gì, thoát 0.
  - `test_hooked_line_passes`: sửa file X, mọi dòng thêm hoặc đổi đều chứa `LEANKEYS-HOOK: a`, có dòng `a\tX` trong hooks.txt. Thoát 0.
  - `test_unhooked_line_fails`: thêm một dòng không có marker. Thoát 1, output chứa `X:`.
  - `test_unregistered_hook_fails`: marker `LEANKEYS-HOOK: b` chưa có trong hooks.txt. Thoát 1.
  - `test_file_allowlist`: `FILE\tLICENSE` cho phép thay hẳn LICENSE.
  - `test_new_files_ignored`: file mới (không có ở tag gốc) không bị kiểm tra.
- [ ] **Step 5:** Chạy `zsh tests/sync/test_check_divergence.sh`. Kết quả mong đợi: FAIL (script chưa có).
- [ ] **Step 6:** Viết `sync/check-divergence.sh`.
  - Dùng `git diff -U0 <tag> -- . ':!vendor' ':!leankeys' ':!sync' ':!tests/sync' ':!docs/superpowers' ':!Package.swift' ':!.github/README.md' ':!ACKNOWLEDGEMENTS.md' ':!.githooks' ':!.gitmodules'`, chỉ xét file đã có ở tag gốc (`--diff-filter=M`).
  - Một dòng `+` hoặc `-` hợp lệ khi chính nó chứa marker, hoặc khi nó thuộc một khối liền nhau bắt đầu bằng dòng marker `LEANKEYS-HOOK-BEGIN: <tên>` và kết thúc bằng `LEANKEYS-HOOK-END`.
- [ ] **Step 7:** Chạy test. Kết quả mong đợi: PASS cả 6.
- [ ] **Step 8:** `git mv LICENSE LICENSES/gonhanh-BSD-3.txt`. Thêm `LICENSE` GPL-3.0 nguyên văn (lấy từ `vendor/vikey/LICENSE`). Thêm dòng `FILE\tLICENSE` vào hooks.txt. Chạy `sync/check-divergence.sh v1.0.165`, kết quả mong đợi thoát 0.
- [ ] **Step 9:** Commit `"Bootstrap LeanKeys: fork, Vikey submodule, divergence check"`.

### Task 2: Engine Vikey trong Swift package

**Files:**
- Create: `Package.swift` (gốc repo, `platforms: [.macOS(.v13)]`, `cxxLanguageStandard: .cxx17`)
- Create: `leankeys/VikeyShim/include/lk_vikey.h`, `leankeys/VikeyShim/lk_vikey.cpp`
- Create: `leankeys/LeanKeysKit/Engine/TypingEngine.swift`, `leankeys/LeanKeysKit/Engine/VikeyEngine.swift`
- Test: `leankeys/Tests/LeanKeysKitTests/VikeyEngineTests.swift`

**Interfaces:**
- Produces (C API, `lk_vikey.h`):
  ```c
  typedef struct { int deleteCount; int length; uint16_t text[256]; int languageChanged; } lk_edit;
  int  lk_vikey_init(void);                       // 1 = ok
  void lk_vikey_press(uint16_t macKeyCode, int shift, double now, lk_edit* out);
  void lk_vikey_reset_context(void);
  void lk_vikey_set_language(int vietnamese);     // 1 = Việt, 0 = Anh
  int  lk_vikey_language(void);
  void lk_vikey_set_options(int modernOrthography, int autoSwitch, int telexStyle);
  ```
- Produces (Swift):
  ```swift
  public struct EngineEdit: Equatable { public let deleteCount: Int; public let text: [Character]; public let languageChanged: Bool }
  public protocol TypingEngine: AnyObject {
      func process(keyCode: UInt16, caps: Bool, shift: Bool) -> EngineEdit?   // nil = để phím đi qua
      func resetContext()
      func setVietnamese(_ on: Bool)
      var isVietnamese: Bool { get }
  }
  public final class VikeyEngine: TypingEngine { public init?() }   // nil khi lk_vikey_init() lỗi
  ```

- [ ] **Step 1:** Viết `Package.swift` với ba target:
  - `VikeyEngine` (C++): `path: "vendor/vikey/Engine"`, `sources: ["Engine.cpp", "Vietnamese.cpp", "SmartSwitchKey.cpp", "Driver.cpp"]`, `publicHeadersPath` trỏ tới thư mục rỗng `leankeys/VikeyEngineHeaders` (tạo nếu cần, vì Engine/ không có `include/`), `cxxSettings: [.headerSearchPath("platforms"), .unsafeFlags(["-w"])]`.
  - `VikeyShim`: `path: "leankeys/VikeyShim"`, phụ thuộc `VikeyEngine`, `cxxSettings: .headerSearchPath("../../vendor/vikey/Engine")` và `.headerSearchPath("../../vendor/vikey/Engine/platforms")`.
  - `LeanKeysKit` (Swift): phụ thuộc `VikeyShim`.
  - Test target `LeanKeysKitTests`.
  - Nếu SwiftPM từ chối path ngoài package root thì Package.swift đã ở gốc repo, nên `vendor/` nằm trong root. Không cần symlink.
- [ ] **Step 2: Viết test hỏng** `VikeyEngineTests`. Helper `type(_ keys: String) -> String` mô phỏng ô nhập: với mỗi phím, áp `deleteCount` rồi nối `text`. Nếu `nil` thì nối chính ký tự phím. Bảng mã phím mac lấy từ `vendor/vikey/Engine/platforms/mac.h`.
  - `testTelexBasic`: `type("vieejt ")` == `"việt "`. `type("truowfng ")` == `"trường "`.
  - `testAutoSwitchToVietnameseFromEnglish`: đặt `setVietnamese(false)`, `type("treen ")` == `"trên "`, sau đó `isVietnamese == true`.
  - `testEnglishStaysEnglish`: `type("more ")` == `"more "`.
  - `testUndoTwoBackspaces`: tiếng Anh, `type("dduowcj ")` == `"được "`. Thêm ⌫ thì còn `"được"`. Thêm ⌫ nữa thì thành `"dduowcj"`.
  - `testNavigationKeyResetsContext`: `type("vie")`, gửi phím ← (123) thì nhận `nil`. Sau đó `type("ej")` không được xoá chữ trước mũi tên (kết quả là `"vie"` + kết quả gõ `ej` như từ mới).
  - `testLanguageChangedFlag`: lần tự chuyển trong `testAutoSwitch…` trả về `languageChanged == true` đúng một lần.
- [ ] **Step 3:** Chạy `swift test --filter VikeyEngineTests`. Kết quả mong đợi: FAIL (chưa có kiểu).
- [ ] **Step 4:** Viết `lk_vikey.cpp`.
  - Định nghĩa các biến toàn cục mà engine cần, đúng như `vendor/vikey/Tools/autoswitch/driver/undo_test.cpp` dòng 7 (copy danh sách và giá trị mặc định). Bổ sung nếu linker còn báo thiếu symbol.
  - Giữ một `static VikeyDriver*`. `press` chép `VKEdit` vào `lk_edit`, cắt ở 256 ký tự.
  - `set_options` gán `vUseModernOrthography`, `vAutoSwitchByTyping` và `vTelexStyle`, rồi gán `driver->autoSwitch`.
- [ ] **Step 5:** Viết `VikeyEngine.swift`. Quy tắc trả về:
  - `deleteCount == 0` và `text` đúng bằng ký tự của phím vừa gõ: trả về `nil`, để phím gốc đi qua.
  - Edit rỗng: `nil`.
  - Còn lại: `EngineEdit`.
  - Phím điều hướng (123–126, 48 Tab, 36/76 Return, 53 ESC): gọi `resetContext()` rồi trả về `nil`. Riêng Return đi qua `press` trước (Vikey dùng Return để chốt từ), sau đó mới reset.
- [ ] **Step 6:** Chạy `swift test`. Kết quả mong đợi: PASS. Chạy thêm `cd vendor/vikey && Tools/autoswitch/check.sh`, kết quả mong đợi thoát 0 (engine gốc vẫn đạt test của nó, chỉ cần clang++ và python3).
- [ ] **Step 7:** Chạy `sync/check-divergence.sh v1.0.165`, kết quả mong đợi thoát 0. Commit `"Add Vikey engine via LeanKeysKit package"`.

### Task 3: EngineRouter: chọn engine, VNI, dự phòng, đồng bộ ngôn ngữ

**Files:**
- Create: `leankeys/LeanKeysKit/Engine/EngineRouter.swift`, `leankeys/LeanKeysKit/Engine/LeanSettings.swift`
- Test: `leankeys/Tests/LeanKeysKitTests/EngineRouterTests.swift`

**Interfaces:**
- Consumes: `TypingEngine`, `VikeyEngine`, `EngineEdit` (Task 2).
- Produces:
  ```swift
  public enum EngineKind: String { case gonhanh, vikey }
  public enum InterceptResult { case passToGoNhanh; case handled((Int, [Character], Bool)?) }  // khớp kiểu trả về của RustBridge.processKey; không Equatable (tuple), test dùng `if case`
  public extension Notification.Name { static let leanKeysLanguageChanged: Notification.Name }      // userInfo["vietnamese": Bool]
  public final class EngineRouter {
      public static let shared: EngineRouter
      public init(defaults: UserDefaults = .standard, makeVikey: () -> TypingEngine? = { VikeyEngine() })
      public var selected: EngineKind { get set }       // ghi vào UserDefaults "LeanKeys.engine"
      public var active: EngineKind { get }             // == selected, trừ khi VNI hoặc Vikey init lỗi thì là .gonhanh
      public private(set) var fallbackReason: String?   // "vni" | "vikey-init-failed" | nil
      public func intercept(keyCode: UInt16, caps: Bool, ctrl: Bool, shift: Bool) -> InterceptResult
      public func setMethod(_ method: Int)              // 0 = Telex, 1 = VNI (giá trị của Gõ Nhanh)
      public func setEnabled(_ vietnamese: Bool)
      public func clear()
  }
  ```

- [ ] **Step 1: Viết test hỏng** `EngineRouterTests`. Dùng `UserDefaults(suiteName:)` riêng và một `FakeEngine: TypingEngine` ghi lại các lời gọi.
  - `testDefaultIsGoNhanh`: `selected == .gonhanh`. `intercept(...) == .passToGoNhanh`.
  - `testVikeySelectedHandles`: `selected = .vikey`, `intercept` trả `.handled` với kết quả FakeEngine đã đổi kiểu (`EngineEdit` thành `(deleteCount, text, true)`, `nil` thành `nil`).
  - `testVNIForcesGoNhanh`: `selected = .vikey`, `setMethod(1)` thì `active == .gonhanh`, `fallbackReason == "vni"`, `intercept == .passToGoNhanh`.
  - `testVikeyInitFailureFallsBack`: `makeVikey: { nil }` thì `active == .gonhanh`, `fallbackReason == "vikey-init-failed"`.
  - `testBypassResetsAndPassesThrough`: engine Vikey, `ctrl: true` thì kết quả `.handled(nil)` và FakeEngine nhận `resetContext()`.
  - `testSwitchEngineMidWordClearsState`: đổi `selected` gọi `resetContext()` trên engine cũ và mới. Lần `intercept` đầu sau khi đổi không có `deleteCount > 0`.
  - `testLanguageChangeNotification`: FakeEngine trả edit có `languageChanged: true` thì `.leanKeysLanguageChanged` được post với `vietnamese == fake.isVietnamese`. Dùng `expectation(forNotification:)`.
  - `testSetEnabledForwardsToVikey`: `setEnabled(false)` gọi `setVietnamese(false)`.
- [ ] **Step 2:** Chạy `swift test --filter EngineRouterTests`. Kết quả mong đợi: FAIL.
- [ ] **Step 3:** Viết `EngineRouter` và `LeanSettings`. `VikeyEngine` chỉ được tạo một lần, khi lần đầu cần. Notification post trên main queue (`DispatchQueue.main.async`), vì event tap chạy trên run loop chính, không chặn callback.
- [ ] **Step 4:** Chạy `swift test`. Kết quả mong đợi: PASS. Commit `"Add EngineRouter"`.

### Task 4: Gắn LeanKeysKit vào app Gõ Nhanh

**Files:**
- Modify: `platforms/macos/GoNhanh.xcodeproj/project.pbxproj`: thêm local package reference tới `../..` và product `LeanKeysKit`. Trong pbxproj không dùng được comment marker, nên thêm `FILE\tplatforms/macos/GoNhanh.xcodeproj/project.pbxproj` vào hooks.txt. Ghi trong hooks.txt rằng chỉ được thêm khối package, không sửa gì khác.
- Modify: `platforms/macos/RustBridge.swift`: hook `engine-dispatch` (đầu `processKey`), `engine-method` (`setMethod`), `engine-enabled` (`setEnabled`), `engine-reset` (`clearBuffer` và `clearBufferAll`), cộng `import LeanKeysKit` có marker.
- Modify: `platforms/macos/MenuBar.swift`: hook `language-sync`, quan sát `.leanKeysLanguageChanged` và gán `appState.isEnabled` theo `vietnamese`. Không gọi lại `RustBridge.setEnabled` theo vòng lặp: chỉ gán khi giá trị khác.
- Modify: `sync/hooks.txt`

**Interfaces:**
- Consumes: `EngineRouter.shared.intercept/setMethod/setEnabled/clear`, `.leanKeysLanguageChanged` (Task 3).

- [ ] **Step 1:** Thêm package trong Xcode, hoặc sửa pbxproj bằng tay: `XCLocalSwiftPackageReference` với `relativePath = ../..`, `XCSwiftPackageProductDependency` `LeanKeysKit` cho target GoNhanh. Chạy `xcodebuild -project platforms/macos/GoNhanh.xcodeproj -scheme GoNhanh -configuration Debug build`. Kết quả mong đợi: `BUILD SUCCEEDED`. Build cần có `libgonhanh_core.a`: chạy `scripts/build/core.sh` trước nếu thiếu.
- [ ] **Step 2:** Thêm hook `engine-dispatch` ngay sau `guard isInitialized`:
  ```swift
  if case .handled(let r) = EngineRouter.shared.intercept(keyCode: keyCode, caps: caps, ctrl: ctrl, shift: shift) { return r } // LEANKEYS-HOOK: engine-dispatch
  ```
  Thêm `EngineRouter.shared.setMethod(method)` vào `setMethod`, `EngineRouter.shared.setEnabled(enabled)` vào `setEnabled`, và `EngineRouter.shared.clear()` vào hai hàm clear. Mỗi dòng có marker tương ứng.
- [ ] **Step 3:** Thêm hook `language-sync` vào MenuBar.swift, ở chỗ `appState` được dùng gần dòng 259 (`RustBridge.setEnabled(appState.isEnabled)`).
- [ ] **Step 4:** Chạy `sync/check-divergence.sh v1.0.165`, kết quả mong đợi thoát 0. Chạy `cd core && cargo test` và `swift test`, kết quả mong đợi PASS. Chạy lại xcodebuild, kết quả mong đợi `BUILD SUCCEEDED`.
- [ ] **Step 5: Thử tay**, ghi kết quả vào commit message. Chạy app Debug, cấp quyền Accessibility. Đổi `defaults write org.gonhanh.GoNhanh LeanKeys.engine vikey` rồi khởi động lại (chưa đổi bundle ID). Gõ trong TextEdit:
  - `vieejt ` ra `việt `.
  - Ở chế độ Anh, `treen ` ra `trên ` và icon menu bar đổi sang Việt.
  - Đổi lại `gonhanh` thì gõ như Gõ Nhanh gốc.
- [ ] **Step 6:** Commit `"Hook EngineRouter into Gõ Nhanh key path"`.

### Task 5: Mục chọn engine trong Cài đặt

**Files:**
- Create: `leankeys/LeanKeysKit/UI/EngineSettingsSection.swift`
- Modify: `platforms/macos/MainSettingsView.swift`: hook `settings-engine`, chèn `EngineSettingsSection()` vào danh sách section.
- Test: `leankeys/Tests/LeanKeysKitTests/EngineSettingsModelTests.swift`

**Interfaces:**
- Consumes: `EngineRouter.shared.selected/active/fallbackReason`.
- Produces: `public struct EngineSettingsSection: View`. `public final class EngineSettingsModel: ObservableObject` có `@Published var selected: EngineKind`, `var vikeyDisabledReason: String?`.

Chữ hiển thị (cố định):
- Tiêu đề: `Engine gõ`.
- Lựa chọn: `Gõ Nhanh (mặc định)` và `Vikey — tự chuyển Việt/Anh theo ngữ cảnh`.
- Khi đang dùng VNI: `Vikey không hỗ trợ VNI — đang dùng Gõ Nhanh`.
- Khi Vikey khởi tạo lỗi: `Không khởi động được engine Vikey — đang dùng Gõ Nhanh`.
- Ghi chú dưới lựa chọn Vikey (thay cho việc làm mờ từng mục của Gõ Nhanh, để không thêm hook): `Khi dùng Vikey, các mục Tự khôi phục tiếng Anh và VNI của Gõ Nhanh không có tác dụng.`

- [ ] **Step 1: Viết test hỏng:**
  - `testModelReflectsRouter`: model.selected đổi thì router.selected đổi theo.
  - `testVNIReasonShown`: router `setMethod(1)` thì `vikeyDisabledReason == "Vikey không hỗ trợ VNI — đang dùng Gõ Nhanh"`.
- [ ] **Step 2:** Chạy `swift test --filter EngineSettingsModelTests`. Kết quả mong đợi: FAIL.
- [ ] **Step 3:** Viết model và view. Dùng `Picker(.radioGroup)`, nằm trong khung tương tự `SettingsRow` (view đó nằm trong app, package không thấy, nên dựng khung tương tự trong package).
- [ ] **Step 4:** Chạy `swift test`. Kết quả mong đợi: PASS. Chèn hook, xcodebuild ra `BUILD SUCCEEDED`, `check-divergence` thoát 0.
- [ ] **Step 5: Thử tay:** đổi engine trong Cài đặt, gõ ngay, không cần khởi động lại. Chọn VNI thì hiện dòng lý do. Commit `"Add engine picker to settings"`.

### Task 6: Thương hiệu, Giới thiệu, ghi công, URL cập nhật, build ra LeanKeys.app

**Files:**
- Create: `leankeys/Branding/Branding.swift` (trong LeanKeysKit: `public enum LeanBranding { name = "LeanKeys", repository = "https://github.com/anlvdt/LeanKeys", releasesAPI = "https://api.github.com/repos/anlvdt/LeanKeys/releases", issuesURL = repository + "/issues" }`)
- Create: `leankeys/LeanKeysKit/UI/AcknowledgementsSection.swift`, `leankeys/LeanKeysKit/Resources/Versions.json` (`{"leankeys":"1.0","gonhanh":"v1.0.165","vikey":"v1.0.33"}`)
- Create: `leankeys/Branding/AppIcon.icns`, icon riêng cho LeanKeys. Dùng skill `ios-icon-gen` hoặc tự vẽ, rồi xuất bằng `iconutil`.
- Create: `leankeys/build.sh`, `ACKNOWLEDGEMENTS.md`, `.github/README.md`
- Modify: `platforms/macos/AppMetadata.swift` (hook `app-metadata`: `name`, `displayName`, `website`, `repository`, `issuesURL` lấy từ `LeanBranding`)
- Modify: `platforms/macos/UpdateChecker.swift` (hook `updater-url`: `githubAPIURL = LeanBranding.releasesAPI`)
- Modify: màn Giới thiệu của Gõ Nhanh (tìm chỗ dùng `AppMetadata.repository` trong `SettingsView.swift`/`MainSettingsView.swift`), hook `about`, chèn `AcknowledgementsSection()`.
- Test: `leankeys/Tests/LeanKeysKitTests/BrandingTests.swift`, `tests/build/test_build_output.sh`

**Interfaces:**
- Produces: `leankeys/build.sh [--version X.Y] [--dmg]`, ghi ra `dist/LeanKeys.app` và, nếu có `--dmg`, `dist/LeanKeys-X.Y.dmg`. Thoát khác 0 nếu bất kỳ bước nào lỗi. Task 7 và 8 gọi script này.
- Produces: `LeanVersions.load() -> (leankeys: String, gonhanh: String, vikey: String)` đọc `Versions.json`.

- [ ] **Step 1: Viết test hỏng** `BrandingTests`:
  - `testVersionsLoad`: `LeanVersions.load()` khớp `Versions.json`.
  - `testAcknowledgementsMentionAllSources`: chuỗi ghi công chứa `Gõ Nhanh`, `BSD-3-Clause`, `Vikey`, `Tony Dinh`, `OpenKey`, `Mai Vũ Tuyên`, `GPL-3.0`.
- [ ] **Step 2: Viết test hỏng** `tests/build/test_build_output.sh`. Sau khi chạy `leankeys/build.sh --version 1.0`, kiểm tra:
  - `CFBundleIdentifier == io.github.anlvdt.leankeys`.
  - `CFBundleName` và `CFBundleDisplayName == LeanKeys`.
  - `CFBundleShortVersionString == 1.0`.
  - `CFBundleIconFile == AppIcon` và không có `CFBundleIconName`.
  - `codesign --verify --deep dist/LeanKeys.app` thoát 0.
- [ ] **Step 3:** Chạy cả hai test. Kết quả mong đợi: FAIL.
- [ ] **Step 4:** Viết `leankeys/build.sh`:
  1. `scripts/build/core.sh`.
  2. `xcodebuild -project platforms/macos/GoNhanh.xcodeproj -scheme GoNhanh -configuration Release PRODUCT_NAME=LeanKeys PRODUCT_BUNDLE_IDENTIFIER=io.github.anlvdt.leankeys MARKETING_VERSION=<ver> -derivedDataPath build/dd`.
  3. Copy sang `dist/LeanKeys.app`.
  4. `PlistBuddy` đặt `CFBundleDisplayName`, xoá `CFBundleIconName`, đặt `CFBundleIconFile=AppIcon`, copy `AppIcon.icns` vào `Contents/Resources`.
  5. Ký app: ad-hoc, hoặc Developer ID theo Global Constraints.
  6. Nếu có `--dmg`: `hdiutil create -volname LeanKeys -srcfolder dist/LeanKeys.app -ov -format UDZO`.
- [ ] **Step 5:** Viết `LeanBranding`, `LeanVersions`, `AcknowledgementsSection` và các hook. `ACKNOWLEDGEMENTS.md` liệt kê ba repo, tác giả và giấy phép (BSD-3 trích nguyên văn từ `LICENSES/gonhanh-BSD-3.txt`). `.github/README.md` (tiếng Việt) gồm: giới thiệu, tải về, `xattr -cr /Applications/LeanKeys.app`, cấp quyền Accessibility, chọn engine, ghi công, giấy phép.
- [ ] **Step 6:** Chạy `swift test` và `zsh tests/build/test_build_output.sh`. Kết quả mong đợi: PASS. Chạy `check-divergence` (thoát 0) và `cargo test` (PASS).
- [ ] **Step 7: Thử tay:** mở `dist/LeanKeys.app` và cấp quyền.
  - Menu bar, Cài đặt và Giới thiệu hiện "LeanKeys" kèm "Gõ Nhanh v1.0.165 · Vikey v1.0.33".
  - Không chạy song song với app Gõ Nhanh gốc.
  - Thử Chrome (thanh địa chỉ), Spotlight, VS Code, Terminal và Slack với cả hai engine.
- [ ] **Step 8: Quyền Accessibility (spec 6.3):** tắt quyền LeanKeys trong System Settings, rồi mở lại app. Mong đợi: màn onboarding của Gõ Nhanh hiện ra, hướng dẫn cấp quyền. Nếu nó chỉ hiện ở lần chạy đầu, thêm hook `accessibility-guard` vào chỗ app khởi động: kiểm tra `AXIsProcessTrusted()` và mở lại onboarding. Ghi kết quả vào commit.
- [ ] **Step 9:** Commit `"Brand as LeanKeys, acknowledgements, build script"`.

### Task 7: Job đồng bộ `sync.sh` và launchd

**Files:**
- Create: `sync/sync.sh`, `sync/ported.txt`, `sync/com.leankeys.sync.plist`, `sync/install-launchd.sh`
- Create: `sync/reports/.gitkeep`. Thêm vào `.gitignore`: `sync/reports/*.md`, `sync/.lock`, `dist/`, `build/`.
- Test: `tests/sync/test_sync.sh`

**Interfaces:**
- Consumes: `sync/upstream.json`, `sync/check-divergence.sh` (Task 1), `leankeys/build.sh` (Task 6), `leankeys/LeanKeysKit/Resources/Versions.json`.
- Produces: `sync/sync.sh [--repo DIR] [--no-notify] [--skip-build]`. Mã thoát: 0 = không có gì mới hoặc đã có bản sẵn sàng; 2 = xung đột merge; 3 = test hay build lỗi; 4 = đang có lần chạy khác. Báo cáo ghi ở `sync/reports/<YYYY-MM-DD>.md`. Bản sẵn sàng ở `dist/LeanKeys-<ver>.dmg`, kèm file `dist/READY` chứa `<ver>`. Task 8 đọc `dist/READY`.
- Produces: `sync/ported.txt`, mỗi dòng `<repo>\t<đường-dẫn-trong-repo-gốc>` cho các file chuyển tay. GĐ1 có thể để trống, chỉ có tiêu đề cột. GĐ2 và GĐ3 sẽ thêm dòng.

- [ ] **Step 1: Viết test hỏng** `tests/sync/test_sync.sh`. Test dựng repo upstream giả và submodule Vikey giả bằng `git init` trong thư mục tạm, rồi chạy `sync.sh --repo <bản-clone> --no-notify --skip-build`. Biến `LEANKEYS_UPSTREAM_URL` và `LEANKEYS_VIKEY_URL` cho phép trỏ tới repo giả.
  - `test_no_new_tags_exits_0_without_branch`: không có tag mới thì thoát 0 và không tạo nhánh `sync/*`.
  - `test_new_tag_merges_to_main`: upstream có tag `v1.0.166` sửa một file không có hook thì thoát 0, `main` chứa commit mới, và `upstream.json.gonhanh == "v1.0.166"`.
  - `test_conflict_aborts`: upstream sửa đúng dòng hook thì thoát 2, `main` không đổi, không còn merge dở (`git status` sạch), báo cáo chứa `CONFLICT`.
  - `test_failing_tests_keep_main`: biến `LEANKEYS_TEST_CMD=false` thì thoát 3, `main` không đổi, nhánh `sync/<ngày>` còn lại.
  - `test_lock_prevents_overlap`: có sẵn `sync/.lock` với PID đang chạy thì thoát 4.
  - `test_ported_file_change_reported`: `ported.txt` có `vikey\tApp/Core/VikeyCore.mm`, tag Vikey mới sửa file đó thì báo cáo có mục `Cần chuyển tay` kèm diff.
- [ ] **Step 2:** Chạy `zsh tests/sync/test_sync.sh`. Kết quả mong đợi: FAIL.
- [ ] **Step 3:** Viết `sync.sh` theo spec mục 5.2.
  - Tag mới nhất của Gõ Nhanh: `git tag -l 'v*' --sort=-v:refname | grep -v -- '-pre' | head -1`.
  - Tag Vikey: `git -C vendor/vikey fetch --tags`, cùng cách lọc.
  - Lệnh test mặc định (`LEANKEYS_TEST_CMD`) chạy `.githooks/pre-push --all`, có từ Task 8.
  - Phiên bản mới = phần minor của `Versions.json.leankeys` cộng 1. Ghi phiên bản mới cùng hai tag gốc vào `Versions.json` và commit trên nhánh sync trước khi build.
  - Thông báo: `osascript -e 'display notification "<msg>" with title "LeanKeys"'`.
  - File khoá: ghi PID vào `sync/.lock`. Nếu PID cũ không còn chạy thì coi khoá đã hết hạn và chạy tiếp.
- [ ] **Step 4:** Chạy test. Kết quả mong đợi: PASS cả 6.
- [ ] **Step 5:** Viết `com.leankeys.sync.plist`:
  - `Label` = `com.leankeys.sync`.
  - `ProgramArguments` = `/bin/zsh -lc "<repo>/sync/sync.sh"`.
  - `StartCalendarInterval` = `{Hour:3, Minute:0}`.
  - `StandardOutPath` và `StandardErrorPath` = `<repo>/sync/reports/launchd.log`.
  - `install-launchd.sh` thay `<repo>`, copy vào `~/Library/LaunchAgents/`, rồi chạy `launchctl bootstrap gui/$(id -u)`.
- [ ] **Step 6:** Chạy `sync/install-launchd.sh`, rồi `launchctl kickstart gui/$(id -u)/com.leankeys.sync`. Kết quả mong đợi: `sync/reports/<hôm nay>.md` được tạo, thường ghi "không có tag mới". Commit `"Add upstream sync job"`.

### Task 8: `release.sh` và pre-push hook

**Files:**
- Create: `sync/release.sh`, `.githooks/pre-push`, `sync/manual-checklist.md`
- Test: `tests/sync/test_release.sh`

**Interfaces:**
- Consumes: `dist/READY`, `dist/LeanKeys-<ver>.dmg` (Task 7), `Versions.json` (Task 6).
- Produces: `.githooks/pre-push [--all]` chạy theo thứ tự:
  1. `cd core && cargo test`
  2. `swift test`
  3. `vendor/vikey/Tools/autoswitch/check.sh`
  4. `sync/check-divergence.sh $(jq -r .gonhanh sync/upstream.json)`
  5. `zsh tests/sync/test_check_divergence.sh && zsh tests/sync/test_sync.sh`
  6. Chỉ khi có `--all`: `leankeys/build.sh` và `tests/build/test_build_output.sh`
- Produces: `sync/release.sh [--dry-run]`.

`manual-checklist.md` gồm 7 mục theo spec mục 7.2: Chrome (thanh địa chỉ và ô nhập), Spotlight, VS Code, Terminal, Slack, đổi engine khi đang gõ, đổi app có nhớ ngôn ngữ. Mỗi mục thử với cả hai engine.

- [ ] **Step 1: Viết test hỏng** `tests/sync/test_release.sh`. Dùng `--dry-run`, và `gh` giả qua `PATH` ghi lại các tham số được gọi.
  - `test_no_ready_exits_1`: không có `dist/READY` thì thoát 1, thông báo "Chưa có bản sẵn sàng".
  - `test_dry_run_prints_plan`: có READY `1.1` thì output chứa `gh release create v1.1` và `LeanKeys-1.1.dmg`, `gh` giả không bị gọi.
  - `test_failure_cleans_up`: `gh` giả lỗi ở bước upload thì script gọi `gh release delete v1.1 --yes` và `git push --delete origin v1.1`, rồi thoát khác 0.
- [ ] **Step 2:** Chạy test. Kết quả mong đợi: FAIL.
- [ ] **Step 3:** Viết `release.sh`:
  1. `gh auth status`.
  2. Nếu chưa có remote `origin`: `gh repo create anlvdt/LeanKeys --public --source . --remote origin`, rồi `gh api -X PUT repos/anlvdt/LeanKeys/actions/permissions -F enabled=false` để tắt các workflow Gõ Nhanh mang theo.
  3. `hdiutil attach` để kiểm tra DMG có `LeanKeys.app`, rồi `detach`.
  4. In `manual-checklist.md`, chờ gõ `yes`.
  5. `git tag vX.Y && git push origin main vX.Y`.
  6. `gh release create vX.Y dist/LeanKeys-X.Y.dmg --title "LeanKeys X.Y" --notes "<Gõ Nhanh tag · Vikey tag + git log tóm tắt từ tag trước>"`.
  7. Xoá `dist/READY`.
  - Nếu có lỗi sau bước 5: dọn dẹp như trong test.
- [ ] **Step 4:** Viết `.githooks/pre-push` (zsh, `set -e`). Thêm hướng dẫn `git config core.hooksPath .githooks` vào `.github/README.md`, mục "Phát triển".
- [ ] **Step 5:** Chạy `zsh tests/sync/test_release.sh` (kết quả mong đợi PASS), rồi `.githooks/pre-push --all` (kết quả mong đợi thoát 0).
- [ ] **Step 6:** Commit `"Add release script and pre-push gate"`. **Không chạy `release.sh` thật.** Lần đăng bản đầu tiên do bạn quyết định.
