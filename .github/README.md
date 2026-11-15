# LeanKeys

Bộ gõ tiếng Việt cho macOS. LeanKeys là bản fork của [Gõ Nhanh](https://github.com/khaphanspace/gonhanh.org), thêm engine [Vikey](https://github.com/tonyminibot/Vikey) để bạn chọn trong Cài đặt:

- **Gõ Nhanh** (mặc định): Telex và VNI, gõ tắt, khôi phục từ tiếng Anh.
- **Vikey**: Telex, tự chuyển Việt/Anh theo ngữ cảnh.

Đổi engine có tác dụng ngay, không cần khởi động lại app.

## Tải về

Tải `LeanKeys-x.y.dmg` mới nhất ở trang [Releases](https://github.com/anlvdt/LeanKeys/releases), mở file và kéo `LeanKeys.app` vào thư mục Applications.

LeanKeys chưa được Apple công chứng (ký ad-hoc), nên lần đầu macOS có thể báo app "bị hỏng" hoặc "không xác định được nhà phát triển". Mở Terminal và chạy:

```sh
xattr -cr /Applications/LeanKeys.app
```

rồi mở lại app.

Đừng chạy LeanKeys cùng lúc với app Gõ Nhanh gốc: hai bộ gõ sẽ cùng xử lý phím.

## Cấp quyền Accessibility

LeanKeys cần quyền Accessibility để đọc và gửi phím.

1. Mở LeanKeys. Màn hướng dẫn hiện ra, bấm **Mở Cài đặt**.
2. Trong **System Settings → Privacy & Security → Accessibility**, bật công tắc cạnh **LeanKeys**.
3. Quay lại LeanKeys và bấm **Khởi động lại**.

Mỗi bản cập nhật ký ad-hoc có thể làm macOS quên quyền này. Khi đó LeanKeys tự mở lại màn hướng dẫn; nếu LeanKeys vẫn có trong danh sách mà không gõ được, xoá nó khỏi danh sách (nút −) rồi bật lại.

## Chọn engine

Bấm biểu tượng LeanKeys trên thanh menu → **Cài đặt** → mục **Engine gõ**, chọn Gõ Nhanh hoặc Vikey. Vikey không hỗ trợ VNI; khi kiểu gõ là VNI, LeanKeys dùng engine Gõ Nhanh và ghi rõ lý do dưới lựa chọn.

## Tự build

Cần Xcode và Rust (`rustup`).

```sh
leankeys/build.sh --version 1.0          # ra dist/LeanKeys.app
leankeys/build.sh --version 1.0 --dmg    # thêm dist/LeanKeys-1.0.dmg
```

## Phát triển

Bật cổng test trước khi push (một lần cho mỗi bản clone):

```sh
git config core.hooksPath .githooks
```

Từ đó mỗi `git push` chạy `.githooks/pre-push`: `cargo test` trong `core/`, `swift test`, test engine Vikey, `sync/check-divergence.sh` và test của `sync/`. Chạy tay `.githooks/pre-push --all` để thêm bản build Release.

Đăng bản: `sync/release.sh --dry-run` để xem trước, rồi `sync/release.sh` (cần `gh` đã đăng nhập). Danh sách thử tay trước khi đăng nằm trong `sync/manual-checklist.md`.

## Ghi công

- [Gõ Nhanh](https://github.com/khaphanspace/gonhanh.org): khaphanspace và cộng đồng Gõ Nhanh, BSD-3-Clause.
- [Vikey](https://github.com/tonyminibot/Vikey): Tony Dinh, GPL-3.0.
- [OpenKey](https://github.com/tuyenvm/OpenKey): Mai Vũ Tuyên, GPL-3.0.

Chi tiết trong [ACKNOWLEDGEMENTS.md](../ACKNOWLEDGEMENTS.md).

## Giấy phép

LeanKeys phát hành theo [GPL-3.0](../LICENSE). Phần mã của Gõ Nhanh giữ giấy phép BSD-3-Clause gốc ([LICENSES/gonhanh-BSD-3.txt](../LICENSES/gonhanh-BSD-3.txt)).
