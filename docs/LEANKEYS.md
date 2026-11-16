# LeanKeys: hướng dẫn cho người phát triển

LeanKeys là bản fork của Gõ Nhanh, thêm engine Vikey. Các tài liệu khác trong `docs/` là của Gõ Nhanh. Tệp này là điểm vào cho phần của LeanKeys. Thiết kế đầy đủ nằm ở `docs/superpowers/specs/2026-11-15-leankeys-design.md`.

Mã của LeanKeys nằm trong `leankeys/` (gói Swift `LeanKeysKit`, shim C cho Vikey), `sync/`, `tests/` và `tools/`. Mã Swift của Gõ Nhanh nằm trong `platforms/macos/`. Không sửa `core/` và `vendor/vikey/`.

## Build

```sh
leankeys/build.sh [--version X.Y] [--dmg]
```

Ra `dist/LeanKeys.app` (universal), và `dist/LeanKeys-X.Y.dmg` khi có `--dmg`. `leankeys/build.sh --help` in cách ký.

## Cổng test

Bật một lần cho mỗi bản clone:

```sh
git config core.hooksPath .githooks
```

Sau đó git chạy `.githooks/pre-push` trước mỗi lần push. Chạy tay: `.githooks/pre-push [--all]`. Sáu bước, dừng ở bước đầu tiên lỗi:

1. `cd core && cargo test` (lõi Gõ Nhanh)
2. `swift test` (LeanKeysKit). Bỏ qua các test Keychain bằng `LEANKEYS_SKIP_KEYCHAIN_TESTS=1`.
3. `vendor/vikey/Tools/autoswitch/check.sh` (engine Vikey)
4. `sync/check-divergence.sh <tag Gõ Nhanh trong sync/upstream.json>`
5. `tests/sync/test_check_divergence.sh`, `test_sync.sh`, `test_release.sh`, `tests/update/test_swap_script.sh`, `tests/build/test_signing_identity.sh`, `tests/privacy/test_debug_log.sh`
6. Chỉ với `--all`: `tests/build/test_build_output.sh` (build Release rồi kiểm tra bundle)

## Đồng bộ với Gõ Nhanh và Vikey

- `sync/sync.sh [--repo DIR] [--no-notify] [--skip-build]`: lấy bản mới của hai nguồn, merge vào một nhánh sync, chạy cổng test, cập nhật `main` và build DMG. Mã thoát ghi ở đầu tệp.
- `sync/install-launchd.sh [--check | --uninstall]`: cài job chạy `sync.sh` mỗi ngày lúc 03:00.

## Phát hành

- `sync/release.sh [--dry-run]` đăng bản `sync.sh` để lại trong `dist/` lên GitHub.
- Trước đó, làm hết `sync/manual-checklist.md`. Script in danh sách này ra và chờ bạn gõ `yes`.

## Điểm gắn vào mã Gõ Nhanh

- Mọi dòng sửa trong tệp có sẵn ở Gõ Nhanh (ví dụ `platforms/macos/…`) phải mang `// LEANKEYS-HOOK: <tên>`, hoặc nằm trong khối `LEANKEYS-HOOK-BEGIN: <tên>` … `LEANKEYS-HOOK-END`.
- Tên đó phải được đăng ký cho đúng tệp trong `sync/hooks.txt` (`<tên><TAB><đường dẫn>`). Có tối đa 12 tên.
- `sync/check-divergence.sh <tag>` kiểm tra điều này (`--help` để xem quy tắc). Tệp mới không bị kiểm tra, nên tài liệu mới của LeanKeys nằm trong tệp mới như tệp này.

## Ảnh giao diện

```sh
LEANKEYS_SNAPSHOTS=1 LEANKEYS_SKIP_KEYCHAIN_TESTS=1 swift test --filter UISnapshotTests
```

Ghi ảnh sáng và tối vào `docs/ui/`. Xem từng ảnh đã đổi. Nếu chỉ muốn xem mà không commit, trả lại bằng `git checkout -- docs/ui`.

## Đo đạc

- `tools/capbench`: tự viết hoa tên riêng (4D). Xem `tools/capbench/README.md`.
- `tools/mixbench`: gõ trộn Việt/Anh và lỗi sửa bằng ⌫ (4C). Xem `tools/mixbench/README.md`.

## Nhật ký gỡ lỗi

- Bật trong Cài đặt → Nâng cao → Nhật ký gỡ lỗi.
- Tệp ở `~/Library/Logs/LeanKeys/debug.log` (quyền 0600) và không chứa chữ gõ. Tắt công tắc là tệp bị xoá.
- Bỏ qua mục `/tmp/gonhanh_debug.log` trong `docs/code-standards.md` (tài liệu của Gõ Nhanh). LeanKeys không ghi tệp đó.

## Ngôn ngữ của script

- Script chỉ dành cho người phát triển báo lỗi cách dùng bằng tiếng Anh: `build.sh`, đối số của `sync.sh`, `pre-push`, `check-divergence.sh`.
- Thông báo đồng bộ và phát hành mà bạn đọc khi vận hành dùng tiếng Việt: các lỗi của `sync.sh`, `release.sh`, thông báo macOS.
