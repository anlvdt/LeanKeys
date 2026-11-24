# Công tắc chính "Tự sửa khi gõ" — thiết kế ngắn (2026-11-24)

## Mục đích
Người dùng muốn gõ theo ý mình: phím ra đúng Telex, LeanKeys không đoán, không đổi ngôn ngữ, không sửa chữ thay họ. Hiện các việc tự sửa nằm rải ở nhiều tầng, có việc không tắt được (Vikey tự chuyển Việt/Anh, D19, Enter chốt từ).

## Mục tiêu / không làm
- Một công tắc chính, mặc định **bật**. Tắt thì mọi việc tự sửa dừng; bật lại thì các công tắc con trở về như cũ (không ghi đè lựa chọn của chúng).
- Giữ nguyên những gì người dùng tự đặt: bảng gõ tắt, nhớ Việt/Anh theo ứng dụng, kiểu đặt dấu, W→Ư, [ ]→ơ ư, phím tắt chuyển Việt/Anh, gợi ý gõ tắt (chỉ gợi ý, người dùng tự thêm).
- Không làm: công tắc theo từng ứng dụng, nút trong ô nổi (có thể làm sau).
- Thất bại nếu: tắt rồi mà vẫn có chữ tự đổi, hoặc bật lại mà cấu hình con bị mất.

## Cách làm (đã chọn: A)
- A. Công tắc chính, Vikey ở chế độ gõ thuần. **Chọn**: giữ cảm giác gõ của Vikey; chỉ thêm một lớp đè lên công tắc con.
- B. Chuyển sang engine Gõ Nhanh, tắt tự khôi phục: Telex thuần đã kiểm chứng, nhưng đổi engine làm hai kiểu gõ khác nhau theo một công tắc.
- C. Nút "tắt tất cả" lật các công tắc con: mất cấu hình, không chạm được tự chuyển của Vikey.

## Thiết kế
- Cài đặt `LeanKeys.autoFix` (Bool, mặc định true) trong `LeanSettings`.
- Tắt (engine Vikey):
  - shim: `lk_vikey_set_options(..., autoSwitch=0, ...)` và hàm mới `lk_vikey_set_restore_wrong_spelling(0)` (đặt `vRestoreIfWrongSpelling`). Đã thử bằng harness: `test`→"tét", `push`→"púh", `coss`→"cos", không bao giờ đổi ngôn ngữ.
  - router: không bật Enter chốt từ, không sửa ⌫ sau phím gõ đúp (`setDoubleKeyFix(false)`), không tự viết hoa, không lọc phím lỡ bấm cùng Enter, không học từ ⌫⌫ (không có bản sửa nào để học).
- Tắt (engine Gõ Nhanh, khi VNI hoặc người dùng chọn): `englishAutoRestore` và `autoCapitalize` của Gõ Nhanh nhận giá trị `cài đặt con && autoFix` (sửa file gốc Gõ Nhanh → `LEANKEYS-HOOK`, đăng ký trong `sync/hooks.txt`).
- Giao diện: hàng "Tự sửa khi gõ" ở trang Chung, ngay dưới "Gõ tiếng Việt", phụ đề "Tắt: phím ra đúng Telex, LeanKeys không tự đổi chữ hay Việt/Anh". Khi tắt, các công tắc con (Nâng cao, Tự khôi phục tiếng Anh, Tự viết hoa đầu câu) mờ đi và ghi "Đang tắt bởi Tự sửa khi gõ". Dòng trạng thái trong ô nổi: "Tự chuyển Việt/Anh: Tắt".
- Đổi công tắc thì xoá trạng thái từ đang gõ (`resetContext`).

## Để người làm tự quyết
Tên hàm, cách gom cờ trong router, thứ tự hàng trong Nâng cao, nội dung test (TDD: mỗi việc tự sửa có một test "tắt thì không xảy ra", và test bật lại giữ cấu hình con).
