# 4A+: danh sách gợi ý kiểu Google Search (2026-11-28)

Người dùng chọn kiểu này sau bản đánh giá `docs/superpowers/reviews/2026-11-28-prediction-4a-latency.md`. Bản chữ chìm đã bị loại: nó không đúng ý người dùng và làm chậm gõ phím.

## Giao diện

- Thanh ngang 3 ô được thay bằng **danh sách dọc** nằm dưới con trỏ, tối đa 3 dòng. Nếu sát mép dưới màn hình thì danh sách lật lên trên.
- Mỗi dòng là chữ sẽ chèn vào. Phần bạn đã gõ viết thường, phần máy gợi thêm in **đậm**. Sau dấu cách thì cả dòng in đậm.
- Dòng đang chọn có nền nổi bật. Dưới cùng có một dòng nhắc nhỏ: `↓ chọn · Tab nhận · Esc ẩn`.
- Vẽ bằng AppKit thuần (`NSTextField` trên `NSVisualEffectView`), dùng lại 3 dòng có sẵn. Danh sách chỉ đặt lại chữ và tính lại kích thước khi nội dung đổi.

## Phím (chỉ khi danh sách đang hiện, không có ⌘/⌃/⌥/⇧)

| Phím | Chưa chọn dòng nào | Đang chọn dòng *i* |
|---|---|---|
| ↓ | chọn dòng đầu, nuốt phím | xuống dòng kế (dừng ở dòng cuối), nuốt phím |
| ↑ | ẩn danh sách, phím chạy như thường | lên dòng trên; ở dòng đầu thì thôi chọn; nuốt phím |
| Tab | nhận dòng đầu **chỉ khi danh sách đã đứng yên ≥ 250 ms**, nếu không thì ẩn danh sách và Tab chạy như thường | nhận dòng *i* |
| Enter | ẩn danh sách, Enter chạy như thường | nhận dòng *i* |
| Esc | ẩn danh sách, nuốt phím | ẩn danh sách, nuốt phím |
| Gõ phím khác | danh sách cập nhật | thôi chọn, danh sách cập nhật |

- ⌥1–⌥3 vẫn chạy như trước để ai quen tay vẫn dùng được, nhưng không còn ghi trên danh sách.
- Bấm chuột vào một dòng thì nhận dòng đó.

## Không làm chậm gõ phím

- Không chờ tay dừng mới hiện. Logic chọn dòng là một struct thuần, mỗi phím chỉ tốn vài phép so sánh.
- Không dùng SwiftUI trong panel. Đo lại bằng `PredictionLatencyBenchTests.testPanelShowCost`: chi phí vẽ khi đổi chữ phải thấp hơn bản 1.14. Kết quả đo theo nhịp gõ: 6,0–6,4 ms (p95 10–11 ms), so với 21,8–22,6 ms (p95 31–33 ms) của thanh SwiftUI.
