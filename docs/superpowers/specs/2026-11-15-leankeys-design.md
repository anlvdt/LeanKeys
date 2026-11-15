# LeanKeys — Thiết kế

- **Ngày:** 2026-11-15
- **Trạng thái:** Chờ duyệt
- **Tác giả:** Lê An (cùng Claude)

## 1. Mục tiêu

LeanKeys là bộ gõ tiếng Việt cho macOS, phát hành công khai, mã nguồn mở. Nó gom những tính năng tốt nhất và độc nhất của ba bộ gõ mã nguồn mở:

| Nguồn | Repo | Giấy phép | Mốc khi phân tích |
|---|---|---|---|
| Gõ Nhanh | github.com/khaphanspace/gonhanh.org | BSD-3-Clause | v1.0.165, nhánh `main` |
| Vikey | github.com/tonyminibot/Vikey | GPL-3.0 | v1.0.33, nhánh `main` |
| OpenKey | github.com/tuyenvm/OpenKey | GPL-3.0 | 2.0.5 (03/2022, gần như dừng) |

LeanKeys phải **tự nhận thay đổi mới từ các repo gốc** với ít công sức tay nhất có thể.

### Tiêu chí thành công

1. Gõ Telex/VNI ổn định trên mọi app mà Gõ Nhanh đang hỗ trợ, gồm thanh địa chỉ Chrome, Spotlight, Arc, IDE và Terminal.
2. Chọn được engine Gõ Nhanh hoặc engine Vikey trong Cài đặt. Đổi engine không cần khởi động lại app.
3. Mỗi ngày, job đồng bộ kéo release mới nhất của Gõ Nhanh và Vikey, chạy toàn bộ test, rồi build sẵn bản phát hành. Có xung đột hay test hỏng thì báo, không phát hành.
4. Phát hành công khai đúng GPL-3 và ghi công đủ ba tác giả gốc.

### Ngoài phạm vi

- Windows, Linux, iOS, Android.
- Macro của OpenKey: Gõ Nhanh đã có gõ tắt.
- Quick Telex (`cc`→`ch`…) và gõ tắt phụ âm của OpenKey: phải sửa sâu vào engine. Xem lại sau giai đoạn 3.
- Nhật ký gõ để gỡ lỗi của Vikey.
- Ký Developer ID và notarize: chưa có tài khoản Apple Developer. Bước này được dựng sẵn, xem mục 6.4.

## 2. Đánh giá ba nguồn (tóm tắt)

- **Gõ Nhanh:** engine Rust (khoảng 45k dòng kể cả test), thân app SwiftUI, test dày nhất (100k từ tiếng Anh, 22k âm tiết, test hoán vị). Phát triển mạnh nhất, commit hằng ngày. Điểm mạnh riêng: tự khôi phục từ tiếng Anh khi nhấn Space, ESC trả lại phím, sửa dính chữ cho từng app, độ trễ theo app, tự tắt khi dùng bộ gõ khác (Nhật, Hàn, Trung…).
- **Vikey:** fork của OpenKey, engine C++. Điểm mạnh riêng: tự chuyển Việt/Anh theo ngữ cảnh (bigram, từ điển dạng từ SCOWL), nhận ra code, undo ⌫⌫, nhớ ngôn ngữ theo website, bảng chọn emoji. Mỗi quy tắc có test và lý do ghi trong `DECISIONS.md`. Vikey đã bỏ VNI, bảng mã cũ và công cụ chuyển mã.
- **OpenKey:** engine C++ đời cũ, không có test, gần như dừng phát triển. Giá trị còn lại: bảng mã cũ (TCVN3, VNI Windows, CP1258, Unicode tổ hợp) có nhớ theo app, và công cụ chuyển mã.

Hai cơ chế "tiếng Anh tự động" của Gõ Nhanh và Vikey **xung đột nhau** trên cùng luồng phím. Vì vậy LeanKeys cho **chọn engine**, không trộn hai engine.

## 3. Kiến trúc

### 3.1 Nền tảng: fork Gõ Nhanh

Repo LeanKeys là fork của Gõ Nhanh, remote `upstream` là `khaphanspace/gonhanh.org`. Lựa chọn này giúp cả engine lẫn thân app của nguồn phát triển mạnh nhất nhận thay đổi bằng `git merge`.

Hai hướng đã cân nhắc rồi bỏ:
- **Tự viết thân app mới:** mất khả năng tự nhận các bản sửa riêng cho từng app của Gõ Nhanh.
- **Fork Vikey làm thân:** Vikey cập nhật thưa hơn, thiếu các bản sửa theo app, và thân app nặng ObjC++.

Repo được khởi tạo từ thư mục chứa spec này. Lúc triển khai, lịch sử Gõ Nhanh được nối vào bằng `git merge <tag> --allow-unrelated-histories`.

### 3.2 Cấu trúc thư mục

```
LeanKeys/
├── core/                    # engine Rust Gõ Nhanh — KHÔNG sửa
├── platforms/macos/         # thân app Gõ Nhanh — chỉ sửa tại điểm LEANKEYS-HOOK
├── platforms/linux, windows # giữ nguyên để merge sạch, không build
├── vendor/vikey/            # submodule tonyminibot/Vikey, ghim theo tag — KHÔNG sửa
├── leankeys/
│   ├── Engine/              # protocol TypingEngine + adapter Rust, adapter Vikey
│   ├── Features/            # tính năng chuyển tay (website, emoji, bảng mã, chuyển mã)
│   └── Branding/            # tên, icon, bundle ID, About, ACKNOWLEDGEMENTS
├── sync/                    # sync.sh, release.sh, check-divergence.sh, hooks.txt, launchd plist, reports/
├── .githooks/pre-push
└── docs/superpowers/specs/
```

### 3.3 Điểm cắm engine

Hai engine trả về cùng một kiểu kết quả:
- Gõ Nhanh: `RustBridge.processKey(keyCode:caps:ctrl:shift:char:) -> (Int, [Character], Bool)?`, nằm trong `platforms/macos/RustBridge.swift`.
- Vikey: `VikeyDriver::press(key, shift, now) -> VKEdit { deleteCount, text, languageChanged }`, nằm trong `Engine/Driver.h`. Lớp này đã gói tự chuyển Việt/Anh và undo ⌫⌫, và không phụ thuộc nền tảng.

LeanKeys định nghĩa:

```swift
struct EngineEdit { let deleteCount: Int; let text: [Character]; let consumed: Bool; let languageChanged: Bool }
protocol TypingEngine {
    func process(keyCode: UInt16, caps: Bool, ctrl: Bool, shift: Bool, char: Character?) -> EngineEdit?
    func resetContext()          // con trỏ di chuyển hoặc đổi ô nhập
    func setVietnamese(_ on: Bool)
    func applySettings(_ s: LeanSettings)
}
```

- `GoNhanhEngine` bọc `RustBridge`.
- `VikeyEngine` bọc `VikeyDriver` qua một file ObjC++ nhỏ (`leankeys/Engine/VikeyShim.mm`). Phím macOS được đổi sang mã phím của Vikey trong shim.
- `EngineRouter` giữ engine đang dùng và đổi engine ngay khi cài đặt thay đổi.

Trong `KeyboardHookManager` / `keyboardCallback` của Gõ Nhanh, lệnh gọi `RustBridge.processKey` được đổi thành `EngineRouter.shared.process(...)` tại **một** điểm `LEANKEYS-HOOK`. Phần gửi phím, độ trễ theo app và sửa lỗi theo app giữ nguyên.

### 3.4 Điểm gắn vào file gốc

Mọi chỗ sửa trong file gốc phải có chú thích `// LEANKEYS-HOOK: <tên>` và được đăng ký trong `sync/hooks.txt`. Mục tiêu tối đa 10 điểm. Dự kiến:

1. `engine-dispatch`: gọi `EngineRouter` thay cho `RustBridge.processKey`.
2. `engine-reset`: báo `resetContext()` khi con trỏ hoặc ô nhập đổi.
3. `settings-engine`: thêm mục chọn engine vào màn Cài đặt.
4. `updater-url`: đổi URL kiểm tra cập nhật sang repo LeanKeys.
5. `branding`: tên app, bundle ID, icon (Info.plist, project, Assets).
6. `about`: màn Giới thiệu, hiện phiên bản engine gốc và ghi công.
7. `app-switch`: báo đổi app/website cho Features (giai đoạn 2).
8. `output-encoding`: lớp bảng mã sau engine (giai đoạn 3).

### 3.5 Quy tắc khi chọn engine

- Mặc định dùng engine Gõ Nhanh.
- Kiểu gõ VNI chỉ chạy với engine Gõ Nhanh. Khi chọn engine Vikey, mục VNI bị khoá và có ghi chú giải thích.
- Khi dùng engine Vikey, "tự khôi phục từ tiếng Anh" của Gõ Nhanh bị ẩn hoặc tắt, vì Vikey có cơ chế tự chuyển riêng.
- Các cài đặt chung (dấu kiểu mới, viết hoa đầu câu…) được chuyển cho engine nào có hỗ trợ. Engine không hỗ trợ thì mục đó bị làm mờ.

## 4. Tính năng và nguồn gốc

🔄 = tự nhận thay đổi từ repo gốc. ✋ = chuyển tay, repo gốc thay đổi thì job chỉ báo cáo.

| Tính năng | Nguồn | Cập nhật | Giai đoạn |
|---|---|---|---|
| Engine Telex/VNI, tự khôi phục từ tiếng Anh, ESC, viết hoa đầu câu, gõ tắt | Gõ Nhanh `core/` | 🔄 | có sẵn |
| Sửa lỗi theo app, độ trễ theo app, nhớ bật/tắt theo app, theo input source | Gõ Nhanh `platforms/macos` | 🔄 | có sẵn |
| Engine Vikey: tự chuyển theo ngữ cảnh, nhận ra code, undo ⌫⌫, Simple Telex 1/2 | Vikey `Engine/` | 🔄 | GĐ1 |
| Branding, Giới thiệu, ghi công | LeanKeys | — | GĐ1 |
| Job đồng bộ, release.sh, pre-push hook | LeanKeys | — | GĐ1 |
| Nhớ ngôn ngữ theo website | Vikey `App/Core/VikeyCore.mm` | ✋ | GĐ2 |
| Bảng chọn emoji (tìm tiếng Việt và tiếng Anh) | Vikey `App/Views/EmojiPicker.swift`, `App/Model/EmojiSearch.swift`, `Emoji.json` | ✋ (dữ liệu 🔄) | GĐ2 |
| Bảng mã cũ: TCVN3, VNI Windows, CP1258, Unicode tổ hợp, nhớ theo app | OpenKey `engine/` | ✋ | GĐ3 |
| Công cụ chuyển mã văn bản | OpenKey `engine/ConvertTool.cpp` | ✋ | GĐ3 |

**Bảng mã cũ** là lớp chuyển đổi đặt sau engine. Nó đổi `EngineEdit.text` từ Unicode sang bảng mã của app hiện tại, và tính lại `deleteCount` theo số đơn vị mã thực tế, vì một ký tự Việt có thể chiếm 2 byte trong VNI Windows hay Unicode tổ hợp. Nhờ vậy lớp này chạy với cả hai engine.

Mỗi giai đoạn có kế hoạch triển khai riêng. Spec này đủ để lập kế hoạch GĐ1. GĐ2 và GĐ3 sẽ được thiết kế chi tiết hơn khi tới lượt.

## 5. Đồng bộ với repo gốc

### 5.1 Lịch chạy

`sync/com.leankeys.sync.plist` là LaunchAgent của người dùng, chạy `sync/sync.sh` mỗi ngày lúc 03:00 bằng `StartCalendarInterval`. Nếu máy đang ngủ lúc đó, launchd chạy bù khi máy thức. Log ghi vào `sync/reports/`.

### 5.2 Các bước của `sync.sh`

1. Lấy file khoá (`sync/.lock`). Nếu đang có lần chạy khác thì thoát.
2. `git fetch upstream --tags`. Tìm tag release mới nhất của Gõ Nhanh (theo semver, dạng `v*`) và của Vikey (`gh api repos/tonyminibot/Vikey/releases/latest`).
3. Nếu cả hai đều không đổi so với lần trước (lưu trong `sync/state.json`) thì kết thúc.
4. Tạo nhánh `sync/<YYYY-MM-DD>` từ `main`. `git merge <tag Gõ Nhanh>`. Checkout submodule `vendor/vikey` sang tag mới.
5. **Xung đột merge:** `git merge --abort`, ghi báo cáo, gửi thông báo macOS, rồi dừng.
6. Chạy `check-divergence.sh`. Nếu file gốc bị sửa ngoài các điểm đã đăng ký thì báo lỗi.
7. **Theo dõi phần chuyển tay:** so sánh diff của các file nguồn đã chuyển tay (danh sách trong `sync/ported.txt`) giữa tag cũ và tag mới của Vikey và OpenKey. Có thay đổi thì đưa diff vào báo cáo.
8. Chạy test theo mục 7.1, bước 1 đến 4.
9. **Tất cả đạt:** merge nhánh sync vào `main` (fast-forward hoặc merge commit), tăng phiên bản, build DMG ký ad-hoc vào `dist/`, cập nhật `state.json`, rồi gửi thông báo "Bản LeanKeys x.y sẵn sàng — chạy release.sh để đăng".
10. **Có lỗi:** giữ nguyên nhánh sync để xem lại, `main` không đổi, gửi thông báo kèm đường dẫn báo cáo.

`sync.sh` không push và không phát hành.

### 5.3 Phát hành: `release.sh` (do bạn chạy)

1. Kiểm tra `gh auth status` và remote GitHub công khai `LeanKeys`. Repo được tạo ở lần phát hành đầu tiên.
2. Mở DMG, kiểm tra app khởi chạy được. In danh sách thử tay (mục 7.2) và chờ xác nhận.
3. `git push` nhánh `main` cùng tag `vX.Y`, rồi `gh release create` kèm DMG và ghi chú. Ghi chú tự sinh, gồm phiên bản engine gốc và changelog tóm tắt.
4. Nếu lỗi giữa chừng thì xoá release nháp và tag vừa tạo.

## 6. Phát hành và tự cập nhật

### 6.1 Phiên bản

- LeanKeys đánh số riêng: `1.0`, `1.1`, …
- `leankeys/Branding/Versions.json` ghi phiên bản engine gốc. Màn Giới thiệu hiện ví dụ "Gõ Nhanh v1.0.165 · Vikey v1.0.33".

### 6.2 Cập nhật trong app

Dùng lại `UpdateChecker` / `UpdateManager` của Gõ Nhanh (kiểm tra GitHub Releases mỗi 24 giờ). Chỉ đổi URL qua điểm `updater-url`. Không thêm Sparkle.

### 6.3 Quyền Accessibility

Ký ad-hoc khiến mỗi bản build có thể làm macOS mất quyền Accessibility. Khi khởi động, nếu `AXIsProcessTrusted()` trả về false, app hiện màn hướng dẫn cấp lại quyền. Màn này dùng lại onboarding của Gõ Nhanh, chỉ đổi nội dung cho trường hợp "sau khi cập nhật".

### 6.4 Ký app

- Hiện tại: ký ad-hoc (`codesign -s -`). README hướng dẫn chạy `xattr -cr /Applications/LeanKeys.app`.
- Về sau: `release.sh` đọc biến `LEANKEYS_SIGN_IDENTITY` và `LEANKEYS_NOTARY_PROFILE`. Nếu có đủ thì ký Developer ID và notarize. Kiến trúc không đổi.

## 7. Test

### 7.1 Tự động

1. `cargo test` trong `core/`: test gốc của Gõ Nhanh.
2. Test engine của Vikey: `vendor/vikey/Tools/autoswitch/check.sh`, hoặc phần tối thiểu của nó nếu thiếu phụ thuộc. Khi triển khai sẽ xác minh phụ thuộc của script và ghi lại.
3. Test hợp đồng `TypingEngine` (XCTest, trong `platforms/macos/Tests` hoặc target `LeanKeysTests`):
   - **Chung:** `vieejt`→`việt`, `truowfng`→`trường`, Backspace, ESC.
   - **Vikey:** `treen`→`trên`, `more` giữ nguyên, undo ⌫⌫.
   - **Gõ Nhanh:** `push`+Space giữ `push`.
   - **Router:** đổi engine giữa chừng không làm hỏng ô nhập. VNI bị khoá khi dùng Vikey.
4. `check-divergence.sh` và `xcodebuild` bản Release.
5. GĐ3: test bảng mã và chuyển mã, đối chiếu với bảng của OpenKey.

`.githooks/pre-push` chạy 1 đến 4. Bật một lần bằng `git config core.hooksPath .githooks`.

### 7.2 Thử tay trước khi đăng bản

Với cả hai engine, thử trên Chrome (thanh địa chỉ và ô nhập), Spotlight, VS Code, Terminal và Slack. Thêm một lần đổi engine khi đang gõ, và một lần đổi app có nhớ ngôn ngữ.

## 8. Xử lý lỗi

- **Engine Vikey khởi tạo lỗi:** `EngineRouter` quay về engine Gõ Nhanh và hiện cảnh báo một lần trên menu bar. Gõ không bao giờ bị gián đoạn.
- **Job đồng bộ:** có file khoá. Mọi việc diễn ra trên nhánh sync, `main` chỉ đổi khi tất cả đạt. Lỗi mạng hay build thì ghi báo cáo, gửi thông báo, và thử lại vào lần chạy sau.
- **`release.sh`:** kiểm tra trước khi làm. Lỗi thì dọn release nháp và tag.
- **Mất quyền Accessibility:** hiện màn hướng dẫn như mục 6.3, không im lặng ngừng gõ.

## 9. Giấy phép và ghi công

- LeanKeys phát hành theo **GPL-3.0**. `LICENSE` ở gốc repo là GPL-3.0.
- Giữ nguyên văn bản BSD-3 của Gõ Nhanh tại `core/LICENSE` (hoặc `LICENSES/gonhanh-BSD-3.txt`). Giữ mọi dòng bản quyền trong code gốc.
- `ACKNOWLEDGEMENTS.md` và màn Giới thiệu ghi công Gõ Nhanh (khaphanspace và cộng đồng Gõ Nhanh), Vikey (Tony Dinh) và OpenKey (Mai Vũ Tuyên), kèm liên kết repo và giấy phép.
- Tên, icon và bundle ID (`io.github.anlvdt.leankeys`) là của riêng LeanKeys. Không dùng thương hiệu của ba app gốc.

## 10. Rủi ro đã biết

- **Gõ Nhanh đổi cấu trúc `RustBridge` hay `keyboardCallback`:** điểm `engine-dispatch` sẽ xung đột merge. Job dừng và báo, bạn sửa tay một điểm.
- **Vikey đổi API `VikeyDriver`:** build shim lỗi, job dừng và báo.
- **Kích thước app:** dữ liệu của Vikey (bigram khoảng 4.8MB, từ điển dạng từ khoảng 0.3MB) làm app nặng thêm vài MB. Chấp nhận được.
- **macOS thu hồi quyền Accessibility sau mỗi cập nhật do ký ad-hoc:** đã có màn hướng dẫn. Hết hẳn khi có Developer ID.
