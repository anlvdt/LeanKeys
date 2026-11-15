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

Mọi chỗ sửa trong file gốc phải có chú thích `// LEANKEYS-HOOK: <tên>` và được đăng ký trong `sync/hooks.txt`. Tối đa 12 tên hook (10 cho GĐ1–3, thêm 2 cho GĐ4, xem mục 11). Dự kiến:

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
| Gợi ý từ khi gõ (học từ Laban Key) | Vikey `vAutoSwitchCompletions` + UI LeanKeys | 🔄 dữ liệu, ✋ UI | GĐ4 |
| Tự đề xuất gõ tắt từ nội dung lặp lại (địa chỉ, SĐT, MST…) | LeanKeys | — | GĐ4 |
| Tự học từ hoàn tác (từ điển cá nhân Việt/Anh) | LeanKeys | — | GĐ4 |

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

## 11. Giai đoạn 4: Gợi ý thông minh

Thêm ngày 2026-11-15. Laban Key (VNG/Zalo) là app mã nguồn đóng, chỉ chạy trên iOS/Android. LeanKeys chỉ học ý tưởng của nó, không dùng code và không tự cập nhật theo nó. Các tính năng chỉ có ý nghĩa trên màn hình cảm ứng (vẽ dấu, vuốt để gõ, giao diện bàn phím) nằm ngoài phạm vi. GĐ4 gồm ba kế hoạch riêng, làm theo thứ tự **4C (mục 12) → 4B → 4A**. 4C đứng đầu vì gõ trộn Việt/Anh là ưu tiên số một.

### 11.1 4B: Tự đề xuất gõ tắt từ nội dung lặp lại

**Hành vi**
- LeanKeys đếm các cụm đã gõ xong: câu, cụm từ, địa chỉ, số điện thoại, mã số thuế, email, tên riêng. Một cụm kết thúc ở dấu câu, Enter, hoặc khi con trỏ đổi chỗ.
- **Ngưỡng đề xuất** (mặc định, chỉnh được trong Cài đặt): cụm lặp lại ≥ 3 lần trong 30 ngày và dài ≥ 8 ký tự.
- Khi có đề xuất, menu bar hiện "Có N gợi ý gõ tắt". Màn duyệt có ba nút cho từng mục: **Thêm**, **Sửa tên tắt**, **Bỏ qua**. Mục đã bỏ qua được nhớ và không đề xuất lại. Không có gì được thêm khi người dùng chưa bấm Thêm.
- Gõ tắt được ghi vào danh sách gõ tắt có sẵn của Gõ Nhanh, nên chạy với cả hai engine.

**Tự đặt tên tắt**

| Loại nội dung | Nhận dạng | Tên tắt |
|---|---|---|
| Số điện thoại | `0` + 9 số, hoặc `+84` + 9 số; chấp nhận dấu cách, `.`, `-` | `sdt` |
| Mã số thuế | 10 số, hoặc 10 số + `-` + 3 số | `mst` |
| Địa chỉ | có ít nhất 2 trong các từ: số, đường, phố, phường, xã, quận, huyện, thị xã, TP, tỉnh | `dc` |
| Email | định dạng email | `em` |
| Câu / cụm khác | — | chữ cái đầu mỗi từ, bỏ dấu, viết thường (ví dụ "Cảm ơn anh chị đã quan tâm" → `caqt`) |

- Nếu tên đã có thì thêm số: `sdt2`, `sdt3`…
- Tên tắt trùng một từ tiếng Việt hoặc tiếng Anh có thật thì bị loại, rồi thử tên kế tiếp. Việc kiểm tra dùng điểm từ của engine Vikey (`vAutoSwitchWordScore`).

**Bảo mật**
- Mặc định tắt. Lần đầu bật có màn giải thích tính năng làm gì.
- Chỉ xử lý và lưu trên máy, không gửi đi đâu.
- Cụm chưa đạt ngưỡng chỉ được lưu dưới dạng HMAC-SHA256 (khoá ngẫu nhiên giữ trong Keychain) kèm số lần và các ngày gặp. Chữ thật chỉ được giữ khi cụm đạt ngưỡng, và chỉ để hiện trong màn duyệt.
- File dữ liệu được mã hoá bằng khoá trong Keychain. Có nút "Xoá toàn bộ dữ liệu đã học". Mục đã Thêm hay Bỏ qua thì xoá chữ thật khỏi bộ đếm.
- Không bao giờ học từ:
  - Secure Input và ô mật khẩu (AX subrole `AXSecureTextField`);
  - chuỗi 13–19 số đạt kiểm tra Luhn (số thẻ);
  - chuỗi 4–8 số gõ đứng riêng (mã OTP);
  - các app trong danh sách loại trừ. Mặc định danh sách có trình quản lý mật khẩu (1Password, Bitwarden, Keychain Access) và người dùng thêm được app khác.

### 11.2 4A: Gợi ý từ khi gõ
- Khi đang gõ dở một từ, một ô nổi cạnh con trỏ hiện tối đa 3 gợi ý. **Tab** chọn gợi ý đầu, **⌥1–⌥3** chọn theo thứ tự, **Esc** ẩn ô. Mặc định tắt.
- Nguồn gợi ý là `vAutoSwitchCompletions` của engine Vikey (từ tiếng Việt và tiếng Anh, có điểm). Dữ liệu này 🔄 tự cập nhật theo Vikey. Gõ tắt của người dùng khớp tiền tố được xếp lên đầu.
- Vị trí con trỏ lấy qua Accessibility (`kAXBoundsForRangeParameterizedAttribute`). App nào không cung cấp thì không hiện ô gợi ý.
- Không hiện trong ô mật khẩu hay Secure Input, và không hiện trong các app bị loại trừ ở 11.1.

### 11.3 Điểm gắn mới
- `word-commit`: báo cho LeanKeys chữ vừa gõ xong mỗi từ hoặc cụm, với cả hai engine, và cho LeanKeys trả về một bản thay thế (xoá N ký tự, chèn chuỗi). Dùng cho 4C, 4B và 4A.
- `shortcut-store`: thêm gõ tắt vào kho của Gõ Nhanh từ LeanKeys.
- Riêng phím Tab và ⌥1–⌥3 của 4A được xử lý trong `EngineRouter.intercept`, qua điểm `engine-dispatch` đã có.

### 11.4 Test
- **4B, test đơn vị:** nhận dạng từng loại (có các ví dụ sai: số thẻ, OTP, chuỗi ngắn), sinh tên tắt và cách tránh trùng, ngưỡng và cửa sổ 30 ngày, và kiểm tra rằng chữ thật không xuất hiện trong file lưu trước khi cụm đạt ngưỡng.
- **4A:** xếp hạng gợi ý, Tab chèn đúng phần còn thiếu, ẩn ô khi con trỏ đổi chỗ.
- **Thử tay:** địa chỉ hay SĐT gõ 3 lần thì có đề xuất, Thêm xong gõ `sdt` bung ra đúng; ô mật khẩu không bị học.

## 12. 4C: Tự học từ hoàn tác (từ điển cá nhân Việt/Anh)

Thêm ngày 2026-11-15.

**Bối cảnh.** Đo bằng `tools/mixbench` (2026-11-15) cho thấy engine Vikey chỉ sai 0.1–0.2% số từ khi gõ trộn. Phần sai còn lại hầu hết là các cặp từ trùng nhau giữa tiếng Anh và Telex: `cos/có`, `car/cả`, `sex/sẽ`, `nos/nó`, `its/ít`, `queen/quên`, `moon/môn`. Không quy tắc chung nào sửa được hết mà không hỏng tiếng Anh. Đáp án đúng tuỳ người, nên LeanKeys học từ chính người dùng.

### 12.1 Hành vi
- **Tín hiệu học.** Mỗi lần người dùng hoàn tác một lần engine tự đổi từ là một tín hiệu: ⌫⌫ ngay sau khi Vikey tự sửa (Vikey D61), ESC hoặc Backspace hoàn tác auto-restore của Gõ Nhanh, hay đổi ngôn ngữ bằng tay rồi gõ lại đúng từ vừa gõ.
- **Nội dung lưu** là một luật: (từ đứng trước, chuỗi phím của từ) → kết quả người dùng muốn (giữ nguyên phím, hay dạng tiếng Việt). Mỗi luật kèm số lần được xác nhận.
- **Khi nào áp dụng:**
  - Luật có ngữ cảnh (cùng từ đứng trước): áp dụng ngay sau **1** lần hoàn tác.
  - Luật không ngữ cảnh: áp dụng sau **2** lần hoàn tác cùng chiều. Nếu người dùng hoàn tác ngược chiều thì bỏ luật, và luật đó cần thêm 2 lần xác nhận nữa mới được dùng lại.
- **Cách áp dụng.** Khi một từ được chốt (phím cách hoặc dấu câu), nếu có luật khớp và kết quả của engine khác kết quả người dùng muốn, LeanKeys thay từ đó qua `word-commit`. Chạy với cả hai engine.
- **Không cần thao tác.** Tính năng bật sẵn, không có bước cài đặt. Cài đặt có danh sách "Từ đã học" để xem, xoá từng mục, xoá hết, hoặc tắt hẳn.

### 12.2 Bảo mật
- Chỉ lưu những từ người dùng đã hoàn tác, không lưu văn bản khác. Lưu trên máy, mã hoá bằng khoá trong Keychain, không gửi đi đâu.
- Không học trong Secure Input, ô mật khẩu, hay các app bị loại trừ ở 11.1.
- Giới hạn 5.000 luật. Khi đầy, bỏ luật lâu không dùng nhất (LRU).

### 12.3 Liên quan tới repo gốc
- Không sửa `vendor/vikey`. Việc thay từ diễn ra trong LeanKeys, sau khi engine đã ra kết quả.
- Nếu `tools/mixbench` hay báo lỗi của người dùng cho thấy một lỗi chung (không phải sở thích riêng), lỗi đó được đề xuất lên Vikey dưới dạng PR kèm ca test. Mỗi PR chỉ gửi khi người dùng đồng ý.

### 12.4 Test
- **Đơn vị:**
  - Học sau 1 lần (có ngữ cảnh) và sau 2 lần (không ngữ cảnh).
  - Hoàn tác ngược chiều thì bỏ luật.
  - Giới hạn và loại bỏ theo LRU.
  - Không học khi Secure Input bật.
  - Xoá một luật hay xoá hết.
- **mixbench:** thêm chế độ "người dùng tự học". Mỗi từ sai sinh một lần hoàn tác, gõ lại cả kho câu, và báo tỉ lệ sai sau khi học. Mục tiêu: lỗi lặp lại của cùng một cặp từ trong cùng ngữ cảnh giảm về 0.
- **Thử tay:** gõ "its" trong một câu tiếng Anh, ⌫⌫, lần sau trong cùng ngữ cảnh thì giữ "its". Gõ "cos" ở đầu câu tiếng Việt thì ra "có".
