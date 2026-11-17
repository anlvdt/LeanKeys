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

1. Gõ Telex/VNI ổn định trên mọi app mà Gõ Nhanh đang hỗ trợ, gồm thanh địa chỉ Chrome, Spotlight, Arc, IDE và Terminal (Terminal bỏ từ 2026-11-17: phím đi thẳng, mục 18).
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

- Mặc định dùng engine **Vikey** (đổi ngày 2026-11-15, xem mục 13). Gõ Nhanh chọn được trong Cài đặt, và là engine dự phòng khi Vikey lỗi hoặc khi dùng VNI.
- Kiểu gõ VNI chỉ chạy với Gõ Nhanh: chọn VNI thì LeanKeys tự dùng Gõ Nhanh và ghi chú lý do dưới mục Lõi gõ.
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
9. **Tất cả đạt:** merge nhánh sync vào `main` (fast-forward hoặc merge commit), tăng phiên bản, build DMG ký ad-hoc vào `dist/`, cập nhật `state.json`, rồi gửi thông báo "Bản LeanKeys x.y sẵn sàng — chạy zsh sync/release.sh để đăng".
10. **Có lỗi:** giữ nguyên nhánh sync để xem lại, `main` không đổi, gửi thông báo kèm đường dẫn báo cáo.

`sync.sh` không push và không phát hành.

### 5.3 Phát hành: `release.sh` (do bạn chạy)

1. Kiểm tra `gh auth status` và remote GitHub công khai `LeanKeys`. Repo được tạo ở lần phát hành đầu tiên.
2. Mở DMG, kiểm tra app khởi chạy được. In danh sách thử tay (mục 7.2) và chờ xác nhận.
3. `git push` nhánh `main` cùng tag `vX.Y`, rồi `gh release create` kèm DMG và ghi chú. Ghi chú tự sinh: một dòng hướng dẫn cài cho người dùng, phiên bản lõi gõ gốc ("Lõi gõ: …"), rồi "Thay đổi kỹ thuật" (các commit).
4. Nếu lỗi giữa chừng thì xoá release nháp và tag vừa tạo.

## 6. Phát hành và tự cập nhật

### 6.1 Phiên bản

- LeanKeys đánh số riêng: `1.0`, `1.1`, …
- `leankeys/Branding/Versions.json` ghi phiên bản engine gốc. Màn Giới thiệu hiện ví dụ "Gõ Nhanh v1.0.165 · Vikey v1.0.33".

### 6.2 Cập nhật trong app

Dùng lại `UpdateChecker` / `UpdateManager` của Gõ Nhanh (kiểm tra GitHub Releases mỗi 24 giờ). Chỉ đổi URL qua điểm `updater-url`. Không thêm Sparkle.

### 6.3 Quyền Accessibility

Từ mục 15 (2026-11-15): app được ký bằng một chứng chỉ tự cấp cố định, nên macOS giữ quyền Accessibility qua các bản cập nhật. Màn hướng dẫn cấp lại quyền chỉ còn dùng cho lần cập nhật chuyển từ ad-hoc sang chứng chỉ, hoặc khi chứng chỉ bị đổi. Xem mục 15.

### 6.4 Ký app

- Hiện tại: ký bằng chứng chỉ tự cấp `LeanKeys Self-Signed` trong Keychain của máy build (mục 15). Không có chứng chỉ thì `build.sh` quay về ký ad-hoc (`codesign -s -`). README vẫn hướng dẫn chạy `xattr -cr /Applications/LeanKeys.app`, vì Gatekeeper không tin chứng chỉ tự cấp.
- Về sau: `release.sh` đọc biến `LEANKEYS_SIGN_IDENTITY` và `LEANKEYS_NOTARY_PROFILE`. Nếu có đủ thì ký Developer ID và notarize. Kiến trúc không đổi.

## 7. Test

### 7.1 Tự động

1. `cargo test` trong `core/`: test gốc của Gõ Nhanh.
2. Test engine của Vikey: `vendor/vikey/Tools/autoswitch/check.sh`, hoặc phần tối thiểu của nó nếu thiếu phụ thuộc. Khi triển khai sẽ xác minh phụ thuộc của script và ghi lại.
3. Test hợp đồng `TypingEngine` (XCTest, trong `platforms/macos/Tests` hoặc target `LeanKeysTests`):
   - **Chung:** `vieejt`→`việt`, `truowfng`→`trường`, Backspace, ESC.
   - **Vikey:** `treen`→`trên`, `more` giữ nguyên, undo ⌫⌫.
   - **Gõ Nhanh:** `push`+Space giữ `push`.
   - **Router:** đổi engine giữa chừng không làm hỏng ô nhập. Chọn VNI khi đang dùng Vikey thì router chuyển sang Gõ Nhanh.
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

### 11.1 4B: Gợi ý gõ tắt từ nội dung lặp lại

**Hành vi**
- LeanKeys đếm các cụm đã gõ xong: câu, cụm từ, địa chỉ, số điện thoại, mã số thuế, email, tên riêng. Một cụm kết thúc ở dấu câu, Enter, hoặc khi con trỏ đổi chỗ.
- **Ngưỡng đề xuất** (mặc định, chỉnh được trong Cài đặt): cụm lặp lại ≥ 3 lần trong 30 ngày và dài ≥ 8 ký tự.
- Khi có đề xuất, menu bar hiện "Có N gợi ý gõ tắt". Màn duyệt có ba nút cho từng mục: **Thêm** (vào Bảng gõ tắt), **Sửa** (đổi từ viết tắt), **Bỏ qua**. Ô từ viết tắt có tooltip "Gõ “sdt” rồi dấu cách để chèn nội dung này". Sửa sai thì báo `Từ viết tắt này đã có trong Bảng gõ tắt` hoặc `Từ viết tắt không được để trống hoặc chứa dấu cách`. Mục đã bỏ qua được nhớ và không đề xuất lại. Không có gì được thêm khi người dùng chưa bấm Thêm.
- Gõ tắt được ghi vào danh sách gõ tắt có sẵn của Gõ Nhanh, nên chạy với cả hai engine.
- Trên giao diện, tính năng chỉ có một tên: công tắc ở Chung, thẻ ở Nâng cao và dòng trên ô nổi đều gọi là `Gợi ý gõ tắt`.

**Tự đặt từ viết tắt**

| Loại nội dung | Nhận dạng | Từ viết tắt |
|---|---|---|
| Số điện thoại | `0` + 9 số, hoặc `+84` + 9 số; chấp nhận dấu cách, `.`, `-` | `sdt` |
| Mã số thuế | 10 số, hoặc 10 số + `-` + 3 số | `mst` |
| Địa chỉ | có ít nhất 2 trong các từ: số, đường, phố, phường, xã, quận, huyện, thị xã, TP, tỉnh | `dc` |
| Email | định dạng email | `em` |
| Câu / cụm khác | — | chữ cái đầu mỗi từ, bỏ dấu, viết thường (ví dụ "Cảm ơn anh chị đã quan tâm" → `caqt`) |

- Nếu tên đã có thì thêm số: `sdt2`, `sdt3`…
- Từ viết tắt trùng một từ tiếng Việt hoặc tiếng Anh có thật thì bị loại, rồi thử tên kế tiếp. Việc kiểm tra dùng điểm từ của engine Vikey (`vAutoSwitchWordScore`).

**Bảo mật**
- Mặc định tắt. Lần đầu bật có màn giải thích tính năng làm gì.
- Chỉ xử lý và lưu trên máy, không gửi đi đâu.
- Cụm chưa đạt ngưỡng chỉ được lưu dưới dạng HMAC-SHA256 (khoá ngẫu nhiên giữ trong tệp riêng, xem mục 20) kèm số lần và các ngày gặp. Chữ thật chỉ được giữ khi cụm đạt ngưỡng, và chỉ để hiện trong màn duyệt.
- File dữ liệu được mã hoá bằng khoá trong tệp riêng (mục 20). Có nút "Xoá dữ liệu gợi ý gõ tắt" (chỉ xoá dữ liệu của 4B; Bảng gõ tắt, "Từ giữ nguyên" và "Tên đã học" vẫn còn). Mục đã Thêm hay Bỏ qua thì xoá chữ thật khỏi bộ đếm.
- Không bao giờ học từ:
  - Secure Input và ô mật khẩu (AX subrole `AXSecureTextField`);
  - chuỗi 13–19 số đạt kiểm tra Luhn (số thẻ);
  - chuỗi 4–8 số gõ đứng riêng (mã OTP);
  - các app trong danh sách loại trừ. Mặc định danh sách có trình quản lý mật khẩu (1Password, Bitwarden, Keychain Access) và người dùng thêm được app khác.
  - **(sửa 2026-11-16)** một dòng chỉ có một từ, hoặc có một từ trông như mật khẩu (từ 6 ký tự trở lên trộn chữ với số hay ký hiệu, hoặc trộn số với ký hiệu, không thuộc SĐT, MST, email hay địa chỉ đã nhận dạng). Mật khẩu gõ ở chỗ macOS không đánh dấu là ô mật khẩu (dấu nhắc `sudo`/`ssh` trong terminal, ô đăng nhập tự làm của một số app) cũng kết thúc bằng Enter, nên trước đây lọt vào gợi ý. Danh sách loại trừ mặc định có thêm các terminal (Terminal, iTerm2, Warp, Ghostty, Alacritty, kitty, WezTerm, Hyper, Tabby). Gợi ý đã lưu mà vi phạm quy tắc này bị xoá ở lần mở app kế tiếp.

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
- **4B, test đơn vị:** nhận dạng từng loại (có các ví dụ sai: số thẻ, OTP, chuỗi ngắn), sinh từ viết tắt và cách tránh trùng, ngưỡng và cửa sổ 30 ngày, và kiểm tra rằng chữ thật không xuất hiện trong file lưu trước khi cụm đạt ngưỡng.
- **4A:** xếp hạng gợi ý, Tab chèn đúng phần còn thiếu, ẩn ô khi con trỏ đổi chỗ.
- **Thử tay:** địa chỉ hay SĐT gõ 3 lần thì có đề xuất, Thêm xong gõ `sdt` bung ra đúng; ô mật khẩu không bị học.

## 12. 4C: Sửa lỗi gõ và tự học từ hoàn tác

Viết ngày 2026-11-15, viết lại ngày 2026-11-16 sau khi đo. Người dùng muốn hướng tối ưu cho người Việt và không cần hỏi lại. Họ phàn nàn: "gõ tiếng Việt mà sai là nó chuyển sang tiếng Anh, rồi phải mất công chuyển lại hoặc xoá hết gõ lại".

**Đo trước khi thiết kế** (bản dựng thử trên engine Vikey thật; kho `chat_messages` 1.869 tin, 20.676 từ). Mỗi chế độ chèn lỗi vào 50% số từ tiếng Việt, hoặc 50% số từ tiếng Anh cho các chế độ tiếng Anh; người gõ sửa lỗi bằng ⌫ như người thật:

| Lỗi rồi sửa bằng ⌫ | Vikey hiện tại | Có sửa ⌫ (12.1) | Từ hỏng thêm / từ được sửa |
|---|---|---|---|
| Không có lỗi | VN 0.15% · EN 0.25% | như cũ | 0 / 0 |
| Phím dấu bấm đúp rồi ⌫ (`hocjj⌫`) | **VN 28.64%** | **VN 0.95%** | 6 / 3.113 |
| Chữ thừa rồi ⌫ | VN 9.54% | VN 9.09% | 4 / 54 |
| Sai giữa từ, xoá lùi gõ lại | VN 7.43% | VN 7.43% | 8 / 8 |
| Chữ cuối gõ đúp trong từ tiếng Anh rồi ⌫ | EN 7.37% | EN 4.43% | 5 / 282 |
| Chữ thừa trong từ tiếng Anh rồi ⌫ | EN 4.75% | EN 4.69% | 1 / 7 |

- **Nguyên nhân chính.** Bấm một phím dấu hai lần (`ss`, `jj`, `xx`…) là "huỷ dấu" trong Telex. Vikey hiểu lần bấm thứ hai là dấu hiệu của từ tiếng Anh: nó trả cả từ về chữ thô và **chuyển ngôn ngữ sang Anh ngay giữa từ** (`học` + `j` → `hocj`, biểu tượng thành EN). Sau đó ⌫ chỉ xoá chữ thô (`hoc`), nên người dùng phải đổi ngôn ngữ lại hoặc xoá cả từ.
- **Lỗi không sửa thì gần như vô hại.** Một từ gõ sai mà không sửa chỉ làm các từ tiếng Việt *phía sau* sai thêm 0.05–0.13 điểm phần trăm (0.15% → 0.20–0.28%), vì Vikey tự chuyển lại ở từ kế tiếp.
- **Bỏ phương án "dựng lại engine sau mỗi ⌫".** Phương án này làm số từ tiếng Anh sai tăng gấp đôi (4.43% → 9.66%) mà tiếng Việt không khá hơn.
- **Lỗi ngữ cảnh còn lại** là các cặp từ trùng nhau giữa tiếng Anh và Telex (`cos/có`, `car/cả`, `been/bên`…). Đáp án đúng tuỳ người, nên LeanKeys học từ chính người dùng (12.2).

### 12.1 ⌫ ngay sau phím gõ đúp: lấy lại chữ trước đó
- **Khi nào kích hoạt.** Người dùng bấm ⌫ ngay sau một phím thoả cả bốn điều kiện:
  - (a) giống hệt phím ngay trước nó (bấm đúp);
  - (b) đã thay chữ có sẵn chứ không chỉ thêm chữ;
  - (c) để lại một từ không phải tiếng Việt hợp lệ;
  - (d) **hoặc** làm Vikey chuyển sang tiếng Anh giữa một từ bắt đầu bằng tiếng Việt, **hoặc** đã thêm dấu vào một từ toàn chữ không dấu (`qua` + `a` → `quâ`).
- **Kết quả.** ⌫ đưa từ về đúng như trước phím bấm đúp và giữ tiếng Việt:
  - `hocjj⌫` → `học`; `tieengss⌫` → `tiếng`; `ddaxx⌫` → `đã`; `quaa⌫` → `qua`.
  - Engine được nạp lại đúng chữ đó, nên gõ tiếp vẫn bỏ dấu và đổi dấu bình thường.
- **Không kích hoạt khi từ tiếng Anh phổ biến hơn.** Nếu chữ trên màn hình là một từ tiếng Anh, nó chỉ được thay khi chữ trước đó là từ tiếng Việt có điểm từ điển ≥ điểm tiếng Anh. Điểm lấy từ `vAutoSwitchWordScore`.
  - `userr⌫` → `use`, giữ nguyên như Vikey.
  - `coss⌫` → `có`; `carr⌫` → `cả`.
- **Mọi trường hợp khác** (⌫ sau phím không bấm đúp, ⌫ sau khi từ hợp lệ, ⌫ lần hai…) giữ nguyên hành vi của Vikey.
- **Nơi xử lý.** Lớp shim C++ (`leankeys/VikeyShim`). Shim giữ một bản sao chữ đang gõ trên màn hình, dựng từ chính các bản sửa nó trả về, rồi trả về một bản sửa: xoá cả từ, gõ lại từ cũ, kèm `languageChanged` nếu ngôn ngữ đổi về Việt.
  - Không sửa `vendor/vikey`.
  - Không thêm điểm gắn vào code Gõ Nhanh.

### 12.2 Tự học từ hoàn tác
- **Tín hiệu học.** Khi người dùng bấm ⌫⌫ ngay sau một lần Vikey tự đổi từ (hành vi có sẵn của Vikey):
  - "Tự đổi" gồm đổi Anh → Việt (`cos` → `có`) và trả về tiếng Anh (`ít` → `its`).
  - Shim báo lại: chữ trước khi đổi, chữ sau khi đổi, và từ đứng trước.
  - Chỉ ⌫⌫ là tín hiệu. Đổi ngôn ngữ bằng tay rồi gõ lại thì không tính, vì khó đoán đúng ý.
- **Luật.** Một luật gồm: từ đứng trước (có thể trống), chữ trước khi đổi (viết thường), và quyết định "giữ nguyên, không đổi".
  - Luật có từ đứng trước được dùng ngay sau **1** lần hoàn tác.
  - Luật không có từ đứng trước được dùng sau **2** lần hoàn tác cùng chữ, ở bất kỳ ngữ cảnh nào.
- **Áp dụng.** Đúng lúc Vikey sắp đổi một từ, shim gọi bộ lọc (một callback C) do LeanKeys đăng ký. Nếu luật nói "giữ", shim làm ⌫⌫ hộ bên trong engine và gõ lại phím ngắt.
  - Kết quả là một bản sửa duy nhất, nên màn hình không nhấp nháy.
  - Ngôn ngữ trở về như trước lần đổi đó.
- **Đổi ý.** Ngay sau khi luật vừa giữ nguyên một từ, nếu người dùng bấm ⌫⌫ thì shim áp lại đúng lần đổi của engine, và đó là một **lần hoàn tác ngược chiều**:
  - Luật của chữ đó (mọi ngữ cảnh) bị bỏ.
  - Chữ đó bị chặn: phải có thêm 2 lần hoàn tác cùng chiều mới tạo lại luật.
- **Từ đứng trước** là từ liền trước trong cùng dòng, viết thường. Bấm chuột, phím mũi tên, chuyển app hay Enter thì coi như không có từ đứng trước.
- **Chỉ cho engine Vikey** (chế độ "Tự động", mặc định).
  - Gõ Nhanh chỉ được dùng cho VNI (gõ dấu bằng số, nên gần như không trùng với tiếng Anh) hoặc khi người dùng tự chọn.
  - Làm cho Gõ Nhanh phải sửa lõi Rust của repo gốc.

### 12.3 Cài đặt và bảo mật
- **Bật sẵn, không có bước cài đặt.** Cả 12.1 và 12.2 đều bật mặc định.
- **Trang Nâng cao có thẻ "Tự sửa và tự học" gồm:**
  - công tắc "Sửa lỗi bấm đúp phím dấu", dòng phụ "Bấm ⌫ ngay sau khi lỡ bấm đúp: hocjj⌫ → học";
  - công tắc "Nhớ từ bạn giữ nguyên", dòng phụ "Bấm ⌫⌫ ngay sau khi một từ bị tự đổi: lần sau giữ nguyên";
  - danh sách "Từ giữ nguyên" (chữ, từ đứng trước nếu có, số lần), mỗi mục có nút xoá; khi trống ghi "Chưa có. Bấm ⌫⌫ ngay sau khi một từ bị tự đổi để thêm.";
  - nút "Xoá tất cả", hỏi lại kèm dòng "Mọi từ giữ nguyên và tên đã học sẽ bị xoá. Không hoàn tác được.".
- Mỗi dòng phụ chỉ một dòng (mục 14.3), đủ chữ trong tooltip.
- **Lưu trữ.** Chỉ lưu những chữ người dùng đã hoàn tác, không lưu văn bản khác.
  - File `~/Library/Application Support/LeanKeys/undo-rules.bin`, quyền 0600, mã hoá AES-GCM bằng khoá trong tệp riêng (mục 20).
  - Dùng lại `KeychainEncryptedFileStore` của 4B với tên file riêng.
  - Không gửi đi đâu.
- **Giới hạn 5.000 luật.** Khi đầy, bỏ luật lâu không dùng nhất (LRU).
- **Không học trong:** Secure Input, ô mật khẩu, và các ứng dụng trong danh sách "Không học khi gõ trong" của 4B (tooltip của danh sách nói nó áp dụng cho cả 4B, 4C và 4D). Luật đã học vẫn được áp dụng ở mọi nơi engine chạy.
  - **(2026-11-17, audit bảo mật MEDIUM-2)** "Ô mật khẩu" ở đây là mọi ô mà phần gõ cho phím đi thẳng (`KeyPassthrough.isCredentialField`, mục 18): ô mật khẩu, ô tên đăng nhập, email, số điện thoại, mã OTP… chứ không chỉ `AXSecureTextField`. Đọc thuộc tính lỗi hay hết giờ vẫn coi là ô mật khẩu (tối đa 3 × 25 ms trên hàng đợi nền).
- **(sửa 2026-11-16, đánh giá toàn ứng dụng) Không hỏi AX trên luồng phím.** Trên luồng phím (event tap) chỉ đọc những gì không cần hỏi app khác: bundle ID và pid của app đang dùng (`NSWorkspace`), `IsSecureEventInputEnabled()`, thời điểm. Secure Input và app bị loại trừ được quyết ngay ở đó, trước khi đưa gì vào hàng đợi. Việc hỏi ô đang có con trỏ có phải ô mật khẩu không (AX, tối đa 2 × 25 ms) chạy trên hàng đợi nền ghi việc học (hàng đợi ghi của 4C và tên tự học, hàng đợi của 4B); ô mật khẩu, lỗi hay hết giờ thì bỏ lần học đó như trước. Chữ gõ chuyển sang hàng đợi chỉ nằm trong bộ nhớ. Kiểm tra từ điển của tên tự học vẫn chạy trên luồng phím (ruling R4). Ô được hỏi là ô đang có con trỏ lúc hàng đợi chạy, vài ms sau phím: chuyển rất nhanh từ ô mật khẩu sang ô thường trước lúc đó thì ô thường được hỏi; Secure Input (đọc trên luồng phím) vẫn là lớp chặn chính.

### 12.4 Test
- **Shim (C++ qua Swift, engine thật):**
  - Các ví dụ của 12.1, gồm `userr⌫`, `coss⌫`, gõ tiếp sau khi sửa (`hocjj⌫` + ` ` → `học `), và ⌫ sau phím không bấm đúp giữ hành vi cũ.
  - Bộ lọc giữ nguyên trả về một bản sửa duy nhất đúng.
  - Báo hoàn tác có đủ chữ trước, chữ sau và từ đứng trước.
  - ⌫⌫ sau khi giữ nguyên thì áp lại lần đổi.
- **Luật (Swift):**
  - Có ngữ cảnh dùng sau 1 lần, không ngữ cảnh sau 2 lần.
  - Ngược chiều thì bỏ luật và chặn chữ.
  - LRU 5.000; xoá một luật, xoá hết; tắt thì không học và không áp dụng.
  - File lưu không chứa chữ ở dạng rõ.
  - Không học khi Secure Input bật hay trong ô mật khẩu.
- **mixbench:** thêm `tools/mixbench/lk.cpp` (chạy qua shim thật thay vì `Driver`) và `typo.py` (các chế độ lỗi của bảng trên).
  - README ghi kết quả.
  - Yêu cầu: chế độ không có lỗi không đổi, và không chế độ nào có số từ sai tăng so với Vikey.
- **Thử tay:**
  - `hocjj` rồi ⌫ ra `học`, biểu tượng vẫn VI.
  - Gõ "its" trong câu tiếng Anh, ⌫⌫, lần sau trong cùng ngữ cảnh giữ "its".
  - Gõ "cos" hai lần ở hai câu khác nhau, mỗi lần ⌫⌫, lần thứ ba giữ "cos".
  - Trong ô mật khẩu không học.

## 13. Mặc định "cài xong là gõ"

Thêm ngày 2026-11-15. **Mục tiêu:** người dùng chỉ cần mở máy và gõ. Mọi thứ khác tự chạy.

### 13.1 Những bước không bỏ được
- **Cấp quyền Accessibility một lần** khi cài. macOS bắt buộc với mọi bộ gõ kiểu này.
- **Khi còn ký ad-hoc** thì có thêm hai bước: chạy `xattr -cr` khi cài, và cấp lại quyền Accessibility sau mỗi lần cập nhật. **Quyết định 2026-11-15: không dùng Apple Developer ID.** Bước `xattr -cr` vẫn còn. Bước cấp lại quyền sau mỗi lần cập nhật được bỏ bằng chứng chỉ tự cấp cố định (mục 15). Đường ký Developer ID trong `build.sh` vẫn giữ nhưng không dùng.

### 13.2 Mặc định

| Mục | Mặc định |
|---|---|
| Engine | Vikey: tự chuyển Việt/Anh theo ngữ cảnh, để yên code, ⌫⌫ để hoàn tác. Lý do: `tools/mixbench` đo được Vikey sai 0.13–0.23% số từ khi gõ trộn, còn Gõ Nhanh có auto-restore sai 0.46–3.50% |
| Khởi động cùng máy | Bật sẵn, không hỏi (dùng `LaunchAtLogin` có sẵn của Gõ Nhanh) |
| Cập nhật | Tự tải và tự cài ngầm. Chỉ áp dụng khi không có phím nào trong 30 giây, và không bao giờ áp dụng giữa lúc đang gõ |
| Nhớ ngôn ngữ theo app | Bật (có sẵn) |
| Sửa lỗi theo app (Chrome, Spotlight, IDE…) | Tự động (có sẵn) |
| Cảnh báo app đang chặn gõ (Secure Input) | Bật (có sẵn). Với engine Vikey, cảnh báo hiện cả khi đang ở chế độ Anh, vì engine vẫn chạy |
| Tự học từ hoàn tác (4C) | Bật sẵn |
| Gợi ý từ (4A) | Bật sẵn, Esc để ẩn |
| Gợi ý gõ tắt (4B) | Hỏi một lần duy nhất ở màn chào. Bật rồi thì mỗi đề xuất chỉ cần một cú bấm "Thêm" |

### 13.3 Màn chào
Chỉ **một màn**: nút cấp quyền Accessibility, cộng một công tắc cho 4B. Không có lựa chọn engine, kiểu gõ hay phím tắt ở lần đầu; những thứ đó nằm trong Cài đặt cho ai cần.

### 13.4 Hai chỗ cố ý không tự động hoàn toàn
- 4B không tự thêm gõ tắt khi người dùng chưa đồng ý, vì một gõ tắt sai sẽ tự bung chữ lạ lúc gõ.
- 4B không tự bật ngầm, vì nó đếm cả dữ liệu cá nhân (địa chỉ, SĐT, MST).

### 13.5 Triển khai
- Làm thành một task bổ sung của GĐ1, ngay sau Task 8. Nội dung:
  - đổi engine mặc định sang Vikey;
  - bật khởi động cùng máy khi chạy lần đầu;
  - cài cập nhật ngầm, kèm điều kiện nhàn rỗi 30 giây;
  - gộp màn chào còn một màn;
  - cho cảnh báo Secure Input hiện với Vikey ở chế độ Anh.
- Cần thêm điểm gắn `auto-update` (cài ngầm, trong `UpdateManager`) và `onboarding` (gộp màn chào). Tổng số tên hook vẫn ≤ 12; nếu vượt thì gộp vào `branding`.
- **Test:**
  - Router: mặc định là `.vikey` khi chưa có giá trị lưu.
  - Bộ đếm nhàn rỗi: không cài khi vừa có phím trong 30 giây.
  - Test build kiểm tra rằng khởi động cùng máy được đăng ký ở lần chạy đầu.
  - Thử tay: cài mới, chỉ bấm cấp quyền, rồi gõ trộn được ngay.

## 14. Giao diện mới: gọn, tự động, mượt

Thêm ngày 2026-11-15, người dùng đã duyệt cả ba phương án A, B, C. Ba phương án được gộp thành một thiết kế: **cấu trúc B** (thanh bên nhiều trang), **trang Chung tối giản theo A**, và **ô nổi trên menu bar theo C**.

**Mục tiêu:** người dùng thường chỉ cần bấm icon menu bar, không bao giờ phải mở cửa sổ Cài đặt. Trên trang chính không có mục nào vô tác dụng.

### 14.1 Ô nổi trên menu bar (thay menu thả xuống)
- Bấm trái icon LeanKeys mở một `NSPopover` viết bằng SwiftUI, rộng khoảng 280 pt. Nội dung từ trên xuống:
  1. **Trạng thái:** một nút gạt lớn hai nấc `Tiếng Việt` / `English`, đổi ngay khi bấm (tương đương phím tắt bật/tắt). Bên dưới là một dòng nhỏ: `Tự chuyển Việt/Anh: Bật` (hoặc `Tạm dừng` khi người dùng đã tự tắt).
  2. **Cảnh báo** (chỉ khi có): `⚠︎ <Tên app> đang chặn gõ tiếng Việt` (không biết tên thì `⚠︎ Một ứng dụng đang chặn gõ tiếng Việt`), lấy từ `SecureInputHolder` có sẵn. Tooltip nói cách gỡ; VoiceOver đọc "Cảnh báo: …".
  3. **Kiểu gõ:** menu thả xuống `Telex` / `VNI`.
  4. **Cập nhật** (chỉ khi có bản mới sẵn sàng): nút `Cài bản mới` (chạy bộ cài an toàn).
  5. Hàng cuối: `Cài đặt…` · `Thoát LeanKeys`.
- Bấm phải, hoặc Option + bấm, mở menu cũ của Gõ Nhanh, để không mất chức năng nào.
- Ô nổi tự đóng khi bấm ra ngoài (`.transient`).

### 14.2 Icon menu bar đổi mượt
- Khi đổi Việt/Anh, kể cả khi Vikey tự chuyển, icon chuyển bằng hiệu ứng mờ dần (crossfade) trong 150 ms.
- Nếu người dùng bật "Giảm chuyển động" (`accessibilityDisplayShouldReduceMotion`) thì không có hiệu ứng.

### 14.3 Cửa sổ Cài đặt: thanh bên bốn trang
- **Thanh bên:** logo 48 pt cạnh tên "LeanKeys" trên cùng một hàng; dưới đó là nhãn cập nhật, nơi duy nhất hiện phiên bản (`v1.2 · Mới nhất`; "Mới nhất" chỉ sau một lần kiểm tra báo vậy, chưa kiểm tra thì `Kiểm tra cập nhật`). Nhãn là một nút: dùng được bằng bàn phím và VoiceOver. Bên dưới là `Chung` · `Phím tắt` · `Nâng cao` · `Giới thiệu`, mỗi mục có biểu tượng SF Symbol.
- **Chung:**
  - Thẻ trạng thái giống phần đầu của ô nổi: trạng thái, dòng tự chuyển, cảnh báo nếu có.
  - Công tắc `Gõ tiếng Việt` (dòng phụ "Tắt là gõ English, như chọn English trên menu bar"), chữ đậm hơn các mục khác.
  - `Kiểu gõ`.
  - Các mục chỉ dành cho Gõ Nhanh (`Gõ W thành Ư`, `Gõ [ ] thành Ơ Ư`, `Tự khôi phục tiếng Anh`, `Tự viết hoa đầu câu`) **chỉ hiện khi** engine là "Chỉ dùng Gõ Nhanh". Ở chế độ "Tự động", chúng không xuất hiện.
- **Phím tắt:** các dòng phím tắt hiện có của Gõ Nhanh, chuyển sang trang này, gọi là `Chuyển Việt/Anh` và `Phím tắt chuyển Việt/Anh thứ hai`. Phím tắt khôi phục của Gõ Nhanh có tên `Trả từ đang gõ về phím gốc` (không gọi là "Hoàn tác", từ đó dành cho ⌫⌫ của 4C) và, như các mục chỉ dành cho Gõ Nhanh, chỉ hiện khi engine là "Chỉ dùng Gõ Nhanh": Vikey coi Esc là phím ngắt từ, không khôi phục. Hàng nào bấm được (phím tắt, Bảng gõ tắt) là nút: dùng được bằng bàn phím và VoiceOver; mọi công tắc, ô chọn và nút chỉ có biểu tượng đều có tên cho VoiceOver.
- **Nâng cao:** thẻ thu gọn `Lõi gõ` (mục 13; trên giao diện, engine gọi là "lõi gõ"), rồi `Gợi ý gõ tắt`, `Tự sửa và tự học`, tuỳ chỉnh theo ứng dụng; các phần ít dùng và kỹ thuật (hiệu năng, tương thích, nhật ký gỡ lỗi) nằm cuối.
  - Mọi mục hiện trên trang này đều có tác dụng: Gõ Nhanh chỉ áp dụng tuỳ chỉnh theo ứng dụng, "Mở lại LeanKeys khi đóng Cài đặt" và "Không theo dõi ô tìm kiếm Spotlight/Raycast" khi bật "cài đặt nâng cao", công tắc mà LeanKeys ẩn; vì thế LeanKeys luôn áp dụng chúng (`SettingsLayout.advancedSettingsApply`, rà soát chữ I2). Tuỳ chỉnh theo ứng dụng ghi `Tiếng Việt: Theo cài đặt chung / Luôn bật / Luôn tắt`, `Độ trễ`, `Cách gửi phím`.
- **Giới thiệu:** giữ như hiện tại, có ghi công.
- **Ghi chú trên giao diện tối đa một dòng.** Giải thích dài hơn nằm trong tooltip của biểu tượng ⓘ. Không đưa chữ kỹ thuật như "giai đoạn 4" ra giao diện.
- **Màu:** chữ phụ phải đạt tương phản ≥ 4.5:1 ở cả chế độ sáng và tối; dùng màu hệ thống `secondaryLabelColor`, không dùng xám tự chọn.

### 14.4 Cách gắn vào code gốc
- Toàn bộ giao diện mới nằm trong LeanKeysKit (`leankeys/LeanKeysKit/UI/`): `StatusPopoverView`, `SettingsRootView`, `StatusCard`, `MenuBarIconAnimator`.
- Các trang dùng lại phần có sẵn của Gõ Nhanh (phím tắt, nâng cao, giới thiệu) bằng cách truyền view vào: điểm gắn dựng `SettingsRootView(general:shortcuts:advanced:about:)` với các view của Gõ Nhanh bọc trong `AnyView`. Không chép code của Gõ Nhanh sang.
- Điểm gắn:
  - `menubar-popover` (tên mới) trong `MenuBar.swift`, nơi gắn hành động bấm vào icon.
  - Điểm thay gốc cửa sổ Cài đặt dùng lại tên `settings-engine`.
  - Tổng số tên hook ≤ 9.
- Nếu một view của Gõ Nhanh là `private` và không truyền được, điểm gắn chỉ được đổi mức truy cập (`private` → `internal`) ở dòng đó, có đánh dấu hook. Không sửa nội dung view.

### 14.5 Test
- **Đơn vị:**
  - Logic hiện hoặc ẩn các mục chỉ dành cho Gõ Nhanh theo engine.
  - Nội dung thẻ trạng thái (Việt/Anh, tự chuyển bật/tạm dừng, cảnh báo Secure Input).
  - Bộ đổi icon tôn trọng "Giảm chuyển động".
- **Ảnh chụp để duyệt:**
  - Một script dựng `StatusPopoverView` và các trang của `SettingsRootView` ra PNG bằng `ImageRenderer`, ở cả chế độ sáng và tối, lưu vào `docs/ui/`.
  - Người dùng duyệt các ảnh này trước khi merge.
- **Thử tay:** thêm vào `sync/manual-checklist.md`:
  - bấm icon thì ô nổi mở, đổi Việt/Anh ngay;
  - bấm phải thì mở menu cũ;
  - icon đổi mượt khi Vikey tự chuyển;
  - chế độ tối;
  - "Giảm chuyển động".


## 15. Quyền Trợ năng: bấm một lần, giữ qua cập nhật

Thêm ngày 2026-11-15, người dùng đã duyệt. macOS không cho app tự bật quyền Trợ năng; mục tiêu là người dùng chỉ gạt **một** công tắc lúc cài, và **không bao giờ** phải cấp lại sau cập nhật. Không sửa cơ sở dữ liệu TCC của hệ thống.

### 15.1 Cấp quyền bằng một lần bấm
- Nút trên màn chào gọi `AXIsProcessTrustedWithOptions` với `kAXTrustedCheckOptionPrompt = true` (LeanKeys có sẵn trong danh sách Trợ năng), rồi mở trang `Privacy_Accessibility`.
- Nhận biết quyền đã được cấp bằng hai tín hiệu: `AXIsProcessTrusted()`, hoặc tạo thử được một event tap chủ động (`defaultTap`) rồi huỷ ngay. Một trong hai đúng là đủ. Dùng tap chủ động vì tap chỉ-nghe (`listenOnly`) bị macOS gắn với quyền Giám sát đầu vào (Input Monitoring), và hộp thoại quyền đó sẽ làm người dùng bối rối.
- Một bộ đếm 1 giây chạy trong LeanKeysKit, **độc lập với cửa sổ màn chào**: khi quyền có, app khởi động lại đúng một lần như hiện nay. Cửa sổ bị che hay bị đóng cũng không làm lỡ bước này.

### 15.2 Chứng chỉ ký cố định
- `sync/make-signing-cert.sh` (người dùng chạy một lần trên máy build): tạo chứng chỉ tự cấp dùng cho ký mã, tên `LeanKeys Self-Signed`, hạn 20 năm, nhập vào login keychain, cho `codesign` dùng khoá không cần hỏi; xuất bản sao lưu `.p12` có mật khẩu do người dùng nhập ra một đường dẫn họ chọn. Script không bao giờ in hay lưu mật khẩu.
- `leankeys/build.sh`: ưu tiên Developer ID (đường cũ, nếu có biến môi trường); nếu không, dùng `LeanKeys Self-Signed` khi có trong keychain; nếu không nữa, ký ad-hoc như cũ. Ghi rõ đã ký bằng gì.
- **Hardened runtime (2026-11-17, audit bảo mật HIGH-1):** cả ba cách ký đều bật hardened runtime (`--options runtime`) và dùng `leankeys/LeanKeys.entitlements`, chỉ có `app-sandbox = false`. Bỏ `cs.disable-library-validation`, `cs.allow-jit`, `cs.allow-unsigned-executable-memory`, `cs.disable-executable-page-protection` và `automation.apple-events` (cùng chuỗi `NSAppleEventsUsageDescription`): lõi Rust là thư viện tĩnh, không có JIT, không gửi Apple Event. Không có hardened runtime, một tiến trình bất kỳ của người dùng có thể mở lại LeanKeys với `DYLD_INSERT_LIBRARIES` và dùng quyền Trợ năng của nó. `build.sh` dừng nếu bản ký thiếu cờ `runtime`; `tests/build/test_build_output.sh` kiểm cờ, các entitlement đã bỏ, và yêu cầu chữ ký `certificate leaf` (không đổi, nên người dùng giữ quyền Trợ năng).
- `UpdateInstallPolicy`: coi bản đang chạy được ký bằng chứng chỉ (không ad-hoc, có chứng chỉ lá) như bản có TeamIdentifier.
- Cài ngầm khi máy rảnh cần **cả hai** điều kiện: (1) app đang chạy được ký ổn định, như trên; và (2) bản tải về khớp yêu cầu chỉ định (designated requirement) của app đang chạy, kiểm bằng `SecStaticCodeCheckValidity` sau khi DMG được gắn và kiểm tra. Nếu không khớp, bản đó không được cài ngầm, và vẫn còn sẵn sàng để cài bằng một lần bấm trên mục menu "cập nhật sẵn sàng".
- **(2026-11-17, audit bảo mật MEDIUM-5)** Mọi cách cài (ngầm, ô nổi, mục menu "Khởi động lại để cập nhật") qua cùng một bộ kiểm: bản tải về phải ký ổn định (không ad-hoc), có số phiên bản lớn hơn bản đang chạy (`SafeInstaller.isNewer`, không cho hạ cấp hay cài lại cùng bản), và khớp yêu cầu chỉ định khi bản đang chạy ký ổn định. Bản không khớp danh tính bị xoá, không còn giữ lại chờ bấm (thay câu trên). Link tải chỉ nhận HTTPS tới `github.com`, `objects.githubusercontent.com`, `release-assets.githubusercontent.com`. Đường dẫn DMG đọc lại từ cài đặt lúc mở app phải đúng là `~/Library/Caches/GoNhanh-update.dmg`, nếu không thì bỏ qua. Hậu tố bản thử (`1.3-beta`) bị bỏ khi so (1.3-beta mới hơn 1.2). Bản bị từ chối khi bấm "Khởi động lại để cập nhật" hiện dòng "Không cài được bản mới". Hệ quả đã chấp nhận: nếu chứng chỉ `LeanKeys Self-Signed` bị tạo lại, bản đang chạy từ chối mọi bản mới; người dùng phải tải DMG về và cài tay (review bảo mật M-9). Số trong `Info.plist` của DMG phải khớp tag; nếu không, bản mới có thể bị tải rồi bỏ. Không có tệp `SHA256SUMS` ký riêng (LOW-7): chữ ký mã, yêu cầu chỉ định và kiểm phiên bản là lớp bảo vệ của bản tải về.

### 15.3 Lần chuyển từ ad-hoc sang chứng chỉ
- Người dùng cũ (`ReturningUser.wasTrusted`) mở bản mới mà mất quyền: app chạy `tccutil reset Accessibility io.github.anlvdt.leankeys` cho đúng bundle của mình, rồi đi lại luồng 15.1. Người dùng chỉ gạt lại công tắc.
- Nếu `tccutil` thất bại, quay về hướng dẫn −/+ hiện có.

### 15.4 Test
- **Đơn vị:** chính sách cài ngầm theo loại chữ ký; logic "đã có quyền" từ hai tín hiệu; bộ đếm gọi khởi động lại đúng một lần; chọn danh tính ký trong `build.sh` (test shell).
- **Kiểm chứng trên máy thật (bắt buộc trước khi merge):** cấp quyền cho bản A ký bằng chứng chỉ; build bản B; thay bản A bằng B; B phải gõ được ngay, không cần cấp lại. Ghi kết quả vào báo cáo.
- **Kết quả 2026-11-15 (máy của người dùng):** bản A (1.0, ký `LeanKeys Self-Signed`, yêu cầu chữ ký `certificate leaf = H"c5f280e9…"`) mở lên ở luồng người dùng cũ, tự `tccutil reset` thành công, người dùng chỉ gạt một công tắc, app tự khởi động lại. Bản B (1.0.1, binary khác, cùng chứng chỉ) thay vào cùng đường dẫn và mở lên **không cần cấp lại quyền**. Đạt.
- **Thử tay:** thêm vào `sync/manual-checklist.md`: cài mới chỉ gạt một công tắc; cửa sổ màn chào bị che vẫn tự khởi động lại; cập nhật không mất quyền.


## 16. Kiểm tra cập nhật ngay trong ô nổi

Thêm ngày 2026-11-16. Mục tiêu: bấm một lần trong ô nổi là xong; có bản mới thì app tự tải, kiểm tra, cài và mở lại.

### 16.1 Khoảng trống
- Ô nổi (§14.1) chỉ có `Cài bản mới` khi bản cập nhật đã tải sẵn; không có nút kiểm tra.
- `checkForUpdatesManually()` (trang Giới thiệu, menu cũ) mở cửa sổ riêng và cần bấm thêm `Cập nhật`; tải xong lại chờ máy rảnh 30 giây (`installWhenIdle`). Đường này giữ nguyên.

### 16.2 Hàng cập nhật trong ô nổi
Thay mục 4 của §14.1 bằng một hàng luôn hiện, nằm dưới `Kiểu gõ`:

| Trạng thái | Hiện | Bấm |
|---|---|---|
| Chưa kiểm tra | nút `Kiểm tra cập nhật` | kiểm tra |
| Đang kiểm tra | vòng quay + `Đang kiểm tra cập nhật…` | — |
| Đang tải | thanh tiến độ + `Đang tải bản mới… 42%` | — |
| Đang cài | vòng quay + `Đang cài — LeanKeys sẽ tự mở lại` | — |
| Đã tải sẵn (tải ngầm) | nút `Cài bản mới` | cài |
| Mới nhất | `Bạn đang dùng bản mới nhất` | — |
| Lỗi | một dòng ngắn + nút `Thử lại` | kiểm tra lại |

- Lỗi kiểm tra: `Không kiểm tra được, thử lại sau`; lỗi tải: `Không tải được bản mới`; bộ cài từ chối: `Không cài được bản mới`. Không hiện chữ lỗi kỹ thuật (tiếng Anh) của `UpdateChecker`. Cửa sổ cập nhật cũ của Gõ Nhanh cũng không: `UpdateChecker` báo lỗi bằng câu tiếng Việt có hướng xử lý, và tiêu đề trang lỗi nói đúng bước hỏng (kiểm tra, tải hay cài).
- Đóng ô nổi thì `Mới nhất` và `Lỗi` trở về `Chưa kiểm tra`.

### 16.3 Luồng
- Bấm `Kiểm tra cập nhật`: đặt cờ "người dùng yêu cầu cài" trong `UpdateManager`, kiểm tra; có bản mới thì tải ngay với tiến độ (không mở cửa sổ cũ). Nếu bản tải ngầm đang chạy dở thì nhận lấy nó, không tải lần hai.
- Tải xong, `installWhenIdle` thấy cờ thì cài ngay, không chờ máy rảnh (người dùng vừa bấm, không phải đang gõ).
- Bộ cài của ô nổi (cả `Cài bản mới`) luôn từ chối bản ký ad-hoc: app đang chạy ký ổn định thì bản mới phải khớp yêu cầu chữ ký của nó; app đang chạy là ad-hoc thì bản mới phải ký bằng chứng chỉ (giữ đường chuyển §15.3). Bị từ chối thì xoá bản tải về và báo lỗi một dòng.
- Bản Debug không bao giờ tự cài (R23): luồng dừng ở `Cài bản mới`.
- Trang Giới thiệu và menu cũ không đổi.

### 16.4 Test
- **Đơn vị (LeanKeysKit):** ánh xạ trạng thái `UpdateManager` + cờ → trạng thái hàng; chữ của từng trạng thái; bấm thì làm gì; tiến độ không xác định (-1) không làm hỏng chữ; `SafeInstaller.verify` từ chối bản ad-hoc khi yêu cầu chữ ký ổn định; mô hình ô nổi gọi đúng hành động và báo đóng.
- **Ảnh:** `docs/ui/popover-update-*-{light,dark}.png` bằng dữ liệu giả.
- **Thử tay:** mục U1–U4 trong `sync/manual-checklist.md`.

## 17. 4D: Tự viết hoa tên riêng, bỏ ký tự gõ dính khi Enter

Thêm ngày 2026-11-16. Người dùng đã duyệt thiết kế và yêu cầu làm luôn. Cả hai tính năng chỉ chạy với engine Vikey (chế độ "Tự động", mặc định), cùng lý do như 4C (mục 12.2), và đều bật sẵn.

### 17.1 Tự viết hoa tên riêng
**Nguyên tắc: viết hoa sai còn tệ hơn không viết hoa.** Mỗi quy tắc dưới đây đã được đo trên hai kho câu của Vikey (`chat_messages` và `synthetic_val`, chữ hoa đúng chuẩn). Cách đo: hạ toàn bộ chữ về chữ thường, gõ lại từng từ, rồi so với bản gốc, không tính từ đầu câu. Bản dựng thử: quy tắc cố định viết hoa **đúng 302 lần, sai 0 lần**; thêm phần tự học (17.1.3) thì đúng 777 lần, sai 0 lần (2 lần lệch do bản gốc viết hoa toàn bộ, `FOMO`).

**Sửa sau review cuối (ruling R11, 2026-11-16).** Cách đo trên hạ hết chữ về chữ thường nên không thấy hai loại lỗi: chữ hoa đầu câu của người dùng bị coi là dấu hiệu tên ("Mai anh đi đâu thế" → "Mai Anh"), và cụm từ thường chứa một mục trong danh sách ("cập nhật bản mới", "lưu văn bản", "xã hội an toàn", "bàn về hòa bình"). Đã sửa dữ liệu, từ chỉ nơi chốn và thêm các chốt chặn ghi ở 17.1.1–17.1.2. Đo thêm bằng kho câu âm `tools/capbench/negatives.txt` (55 câu thường, chữ hoa đúng chuẩn, **gõ lại đúng như viết**, kể cả chữ hoa đầu câu; mọi từ bị đổi đều tính là sai): trước khi sửa sai 39 lần, sau khi sửa **sai 0 lần**. Ruling R15 thêm 4 câu ("Đi đến hòa bình cần kiên nhẫn", "vương quốc Anh" giữa câu…): trước R15 sai 5 lần, sau R15 sai 0 lần trên 59 câu. Trên hai kho câu cũ vẫn là đúng 302, sai 0 (cố định) và đúng 777, sai 2 `FOMO` (thêm tự học). **(sửa 2026-11-16, đánh giá toàn ứng dụng)** `capbench` gõ lại từ viết hoa toàn bộ đúng như viết (app không bao giờ đụng tới chúng) và không tính từ được giữ nguyên, nên 2 lần lệch `FOMO` hết. Thêm 2 câu của quy tắc `:`/ngoặc kép (17.1.2): trước khi sửa sai 2 lần, sau khi sửa sai 0 lần trên 61 câu. Quy tắc đó có giá (ruling R17, chấp nhận): **tên viết hoa trong ngoặc kép giữa câu không được học**, nên trên hai kho câu phần tự học mất một tên "mọi nơi" (122 → 121): **đúng 775, sai 0** (thêm tự học; trước quy tắc là 777); quy tắc cố định vẫn đúng 302, sai 0.

**Thời điểm.** Khi một từ được chốt bằng phím cách hoặc dấu câu, LeanKeys xét các từ vừa gõ trong `TextMirror` (cùng cụm, không vượt qua dấu câu). Nếu khớp một quy tắc, LeanKeys thay các từ đó bằng dạng viết hoa: xoá N ký tự rồi gõ lại, phím ngắt vẫn đi như thường. Gõ tắt (4B) vẫn được xét trước.

**Không viết hoa trong terminal và trình soạn code** (cùng một danh sách app với 17.2, ruling R12): ở đó chữ là lệnh hay mã, phân biệt hoa thường (tên nhánh, đường dẫn, tên biến), và trong terminal lệnh chạy ngay khi Enter nên không kịp ⌫. Cũng không viết hoa một từ dính với ký hiệu (`an@tiki.vn`, `~/tiki/`, `#tiki`, `ten-tiki`): chỉ xét từ gồm toàn chữ và số (ruling R13). **(sửa 2026-11-16, đánh giá toàn ứng dụng)** Cụm nhiều từ mà từ đầu dính với ký hiệu cũng giữ nguyên: `~/hà nội`, `@nguyễn văn`, `#hà nội`, `ten_hà nội`, `ten-hà nội`. Dấu ngoặc kép, ngoặc đơn và `, ; :` đứng sát từ không tính là dính (`"Hà Nội`). Từ dính đó cũng không làm từ chỉ nơi chốn hay từ xưng hô cho các từ sau (`~/ở hoà bình`, `@anh hùng` giữ nguyên; ruling R17); các từ đứng riêng mà không cần từ chỉ nơi chốn vẫn được viết hoa (`~/ở Hà Nội`).

**17.1.1 Địa danh.** Một cụm 1–4 từ, khớp không phân biệt hoa thường, trong danh sách sau được viết hoa từng âm tiết:
- 34 tỉnh, thành sau sắp xếp 2025: Hà Nội, Huế, Lai Châu, Điện Biên, Sơn La, Lạng Sơn, Quảng Ninh, Thanh Hóa, Nghệ An, Hà Tĩnh, Cao Bằng, Tuyên Quang, Lào Cai, Thái Nguyên, Phú Thọ, Bắc Ninh, Hưng Yên, Hải Phòng, Ninh Bình, Quảng Trị, Đà Nẵng, Quảng Ngãi, Gia Lai, Khánh Hòa, Lâm Đồng, Đắk Lắk, Hồ Chí Minh, Đồng Nai, Tây Ninh, Cần Thơ, Vĩnh Long, Đồng Tháp, Cà Mau, An Giang.
- Tên tỉnh cũ: Hà Giang, Yên Bái, Bắc Kạn, Hòa Bình, Vĩnh Phúc, Bắc Giang, Hải Dương, Thái Bình, Hà Nam, Nam Định, Quảng Bình, Thừa Thiên Huế, Quảng Nam, Bình Định, Phú Yên, Ninh Thuận, Bình Thuận, Kon Tum, Đắk Nông, Bình Phước, Bình Dương, Bà Rịa, Vũng Tàu, Long An, Tiền Giang, Bến Tre, Trà Vinh, Hậu Giang, Sóc Trăng, Bạc Liêu, Kiên Giang.
- Địa danh quen thuộc: Sài Gòn, Hội An, Phú Quốc, Đà Lạt, Nha Trang, Hạ Long, Sa Pa, Mũi Né, Quy Nhơn, Buôn Ma Thuột, Pleiku, Biên Hòa, Thủ Đức, Côn Đảo, Tam Đảo, Mộc Châu, Phan Thiết, Rạch Giá, Hà Tiên, Châu Đốc, Mỹ Tho, Long Xuyên, Cát Bà, Tân Sơn Nhất, Nội Bài, Hoàn Kiếm, Ba Đình, Cầu Giấy, Gò Vấp, Bình Thạnh, Tân Bình, Phú Nhuận.
- Tên nước và vùng: Việt Nam, Trung Quốc, Nhật Bản, Hàn Quốc, Hoa Kỳ, Thái Lan, Campuchia, Singapore, Malaysia, Indonesia, Philippines, Ấn Độ, Canada, Đài Loan, Hồng Kông, Triều Tiên, Châu Âu, Châu Á, Châu Phi, Châu Mỹ, Đông Nam Á, Liên Hợp Quốc, Myanmar.
- Không thêm "Tết": kho câu viết cả "Tết" lẫn "tết" (11 lần chữ thường), nên viết hoa sẽ bị tính là sai.
- So khớp không phân biệt kiểu đặt dấu (`Thanh Hoá` và `Thanh Hóa`, `Khánh Hoà` và `Khánh Hòa`). Kết quả là chính các từ người dùng đã gõ, chỉ viết hoa chữ cái đầu, giữ nguyên kiểu đặt dấu của họ.
- **Cụm trùng từ thường** chỉ được viết hoa khi từ (hoặc cặp từ) ngay trước là một từ chỉ nơi chốn rõ ràng: `tỉnh`, `thành phố`, `tp`, `ở`, `tại`, `quê`, `người`. Không dùng động từ chỉ hướng đi (`đến`, `đi`, `từ`, `ra`, `vào`, `về`; ruling R11, R15): "bàn về hòa bình", "đi đến hòa bình" là nghĩa thường. Muốn "đi đến Hòa Bình" thì người dùng tự gõ hoa. Các cụm đó là: hòa bình, thái bình, cao bằng, hải dương, phú thọ, vĩnh phúc, bình định, an giang, long an, hà nam, quảng nam, gia lai, bình dương, nam định, tân bình, bình thạnh, phú nhuận, cầu giấy, ba đình, bà rịa, thanh hóa, phú yên, hưng yên, vĩnh long, châu á, châu âu, châu phi, châu mỹ, hoa kỳ.
- Cụm dài được ưu tiên: "thừa thiên huế" thắng "huế"; "hồ chí minh" thắng họ "hồ".
- **Không viết hoa sau một số từ** (ruling R11; `placeNotAfter` trong `ProperNouns.json`), vì khi đó là cụm từ thường: "nhật bản" sau `cập` ("cập nhật bản mới"); "hội an" sau `hiệp`, `xã`, `đại`, `quốc`, `đoàn`, `học`, `nội`, `lễ`, `cơ`, `giáo` ("xã hội an toàn", "hiệp hội an ninh"; luật chạy khi chốt "an", trước khi gõ từ sau).

**17.1.2 Họ tên.**
- **Họ:** nguyễn, trần, lê, phạm, hoàng, huỳnh, phan, vũ, võ, đặng, bùi, đỗ, hồ, ngô, dương, lý, đinh, đoàn, trương, lâm, mai, tô, trịnh, đào, cao, lương, hà, lưu, tạ, châu, quách, thái, vương, kiều.
- **Họ luôn viết hoa** (không trùng từ thường): chỉ nguyễn. Không thêm phạm (vi phạm), trương (khai trương), đặng: đo thấy viết hoa sai. Bỏ quách ("bỏ quách đi"), trịnh ("trịnh trọng"), huỳnh ("đèn huỳnh quang") theo ruling R11: ba họ này giờ cần chữ hoa có sẵn như các họ khác.
- **Chữ hoa đầu cụm không phải dấu hiệu tên** (ruling R11): từ đầu tiên của cụm (sau `.` `!` `?`, xuống dòng, hoặc khi không biết gì đứng trước) được viết hoa vì là đầu câu, nên ở mọi quy tắc dưới đây "đã viết hoa" không tính chữ hoa đó, trừ khi từ đó là họ luôn viết hoa. "Mai anh đi đâu thế", "Lương tâm", "Thái bình", "Vương quốc Anh" giữ nguyên. **(sửa 2026-11-16)** Chữ hoa ngay sau `:` hay sau dấu mở ngoặc kép cũng là chữ hoa đầu câu: `Anh nói: "Mai anh qua đón em."`, `Em ghi chú: Lương tâm là trên hết.` giữ nguyên, và từ đó cũng không được học làm tên (17.1.3). `capbench` bắt đầu cụm mới ở đó, và hai câu này nằm trong `negatives.txt`. Giá phải trả (ruling R17, chấp nhận): tên thật đứng ngay sau `:` cũng không được viết hoa theo chữ hoa đó ("Liên hệ: Trần văn an" giữ nguyên, trước đây thành "Trần Văn An"), và tên viết hoa trong ngoặc kép giữa câu không được học.
- **Tên lót:** văn, thị. Khi đứng ngay sau một họ luôn viết hoa, hoặc một họ đã viết hoa (không tính chữ hoa đầu cụm), cả họ và tên lót được viết hoa (ruling R11: "lưu văn bản", "trần thị" gõ thường giữ nguyên).
- **Sau "Họ Văn/Thị",** từ kế tiếp luôn được viết hoa ("Nguyễn Văn Tèo").
- **Tên phổ biến** (danh sách khoảng 130 tên trong bản dựng thử `data.py`, ví dụ an, anh, bình, dũng, hùng, lan, linh, mai, minh, nam, ngọc, phương, quân, thảo, trang, tuấn, vân, yến…):
  - đứng sau một họ đã viết hoa, hoặc sau một họ luôn viết hoa: viết hoa cả hai;
  - đứng sau hai từ viết hoa mà từ đầu là họ hoặc tên lót: viết hoa.
- **Tên không đứng sau một số từ** (ruling R15; `givenNameNotAfter` trong `ProperNouns.json`): "quốc" sau "vương" là danh từ thường ("vương quốc"), nên "Vương quốc Anh" giữ nguyên dù "Vương" viết hoa giữa câu.
- Ngoài các trường hợp trên thì không viết hoa: "nguyễn đi chợ" → "Nguyễn đi chợ".

**17.1.3 Tên tự học.** LeanKeys đếm các từ người dùng **tự gõ hoa bằng Shift hoặc Caps Lock** ở giữa câu. Từ đầu câu, từ viết hoa toàn bộ, từ một chữ cái, và từ do chính LeanKeys viết hoa đều không tính.
- **Học "sau từ xưng hô":** từ được gõ hoa ngay sau một từ xưng hô (anh, chị, em, ông, bà, cô, chú, bác, thầy, sếp, dì, cậu) từ 2 lần trở lên. Lần sau, khi từ đó được gõ thường ngay sau một từ xưng hô, nó được viết hoa ("anh hùng" → "anh Hùng").
- **Học "mọi nơi":** từ được gõ hoa giữa câu từ 2 lần trở lên mà không phải từ tiếng Việt hay tiếng Anh có thật (`lk_vikey_word_score` của cả hai ngôn ngữ đều là `LK_VIKEY_NOT_A_WORD`, xét trên các chữ ASCII của từ). Lần sau, từ đó được viết lại đúng dạng đã học ở mọi nơi ("shopee" → "Shopee", "chatgpt" → "ChatGPT").
- **Lưu trữ:** trước khi đạt 2 lần chỉ lưu HMAC-SHA256 của từ (khoá HMAC như 4B, mục 20) kèm số lần. Đạt ngưỡng thì mới lưu dạng chữ. File riêng `~/Library/Application Support/LeanKeys/learned-names.bin` (quyền 0600, AES-GCM, dùng `KeychainEncryptedFileStore` với mục Keychain `io.github.anlvdt.leankeys.names`). Giới hạn 2.000 tên, bỏ tên lâu không dùng nhất (LRU).
- **Không học** trong Secure Input, ô mật khẩu, và các app bị loại trừ (mục 11.1). Ô mật khẩu được kiểm tra trên hàng đợi nền như 12.3.
- **(sửa 2026-11-16, đánh giá toàn ứng dụng)** Cũng không học trong terminal và trình soạn code (danh sách của 17.2): ở đó từ viết hoa giữa dòng thường là tên biến hay lệnh (`Config`, `Router`). Danh sách loại trừ của 4B và 4C không đổi.

**17.1.4 Hoàn tác.** Nếu người dùng bấm ⌫ ngay sau một lần tự viết hoa (phím đầu tiên sau phím ngắt):
- Chữ trở lại đúng như đã gõ, chỉ mất phím ngắt, giống 4C.
- LeanKeys lưu luật "không viết hoa cụm này sau từ đứng trước này" vào sổ luật của 4C (`UndoRuleBook`, chữ có tiền tố `cap:` để không lẫn với luật 4C). Luật có từ đứng trước được dùng ngay sau 1 lần hoàn tác, luật không có từ đứng trước sau 2 lần, như 4C. Từ đứng trước có dạng mật khẩu (`Exclusions.looksLikeSecret`) thì không được lưu làm ngữ cảnh, chỉ tăng luật không có từ đứng trước (ruling R14). Danh sách "Từ giữ nguyên" hiện luật này với nhãn "(giữ chữ thường)": LeanKeys giữ cụm đó chữ thường.
- Tên tự học bị hoàn tác 2 lần ở bất kỳ đâu thì bị xoá khỏi danh sách tên.

### 17.2 Bỏ ký tự gõ dính khi Enter
- **Phím sát Enter** (mã phím Mac):
  - `\` (42), `]` (30), `'` (39);
  - khi giữ Shift: `|`, `}`, `"`.
- **Trước Enter.** Khi bấm Enter (36 hoặc 76), nếu phím ngay trước là một phím sát Enter, cách Enter **≤ 100 ms** (theo thời điểm nhấn phím), và đã gõ ra đúng một ký tự ở cuối dòng: LeanKeys xoá ký tự đó, rồi để Enter đi như thường.
- **Sau Enter.** Nếu một phím sát Enter được nhấn trong vòng **≤ 100 ms** sau Enter, phím đó bị bỏ. Riêng `]` và `}` không bị bỏ khi Vikey đang gõ tiếng Việt: Telex gõ chúng ra ư, Ư, chữ đầu của dòng mới (ruling R14).
- **Không áp dụng khi:**
  - ký tự đó đóng một cặp đang mở trên cùng dòng: `'` khi trên dòng đã có số lẻ dấu `'`; `]` khi có `[` chưa đóng; `"` và `}` tương tự;
  - app đang dùng là terminal hay trình soạn code: Terminal, iTerm2, Warp, Ghostty, Alacritty, kitty, WezTerm, Hyper, Tabby, VS Code, VS Code Insiders, Cursor, Windsurf, Zed, Xcode, Sublime Text, Nova, BBEdit, các IDE của JetBrains (bundle ID bắt đầu bằng `com.jetbrains.`), Android Studio;
  - đang ở chế độ Gõ Nhanh.
- **Ngưỡng 100 ms** là hằng số có tên, đặt trong một file. Gõ dính là hai phím gần như cùng lúc, còn gõ `\` rồi Enter có chủ đích thường cách nhau trên 150 ms.

### 17.3 Cài đặt
Thẻ "Tự sửa và tự học" (mục 12.3) có thêm:
- hai công tắc `Tự viết hoa tên riêng` (dòng phụ "Tên người, địa danh: Hà Nội, Nguyễn Văn An") và `Bỏ phím \ ] ' lỡ bấm cùng Enter` (dòng phụ "Không áp dụng trong Terminal và trình soạn code"), bật sẵn; khoá UserDefaults là `LeanKeys.autoCapitalize` và `LeanKeys.strayEnter`. Tên công tắc thứ hai đổi từ `Bỏ ký tự gõ dính khi Enter` theo ruling R19 (rà soát chữ trên giao diện);
- danh sách `Tên đã học` (dạng chữ, số lần, nút xoá); khi trống ghi "Chưa có. Tên bạn tự viết hoa từ hai lần sẽ hiện ở đây."; nút "Xoá tất cả" của thẻ xoá cả danh sách này.

### 17.4 Test
- **Đơn vị:**
  - Mỗi quy tắc ở 17.1.1–17.1.2, kèm các ca phải giữ chữ thường: "vi phạm", "khai trương", "hòa bình thế giới", "nguyễn đi chợ" → "Nguyễn đi chợ", "anh hùng" khi chưa học, và các câu của ruling R11 ("Mai anh đi đâu thế", "cập nhật bản mới", "lưu văn bản", "bỏ quách đi", "trịnh trọng", "đèn huỳnh quang", "hiệp hội an ninh", "xã hội an toàn", "bàn về hòa bình") và R15 ("đi đến hòa bình", "Vương quốc Anh" giữa câu).
  - Tên tự học: ngưỡng 2 lần; không học từ đầu câu, từ do LeanKeys viết hoa, hay trong ô mật khẩu; file lưu không chứa tên chưa đạt ngưỡng; LRU 2.000.
  - Hoàn tác bằng ⌫.
  - Ký tự gõ dính: trước Enter, sau Enter, đúng 100 ms (có) và 101 ms (không); cặp đang mở; app bị loại; chế độ Gõ Nhanh.
- **Đo lại** bằng `tools/capbench/` (bản dựng thử, chuyển vào repo): quy tắc cố định không có lần viết hoa sai nào trên hai kho câu, và không đổi từ nào trong kho câu âm `negatives.txt` (gõ lại đúng như viết).
- **Thử tay:**
  - gõ "toi o ha noi" → "tôi ở Hà Nội";
  - gõ "nguyen van an" → "Nguyễn Văn An";
  - gõ "anh Hùng" hai lần, rồi "anh hùng" → "anh Hùng";
  - ⌫ ngay sau khi tự viết hoa trả lại chữ thường;
  - trong Notes gõ "xong." rồi bấm `\` và Enter gần như cùng lúc → dòng kết thúc ở "xong.";
  - trong Terminal, `\` rồi Enter vẫn giữ `\`.

## 18. Phím đi thẳng: ô đăng nhập, mật khẩu, điều khiển từ xa

Thêm ngày 2026-11-16 theo yêu cầu người dùng. Áp dụng cho cả hai engine.

- **Điều khiển từ xa và máy ảo.** Khi app đang dùng là một app điều khiển máy khác hay một máy ảo, mọi phím đi thẳng, không bỏ dấu, không gõ tắt, không học. Máy bên kia có bộ gõ riêng, còn phím giả mà LeanKeys gửi (Backspace + chữ có dấu) không được chuyển đi như phím thật, nên gõ ở đây sẽ bị bỏ dấu hai lần hoặc lỗi chữ.
  - Gõ Nhanh đã làm việc này cho RustDesk, AnyDesk và TeamViewer.
  - LeanKeys thêm: MacViewer (tương thích UltraViewer), Windows App / Microsoft Remote Desktop, Parsec, RealVNC Viewer, Jump Desktop, Screens, Screen Sharing của Apple, Splashtop, NoMachine, VMware Fusion, Parallels Desktop, UTM, VirtualBox; từ 2026-11-17 (audit bảo mật LOW-4) thêm DeskIn, Citrix Workspace, VMware Horizon, Royal TSX.
  - Danh sách nằm trong `KeyPassthrough.remoteBundleIDs`.
- **Terminal (2026-11-17, ruling R22, theo yêu cầu người dùng).** Mọi phím đi thẳng trong mọi app terminal (`CodeApps.terminals`: Terminal, iTerm2, Warp, Ghostty, Alacritty, kitty, WezTerm, Hyper, Tabby…): không bỏ dấu, không gõ tắt, không viết hoa, không học. Dấu nhắc `sudo`, `ssh`, `passwd`, `git` nhận mật khẩu ở đó mà không có ô bảo mật, còn lệnh thì không phải tiếng Việt. Cấu hình theo app không bật lại được. Giới hạn: terminal nằm trong trình soạn code (VS Code, Cursor, JetBrains…) vẫn gõ tiếng Việt, vì LeanKeys không phân biệt được nó với phần soạn thảo; ở đó trình soạn code chỉ không bị học (12.3). Muốn chắc chắn khi gõ mật khẩu trong terminal của trình soạn code, chuyển sang English trước.
- **Trình quản lý mật khẩu và hộp thoại đăng nhập của macOS (2026-11-17, audit bảo mật MEDIUM-3).** Mọi phím đi thẳng ở mọi ô của: 1Password, Bitwarden, KeePassXC, Enpass, LastPass, Proton Pass, Keychain Access, Passwords của Apple (`Exclusions.passwordManagers`), hộp thoại xin quyền quản trị (`com.apple.SecurityAgent`, `SecurityAgentHelper`) và màn đăng nhập (`com.apple.loginwindow`). Ô tên người dùng, khoá TOTP, mã khôi phục ở đó là ô văn bản thường, Telex sẽ đổi chúng. Danh sách: `KeyPassthrough.credentialAppBundleIDs`; app nào cũng không có cách bật lại tiếng Việt (cấu hình theo app không đè được).
- **Ô đăng nhập và mật khẩu.** Ô được nhận ra khi:
  - đó là ô mật khẩu của hệ thống (`AXSecureTextField`); hoặc
  - đó là ô một dòng (`AXTextField`, `AXComboBox`) có chữ gợi ý, nhãn, tiêu đề, chú thích (`AXHelp`), mã định danh, hay chữ của nhãn gắn với ô (`AXTitleUIElement`, nhãn rời của form AppKit) chứa một trong các từ trong `KeyPassthrough.credentialWords` (khớp nguyên từ, sau khi chuẩn hoá NFC và viết thường; mã định danh được tách ở chỗ chữ thường sang chữ hoa và ở `_ - .`, nên `txtPassword`, `loginEmail`, `otpCode`, `identifierId` đều khớp). Danh sách gồm: password, passwd, passcode, passphrase, pin, otp, 2fa, username, user name, userid, user id, login, log in, sign in, signin, email, e-mail, account, apple id, identifier id, verification, verify, security code, authenticator, token, secret, cvv, cvc, phone, mobile, mật khẩu, mật mã, tên đăng nhập, tên người dùng, đăng nhập, tài khoản, mã xác nhận, mã otp, mã xác thực, xác thực, mã xác minh, mã bảo mật, mã kích hoạt, số điện thoại, sđt (cùng dạng không dấu). Số điện thoại có trong danh sách vì ngân hàng và ví điện tử Việt Nam đăng nhập bằng số điện thoại.
  - Mã định danh viết liền một mạch (`userpassword`, `loginemail`) khớp khi chứa password, passwd, passcode, passphrase, username, userid, login, signin hay email. Từ ngắn (pin, otp) không tìm bên trong từ khác ("shipping", "hotpot").
  - App Electron (Slack, Discord, Bitwarden…) chỉ dựng cây Trợ năng của trang web khi có app trợ năng hỏi. Khi chuyển sang một app có `Electron Framework.framework`, LeanKeys đặt `AXManualAccessibility` một lần cho tiến trình đó, ngoài luồng phím (`KeyPassthrough.prepare`), để ô đăng nhập trong đó đọc được.
  - Hỏi AX lỗi hay quá giờ thì ô được coi là ô thường khi gõ (gõ không bị chặn), nhưng là ô mật khẩu khi học (12.3).
  - Ở các ô đó, phím đi thẳng, kể cả khi đang bật tiếng Việt.
- **Cách gắn.** Một dòng trong `detectMethod()` của Gõ Nhanh, có đánh dấu hook `engine-dispatch`. Phần này chạy khi bộ nhớ đệm 200 ms hết hạn và dùng phần tử đang có con trỏ mà Gõ Nhanh đã lấy, nên thêm một lần hỏi AX (`AXUIElementCopyMultipleAttributeValues`, giới hạn 25 ms), cộng một lần nữa cho chữ của nhãn gắn với ô khi có (`AXTitleUIElement`). Hỏi lỗi hay hết giờ thì ô được coi là ô thường khi gõ, tối đa tới lần dò sau (200 ms); việc học vẫn coi đó là ô mật khẩu nên không lưu gì (review bảo mật M-4, M-13). Phím đi thẳng không được ghi dòng nào vào nhật ký, kể cả dòng chọn cách gửi phím (M-7). Khi phím đi thẳng, cụm đang gõ dở bị bỏ (`discardPending`).
  - **(ghi chú 2026-11-16)** Lần hỏi AX này của `KeyPassthrough` vẫn nằm trong `RustBridge.detectMethod`, trên đường chậm sẵn có của Gõ Nhanh (tối đa một lần mỗi 200 ms, cùng lúc Gõ Nhanh tự hỏi AX), nên được giữ nguyên; các lần hỏi AX của việc học (12.3) thì đã chuyển khỏi luồng phím.
- **(2026-11-17, audit bảo mật MEDIUM-1, LOW-1)** Bộ nhớ đệm 200 ms hết hạn ngay khi con trỏ có thể đã sang ô khác: bấm chuột, Tab, Return/Enter, và khi Spotlight hay Raycast đổi ô (`DetectionCache.expire`; chỉ các bảng nổi đó được theo dõi đổi ô). Một lần dò đang chạy dở khi con trỏ đổi ô không được ghi vào bộ nhớ đệm (bộ đếm thế hệ). Phím đầu tiên gõ vào ô đăng nhập vừa Tab tới vì vậy đã đi thẳng. Phím tắt khôi phục chữ không chạy khi phím đang đi thẳng, và bộ đệm của Gõ Nhanh được xoá cùng lúc với cụm gõ dở.
- **Test:** `KeyPassthroughTests`, gồm cả các ô thường phải gõ tiếng Việt bình thường (tìm kiếm, "Shopping list", ô soạn tin nhắn).
- **Thử tay:**
  - gõ `nguyenvana` vào ô Email/Username của một trang đăng nhập trên Safari: giữ nguyên chữ;
  - gõ vào một máy Windows qua MacViewer, TeamViewer hay AnyDesk: chữ do bộ gõ bên Windows xử lý, không bị bỏ dấu hai lần;
  - mật khẩu gõ ở dấu nhắc `sudo` trong Terminal không xuất hiện trong gợi ý gõ tắt;
  - trong Terminal, đang bật tiếng Việt, gõ `vieejt` vẫn ra `vieejt`.

### 18.2 Nhật ký debug không lộ chữ gõ

Thêm ngày 2026-11-16 sau đánh giá toàn bộ ứng dụng. Gõ Nhanh gốc ghi nhật ký phím vào `/tmp/gonhanh_debug.log` mỗi khi tệp đó tồn tại, kèm từng ký tự và mã phím. `/tmp` dùng chung cho mọi người dùng và mọi tiến trình, nên bất kỳ chương trình nào trên máy cũng bật được nhật ký và đọc được những gì người dùng gõ, kể cả trong ô đăng nhập dạng văn bản thường, mà không cần quyền Accessibility.

LeanKeys:
- giữ nhật ký trong `~/Library/Logs/LeanKeys/debug.log` (thư mục 0700, tệp 0600), bật và tắt từ Cài đặt nâng cao như trước (`DebugLog` trong LeanKeysKit);
- không bao giờ ghi ký tự đã gõ hay văn bản được chèn: chỉ ghi độ dài, dạng `<3>`;
- không ghi mã phím của phím ký tự (chữ, số, dấu): ghi `char`; chỉ phím điều khiển (Return, Enter, Tab, Space, ⌫, Esc, xoá xuôi, mũi tên, Home, End, Page Up, Page Down) giữ mã;
- không đụng tới `/tmp/gonhanh_debug.log` có sẵn (có thể là của một bản Gõ Nhanh cài riêng).

**(2026-11-17, audit bảo mật LOW-2)** Phím đi thẳng (ô đăng nhập, terminal, trình quản lý mật khẩu, điều khiển từ xa) không được ghi vào nhật ký, kể cả số lần bấm. Dòng chọn cách gửi phím không ghi loại ô (`role`). Nhật ký tự tắt: tệp tạo cách đây hơn 24 giờ bị xoá khi app mở hay khi đọc lại công tắc (`DebugLog.isOnAfterExpiry`), vì tiến trình nào của cùng người dùng cũng tạo được tệp đó.

Điều còn lại, chấp nhận: nhật ký vẫn cho thấy nhịp gõ và độ dài từ, vì không có chúng nhật ký không còn dùng được để tìm lỗi.

`tests/privacy/test_debug_log.sh` (bước 5 của `.githooks/pre-push`) chặn mọi lần đồng bộ bản gốc đưa lại đường dẫn `/tmp` hay dòng nhật ký ghi chữ gõ. Thử tay: mục K4 trong `sync/manual-checklist.md`.

## 19. Gõ chữ hoa bằng Caps Lock

Thêm ngày 2026-11-17, theo lỗi người dùng báo: gõ "BÙI" bằng Caps Lock trong Canva ra "BUIF".

- **Nguyên nhân (Vikey, D23/D41):** để từ viết tắt (USA, IRS) không bị bỏ dấu, Vikey chỉ giữ dấu cho một từ viết hoa toàn bộ khi từ trước nó cũng viết hoa toàn bộ, hoặc khi phím của nó có nguyên âm gõ đúp hay `w`. Từ đầu tiên của một dòng chữ hoa (thường là họ) bị trả về phím gốc ở dấu cách: `BUIF` hiện "BÙI" rồi thành "BUIF". Điểm từ điển của Vikey lấy từ tin nhắn chat nên họ tên điểm thấp ("bùi" 3, "nguyễn" 5), ngang từ viết tắt IRS (6), nên ngưỡng 15 của Vikey cũng loại chúng.
- **LeanKeys:** Caps Lock bật cho mọi chữ của từ chính là "dòng chữ hoa" Vikey cần. Khi Vikey trả một từ gõ bằng Caps Lock về phím gốc (thực tế là từ không nằm trong dòng chữ hoa: đầu dòng, sau con số) ở dấu cách hay dấu câu, LeanKeys giữ từ tiếng Việt (chặn lần sửa đó, như 12.2) nếu: mọi chữ gõ bằng Caps Lock (không giữ Shift), từ bắt đầu ở chế độ tiếng Việt, phím gốc không phải từ tiếng Anh, và từ là âm tiết thông dụng (điểm ≥ 15) hoặc là họ, tên đệm, tên trong dữ liệu 4D (`ProperNouns.json`). ⌫⌫ ngay sau đó trả lại phím gốc; lần ⌫⌫ này không được báo cho việc tự học từ hoàn tác (12.2), vì luật này không phải do sổ luật đặt ra. Gõ bằng Shift giữ nguyên cách Vikey quyết định. Hệ quả đã chấp nhận: từ được giữ trở thành từ trước của một dòng chữ hoa theo luật của Vikey, nên "BUIF COS" ra "BÙI CÓ", như "THỊ CÓ" vốn đã vậy; quét mọi chuỗi chữ hoa 2–4 ký tự, chỉ 10 chuỗi đổi kết quả và đều là tên (BÙI, NGÔ, HƯNG, PHÚ, TÚ).
- **Vị trí:** `leankeys/VikeyShim` (`capsLockKeeps`, `lk_vikey_set_caps_lock`, `lk_vikey_set_caps_words`) và `VikeyEngine` (Caps Lock = chữ hoa mà không giữ Shift). `vendor/` không đổi.
- **Test:** `CapsLockWordTests` (BÙI, NGUYỄN, BÙI THỊ XUÂN, 453 BÙI MÌ, BÀN; USA, IRS, HTML giữ nguyên; Shift giữ nguyên; ⌫⌫).

## 20. Khoá mã hoá dữ liệu tự học nằm trong tệp, không trong Keychain

Thêm ngày 2026-11-17, theo lỗi người dùng báo: LeanKeys liên tục đòi mật khẩu máy ("LeanKeys wants to access key 'LeanKeys learned phrases' in your keychain").

- **Nguyên nhân:** khoá AES và HMAC của các kho tự học (gợi ý gõ tắt, từ giữ nguyên, tên đã học) nằm trong login Keychain. App ký bằng chứng chỉ tự cấp, không có Team ID, nên macOS gắn quyền đọc mỗi mục vào cdhash của bản build đã tạo hay đã được cho phép (danh sách `partition_id` chứa các `cdhash:`). Mỗi bản cập nhật có cdhash mới, nên với mọi người dùng, mỗi lần cập nhật macOS hỏi mật khẩu một lần cho mỗi mục. Không có cách nào tránh được khi vẫn dùng Keychain mà không có Team ID (quyết định không mua Developer ID, mục 15).
- **LeanKeys:** mỗi kho giữ hai khoá (32 byte ngẫu nhiên) trong tệp cạnh tệp dữ liệu, `<tệp>.aes-gcm.key` và `<tệp>.hmac-sha256.key`. Tệp có quyền 0600, thư mục `~/Library/Application Support/LeanKeys` có quyền 0700, ghi qua tệp tạm `O_EXCL` rồi đổi tên. Dữ liệu vẫn mã hoá AES-GCM như cũ.
- **Đánh đổi đã chấp nhận:** một tiến trình khác của cùng người dùng đọc được tệp khoá mà không bị hỏi, trong khi Keychain sẽ hỏi. Tiến trình như thế vốn đã đọc được nhiều thứ khác của người dùng.
- **Chuyển từ bản cũ (một lần):** một kho đã có dữ liệu nhưng chưa có tệp khoá nào (kho của LeanKeys ≤ 1.3) lấy cả hai khoá từ Keychain cùng lúc. macOS hỏi mật khẩu lần cuối, mỗi mục một lần; nên bấm "Always Allow". LeanKeys chép khoá sang tệp rồi xoá mục trong Keychain. Nếu người dùng bấm Deny, kho đó được coi là không đọc được trong phiên này và không bị ghi đè (R16); lần mở sau thử lại. Kho chưa có dữ liệu không bao giờ hỏi Keychain.
- **Test:** `FileKeyStoreTests` (khoá trong tệp, quyền, chuyển một lần, Deny, xoá); `KeychainEncryptedFileStoreTests.testKeychainKeysMoveToFiles` (Keychain thật).

## 21. Gửi bản sửa vào trình soạn thảo trong trình duyệt

Thêm ngày 2026-11-17, theo lỗi người dùng báo: từ đầu tiên "kieemr" không thành "kiểm" trong ô nhập của app Claude, chữ "s" bị lặp ("maussbot"); lỗi có từ khi dùng lõi Vikey.

- **Tái hiện (webbench, Chrome):** trong trình soạn thảo ProseMirror (ô nhập của Claude, Tiptap, nhiều web app), các phím xoá lùi LeanKeys gửi bị mất: "Hoom" ra "Hoôm" hay "Ho\u202Fôm", "dduwowcj," ra "dduwowcj được,", câu tiếng Anh ra "me êting meeting". Lexical (Messenger), Quill, contenteditable và ô nhập thì đúng. Lõi Vikey hay xoá cả từ rồi gõ lại khi tự chuyển Việt/Anh, nên lỗi lộ rõ hơn với Gõ Nhanh.
- **Đo (2026-11-17, cùng câu, cùng tốc độ):**

  | Cách gửi | ProseMirror | Lexical, Quill, contenteditable, ô nhập |
  |---|---|---|
  | emptyCharPrefix (Gõ Nhanh, mặc định cũ cho mọi ô trình duyệt) | hỏng | đúng |
  | charByChar | hỏng | đúng |
  | fast | hỏng | đúng |
  | slow (8 ms, chờ 25 ms) | hỏng | (không đo) |
  | selection (Shift+← chọn rồi gõ đè) | **đúng** | đúng |

- **LeanKeys:** trong các trình duyệt Gõ Nhanh liệt kê, ô có role `AXTextArea` hay `AXWebArea` (vùng soạn thảo) dùng `selection`; `AXTextField`, `AXComboBox` (thanh địa chỉ, ô một dòng, ô có gợi ý) giữ `emptyCharPrefix`. Ngoài trình duyệt, mọi ô `AXTextArea` có class DOM `ProseMirror` (đọc qua `AXDOMClassList`, giới hạn 25 ms) cũng dùng `selection`: ô nhập của app Claude desktop là ProseMirror trong Electron. Safari không đổi. Cài đặt ẩn `LeanKeys.browserEditorMethod` (fast, slow, charByChar, emptyCharPrefix, selection) để đo lại. Code: `BrowserEditorInjection` (LeanKeysKit) và một hook `engine-dispatch` trong `detectMethod`.
- **Chưa đo được:** textarea và Slate (Discord), vì máy đo bị app khác gửi phím chen vào; app Claude desktop chưa được đo bằng webbench (nhận ra qua class ProseMirror, người dùng thử tay). Một dấu chấm lạ cuối câu ("Hà Nội. ") xuất hiện một lần ở ProseMirror, cần kiểm tra (có thể là "thêm dấu chấm khi gõ hai dấu cách" của macOS).

