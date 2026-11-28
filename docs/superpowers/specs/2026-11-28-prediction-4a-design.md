# Gợi ý từ, cụm từ, câu tiếp theo kiểu Laban Key (4A+) — Thiết kế

Ngày 2026-11-28. Triển khai mục 4A của spec chính (§4, §11.2) và mở rộng thêm dự đoán cụm từ, câu kiểu Laban Key, tuân thủ tuyệt đối chính sách quyền riêng tư opt-in (`docs/superpowers/specs/2026-11-28-privacy-opt-in-design.md`).

## 1. Mục tiêu

1. **Khi vừa gõ xong một từ (sau Space):** gợi ý tối đa 3 ứng viên hợp ngữ cảnh ngay bên cạnh con trỏ, kết hợp giữa **từ tiếp theo**, **cụm từ**, và **câu tiếp nối** (ví dụ: `"cảm "` → `ơn`, `ơn bạn nhiều`, `ơn anh nhiều`; `"mình sẽ "` → `kiểm tra lại`, `gửi lại bạn`, `cập nhật sau`).
2. **Khi đang gõ dở một từ (≥ 2 ký tự):** gợi ý hoàn thành từ / cụm từ từ:
   - Bảng gõ tắt của người dùng;
   - Ngữ cảnh trước đó khớp tiền tố đang gõ (cả có dấu và không dấu);
   - Kho âm tiết tiếng Việt, từ vựng cá nhân đã học, và từ điển Vikey (`vAutoSwitchCompletions`).
3. **Chọn nối tiếp (chaining):** bấm `Tab` chọn `"ơn"` xong, thanh gợi ý cập nhật ngay gợi ý cho `"cảm ơn "` để có thể bấm `Tab` tiếp hoàn thành cả cụm.
4. **Không tự ý sửa chữ:** thanh gợi ý chỉ hiển thị để người dùng chủ động chọn (`Tab`, `⌥1`–`⌥3`, hoặc bấm chuột). Không bao giờ tự thay từ đã gõ đúng.

## 2. Điều khiển bàn phím & giao diện

- **Thanh gợi ý nổi (`CandidatePanel`):** `NSPanel` không kích hoạt (`.nonactivatingPanel`, `canBecomeKey = false`, `level = .popUpMenu`), nền mờ `.popover`, neo ngay dưới hoặc trên vị trí con trỏ (`CaretLocator`, timeout AX 25 ms).
- **Phím tắt khi thanh gợi ý đang hiện:**
  - `Tab` (không modifier): chèn gợi ý #1.
  - `⌥1`, `⌥2`, `⌥3`: chèn gợi ý #1, #2, #3.
  - `Esc`: ẩn thanh gợi ý (nuốt phím Esc ở lần đó).
  - Mũi tên, Home/End, PageUp/Down, Return/Enter, tổ hợp `⌘`, click chuột, chuyển app, vào Secure Input: tự động ẩn.
- **Giữ chữ hoa:** khi hoàn thành từ đang gõ dở (`Chươ` → `Chương`, `CHƯƠ` → `CHƯƠNG`), giữ nguyên kiểu viết hoa/thường.

## 3. Loại trừ an toàn & Quyền riêng tư (Opt-in)

Tuân thủ spec `2026-11-28-privacy-opt-in`:
- `LeanKeys.predict.enabled` (Bool, mặc định **`false`**): bật/tắt thanh gợi ý nổi. Có thể bật dùng riêng kho từ/cụm tích hợp mà **không lưu gì từ người dùng**.
- `LeanKeys.predict.learn` (Bool, mặc định **`false`**) và `LeanKeys.predict.learnConsented` (Bool, mặc định **`false`**): học từ ngữ cảnh người dùng gõ. Bắt buộc hiện hộp thoại đồng ý giải thích rõ dữ liệu chỉ nằm trên máy, được mã hoá AES-GCM, không gửi đi đâu. Trước khi đồng ý, **không ghi file hoặc khoá nào ra đĩa**.
- **Lưu trữ cá nhân:** `~/Library/Application Support/LeanKeys/prediction.bin` (0600, `KeychainEncryptedFileStore`). Cụm/câu chỉ được gợi ý khi xuất hiện **≥ 2 lần**. Có nút **"Xoá dữ liệu gợi ý"** trong Cài đặt › Nâng cao.
- **Loại trừ:** không hiện gợi ý và không học trong Secure Input, ô mật khẩu (`AXSecureTextField`, `KeyPassthrough`), ô tìm kiếm/địa chỉ (`AXSearchField`, `AXComboBox`), terminal & trình soạn code (`CodeApps`), trình quản lý mật khẩu, app điều khiển từ xa, và danh sách app người dùng loại trừ. Không học số thẻ/OTP (`Exclusions.containsSensitiveNumber`) hoặc từ dạng mật khẩu (`Exclusions.looksLikeSecret`).

## 4. Kiến trúc & Điểm gắn

- **C++ Shim (`leankeys/VikeyShim`):** `lk_vikey_completions` và `lk_vikey_render_telex` đọc từ `vendor/vikey` (không sửa `vendor/`).
- **Swift Module (`leankeys/LeanKeysKit/Predict/`):**
  - `BuiltInPredictionCorpus` + `Resources/VietnamesePredictions.json`
  - `PersonalPredictionModel`
  - `PredictionEngine`
  - `CaretLocator`
  - `CandidatePanelController`
  - `PredictionController`
  - `PredictionSettingsSection` (UI cho Chung & Nâng cao)
- **Hook Gõ Nhanh (`platforms/macos/`):** tái sử dụng đúng 3 tên hook đã đăng ký trong `sync/hooks.txt` (`engine-dispatch`, `menubar-popover`, `settings-engine`), không thêm tên hook mới.
