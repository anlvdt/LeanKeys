# Gõ tiếng Việt trong terminal — thiết kế ngắn (2026-11-24)

## Mục đích
Người dùng chat với các agent CLI (Claude Code, Codex…) trong **Ghostty** và **Terminal**, nên cần gõ tiếng Việt ở đó. Hiện quy tắc R22 (2026-11-17) cho mọi phím trong mọi terminal đi thẳng.

## Mục tiêu / không làm
- Bật tiếng Việt cho **từng terminal** mà người dùng chọn. Mặc định: không terminal nào (R22 giữ nguyên cho đến khi người dùng bật).
- Trong terminal đã bật: gõ như app thường (Telex, tự chuyển Việt/Anh, gõ tắt, công tắc "Tự sửa khi gõ").
- Vẫn **không bao giờ** học hay lưu thứ gõ trong terminal: không học từ ⌫⌫, không gợi ý gõ tắt, không học tên riêng; không tự viết hoa, không lọc phím lỡ bấm cùng Enter, Enter không chốt từ. Những việc này đã dựa vào danh sách `CodeApps`, không đổi.
- Không làm: tự nhận ra agent đang chạy (terminal không cho biết tab nào ở trước), một công tắc chung cho mọi terminal.
- Thất bại nếu: một terminal không được chọn mà vẫn nhận tiếng Việt; hoặc bất kỳ thứ gì gõ trong terminal bị ghi vào dữ liệu học.

## Cách làm (đã chọn: A)
- A. Danh sách terminal được bật, mỗi terminal một ô đánh dấu, mặc định tắt. **Chọn**: đúng nhu cầu, an toàn cho terminal khác, chạm một chỗ.
- B. Một công tắc chung: mở cả terminal không dùng với agent.
- C. Tự nhận ra `claude`/`codex` đang chạy: không biết tab nào đang ở trước, có thể bật tiếng Việt đúng lúc gõ `sudo` ở tab khác.

## Thiết kế
- Cài đặt `LeanKeys.terminalVietnamese`: mảng bundle ID, mặc định rỗng.
- `KeyPassthrough.reason(bundleID:focused:)`: terminal có trong danh sách này thì không trả `"terminal"` (các kiểm tra khác giữ nguyên: ô đăng nhập, app quản lý mật khẩu, điều khiển từ xa).
- Đổi danh sách thì bỏ kết quả dò đã nhớ (`clearDetectionCache()` / `DetectionCache.expire()`), để có hiệu lực ngay, không phải đổi app.
- Giao diện: trang Nâng cao, mục "Gõ tiếng Việt trong terminal", một hàng cho mỗi terminal trong `CodeApps.terminals` **có cài trên máy**, có tên app và ô đánh dấu. Ghi chú dưới mục: "Chuyển sang English trước khi gõ mật khẩu (sudo, ssh): LeanKeys không biết lúc nào terminal hỏi mật khẩu. Thứ gõ trong terminal không bao giờ được học."
- Cập nhật mục R22 trong `docs/superpowers/specs/2026-11-15-leankeys-design.md`: thêm ngoại lệ do người dùng bật theo từng terminal.
- Sửa file gốc Gõ Nhanh (nếu có) → `LEANKEYS-HOOK`, đăng ký trong `sync/hooks.txt`.

## Để người làm tự quyết
Nơi đặt danh sách (LeanSettings hay KeyPassthrough), cách lấy tên app, test (TDD: terminal không chọn vẫn đi thẳng; terminal đã chọn không đi thẳng; ô đăng nhập trong terminal đã chọn vẫn đi thẳng; terminal đã chọn vẫn bị loại khỏi học và viết hoa).
