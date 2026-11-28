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

## Nguồn thứ hai: macOS QuickType (2026-11-28)

Đo bằng `testOursVersusQuickType`, 600 vị trí; giữa hai lần chạy số đo lệch nhau khoảng ±4 điểm:

| Trạng thái | LeanKeys một mình: ô đầu / 3 ô | App (gộp với QuickType): ô đầu / 3 ô |
|---|---|---|
| Sau dấu cách (từ kế tiếp) | 7 % / 14 % | **10,8 % / 20,3 %** |
| Vừa gõ xong từ (đi trước một từ) | 5,5 % / 10 % | **9 % / 15 %** |
| Đã gõ 2 chữ | 53–57 % / 68 % | 53–57 % / 66 % |
| Đã gõ 3 chữ | 68–72 % / 75–81 % | 69–73 % / 76–81 % |

- QuickType trả kết quả bất đồng bộ (p50 4,8 ms, p95 8,5 ms). Danh sách chờ QuickType tối đa 25 ms rồi mới hiện lần đầu, chạy song song với việc tìm vị trí con trỏ qua AX. Nếu QuickType trả lời muộn hơn, danh sách cập nhật thêm một lần.
- Không hỏi QuickType khi đang gõ giữa URL hay mã, và không hỏi ở những app/ô đã bị loại trừ như ô mật khẩu. Chữ chỉ được gửi tới dịch vụ chính tả của macOS, chạy ngay trên máy này.
- Đã sửa một lỗi của `c092ca0`: những tiền tố 2 chữ cũng là một từ (`đi` trong `điện`) bị gợi ý đi trước chiếm chỗ, làm độ chính xác ô đầu giữa từ tụt xuống 18 %. Giờ gợi ý đi trước được xếp dưới các gợi ý hoàn thành từ. Chỉ khi từ đã gõ dài từ 3 chữ trở lên thì gợi ý đi trước mới được xếp lên trước.

## Luật hiển thị (`SuggestionGate`, theo `docs/superpowers/reviews/2026-11-28-prediction-research.md`)

1. Ở đầu từ mới, và với gợi ý dạng "từ vừa gõ + từ kế tiếp", chỉ hiện cụm bạn đã gõ ít nhất 2 lần. Từ do máy đoán chỉ đúng khoảng 10 % (QuickType cũng vậy), và điểm số không phân biệt được gợi ý đúng với gợi ý sai. Vì vậy ở chỗ này QuickType cũng không được hỏi.
2. Gợi ý hoàn thành từ chỉ hiện khi đã gõ ít nhất 2 chữ.
3. Dòng nào cũng phải tiết kiệm được ít nhất 2 phím Telex so với gõ tay. Bấm Tab tính là 1 phím.
4. Hiện tối đa 2 dòng.
5. Tab nhận gợi ý ngay sau 120 ms. Thời gian này ngắn hơn phản xạ của người, nên phím Tab bấm trước khi kịp nhìn thấy danh sách vẫn là Tab.
6. Danh sách chỉ vẽ một lần cho mỗi phím. Kết quả QuickType về muộn hơn 25 ms thì bỏ, không vẽ lại.
7. Danh sách nằm gần con trỏ, như trước.

Đo bằng `testGatedPolicyVersusUngated` (500 từ, có QuickType, kết quả lệch khoảng ±3 điểm giữa các lần chạy):

| | Danh sách hiện | Dòng 1 đúng khi hiện | Liếc phí công | Phím Telex tiết kiệm (Tab khi dòng 1 đúng) |
|---|---|---|---|---|
| Không lọc | 96 % | 28 % | 70 % | 30 % |
| **Có lọc: từ 2 chữ, tiết kiệm ≥ 2 phím (đang dùng)** | 38 % | 26 % | 28 % | 17 % |
| Từ 2 chữ, tiết kiệm ≥ 3 phím | 28 % | 20 % | 22 % | 13,5 % |
| Từ 3 chữ, tiết kiệm ≥ 3 phím | 20 % | 18 % | 17 % | 8 % |

Cách duy nhất để biết bản nào thật sự nhanh hơn cho riêng bạn là đo tốc độ gõ của chính bạn trong ba chế độ: luôn hiện, có lọc, và tắt hẳn.
