# Ô nổi thanh menu: phiên bản, gọn đẹp, dễ dùng — thiết kế ngắn (2026-11-24)

## Mục đích
Người dùng mở ô nổi (bấm trái icon trên thanh menu) **chủ yếu để đổi Việt/Anh**. Họ muốn thấy số phiên bản, và muốn ô đẹp hơn, chuyên nghiệp hơn, dễ dùng hơn. Bố cục do Claude quyết; người dùng đã duyệt bản phác bên dưới và yêu cầu ô tự đóng khi bấm ra ngoài.

## Hiện trạng
`StatusPopoverView` (LeanKeysKit): Picker Việt/Anh không trải hết chiều ngang; không có tên app hay phiên bản; nút "Cài bản mới" không nói bản nào; hàng cuối là hai nút có khung; không có công tắc "Tự sửa khi gõ". `NSPopover.behavior = .transient`, nhưng app thanh menu không được kích hoạt nên bấm sang app khác đôi khi không đóng.

## Bố cục (rộng 300 pt)
```
[icon] LeanKeys  1.8                    ⚙︎
[      Tiếng Việt      |     English     ]   (to, trải hết chiều ngang)
Đổi nhanh: ⌃⇧ · Tự chuyển Việt/Anh: Bật       (dòng phụ, 11 pt; cảnh báo thay vào khi có)
──────────────────────────────────────────
Kiểu gõ                          Telex ▾
Tự sửa khi gõ                       [●]
Có bản mới 1.9                    [Cài]   (chỉ khi có bản mới / đang tải: như hàng cập nhật hiện nay)
Có 2 gợi ý gõ tắt                    ›   (chỉ khi có gợi ý)
──────────────────────────────────────────
Cài đặt…                           Thoát   (chữ nhẹ, không khung)
```
- Đầu ô: icon app 18 pt, "LeanKeys" đậm 13 pt, số phiên bản (CFBundleShortVersionString) mờ 11 pt; nút ⚙︎ (SF Symbol `gearshape`, không khung, có tooltip "Cài đặt") mở Cài đặt.
- Việt/Anh: segmented, `.controlSize(.large)`, trải hết chiều ngang. Giữ nguyên hành vi chọn.
- Dòng phụ: phím tắt đổi Việt/Anh (nếu người dùng có đặt) nối với dòng tự chuyển, cách bằng " · ". Khi có cảnh báo (bị bộ gõ khác chặn, bàn phím không Latin) thì cảnh báo hiện như hiện nay.
- Hàng cài đặt: chữ trái 13 pt, điều khiển phải; "Tự sửa khi gõ" là công tắc mini, đổi ngay `AppState.autoFix` (cùng đường với trang Chung).
- Hàng cập nhật: giữ các trạng thái hiện có; khi có bản mới và biết số bản, chữ là "Có bản mới X.Y". Không biết số bản thì "Có bản mới".
- Chân ô: "Cài đặt…" và "Thoát" là nút kiểu chữ (`.borderless`), 12 pt.
- Menu bấm phải: thêm dòng đầu "LeanKeys X.Y" (mờ, không bấm được) và một đường kẻ.

## Đóng ô
- Bấm chuột (trái/phải/giữa) bất kỳ đâu ngoài ô → đóng (theo dõi chuột toàn hệ thống khi ô đang mở, gỡ khi ô đóng).
- Esc → đóng.
- Bấm lại icon khi ô đang mở → đóng (như hiện nay, giữ khoảng chặn mở lại 0,3 s).

## Không làm
Đổi icon/màu thanh menu; đổi trang Cài đặt; thêm mục mới ngoài "Tự sửa khi gõ".

## Kiểm chứng
Test cho dữ liệu mới của ô (phiên bản, phím tắt, dòng phụ, chữ cập nhật có số bản, công tắc tự sửa gọi đúng hành động); ảnh chụp sáng/tối qua `LEANKEYS_SNAPSHOTS=1 swift test --filter UISnapshotTests` gửi người dùng xem trước khi merge. Sửa file gốc Gõ Nhanh → `LEANKEYS-HOOK` (tên hook có sẵn), `sync/check-divergence.sh v1.0.165` exit 0.
