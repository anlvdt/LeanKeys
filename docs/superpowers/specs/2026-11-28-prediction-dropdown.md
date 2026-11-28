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

## Dòng cụm từ (đo trên bench, 2026-11-28)

Ở kiểu Google, mỗi dòng nên là cả cụm. Nhưng với engine 1.14, chỉ khoảng 2 % số dòng có từ 2 chữ trở lên. Tôi đã thử nối mỗi từ với cụm đi sau nó (`PredictionEngine.PhraseExtension`, chạy `testPhraseRowsAccuracy` trên phần câu chat dùng để thử):

| Cách nối | Dòng 1 là cụm | Dòng 1 đúng chữ đầu | Đúng trọn cả cụm (trong số đúng chữ đầu) | Phím tiết kiệm (Tab chỉ khi đúng trọn) |
|---|---|---|---|---|
| Không nối (1.14) | 182 lần | 20 % | 16 % | 23,3 % |
| Nối bằng bảng cụm có sẵn, khớp ≥ 2 từ | 852 lần | 39 % | **1,8 %** | 22,0 % |
| Chỉ nối bằng cụm người dùng đã gõ từ 2 lần trở lên | 182 lần | 20 % | 16 % | 23,3 % |

- Nối bằng bảng có sẵn thì gần như luôn sai phần đuôi. Bấm nhận một dòng như vậy là phải xoá lại, nên **không bật**.
- App chỉ nối bằng cụm người dùng đã gõ từ 2 lần trở lên (`personalExtensionOnly`, khớp ít nhất 2 từ), giống Google dựa vào lịch sử gõ. Câu trong bench không lặp lại nên số đo không đổi. Khi dùng thật, những câu hay gõ lại (chào hỏi, chữ ký, câu trả lời quen) sẽ hiện thành cả cụm.
- Cần bật "Nhớ cụm từ bạn hay gõ" (phải đồng ý trước). Khi tắt học, dữ liệu đã học không hiện ra (có test).

## Enter

Gõ Nhanh xử lý Enter ở đầu `keyboardCallback`, trước khối 4A+, và ẩn danh sách ngay tại đó. Vì vậy Enter nhận dòng được viết trong nhánh Enter ấy (`LEANKEYS-HOOK-BEGIN/END`). Mọi phím không phải ↓ ↑ Tab Enter Esc đều xoá dòng đang chọn trước khi xử lý gì khác (`PredictionController.clearSelection`). Nhờ vậy ↓ → ⌫ → Enter không nhận một dòng đã cũ.
