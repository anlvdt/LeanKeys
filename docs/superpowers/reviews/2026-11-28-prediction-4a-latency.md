# Đánh giá 4A+: độ trễ và độ dễ chọn của gợi ý (2026-11-28, bản 1.14)

Người dùng phản ánh: "tốc độ gợi ý chậm hơn tốc độ gõ của tôi… và gợi ý đưa ra cũng rất khó chọn."

Cách đo: dùng `leankeys/Tests/LeanKeysKitTests/PredictionLatencyBenchTests.swift`. Test này bị bỏ qua nếu không đặt `LEANKEYS_PREDICT_BENCH=1`. Bản build là release (`swift test -c release -Xswiftc -enable-testing`).
- Văn bản chạy thử là `chat_messages.txt` của Vikey, gồm 1 868 câu chat bịa. Model cá nhân học 2/3 số câu, phần còn lại dùng để gõ lại.
- Đo AX trên TextEdit đang nhận phím. Phím được gửi bằng `postToPid`, đi thẳng vào TextEdit nên LeanKeys không thấy: `debug.log` ghi 0 phím trong lúc đo, dữ liệu học không bị bẩn.
- Không gõ phím tổng hợp qua LeanKeys và không thay app đang chạy.

## 1. Độ trễ từng chặng (ms)

| Chặng | Chạy ở đâu | mean | p95 | max |
|---|---|---|---|---|
| `engine.predict` sau dấu cách (có model cá nhân) | main | 0,03 | 0,06 | 0,26 |
| `engine.predict` giữa từ (có model cá nhân) | main | 0,07 | 0,14 | 0,32 |
| `CaretLocator` AX, TextEdit nhận phím mỗi 50 ms | hàng AX | 3,2 | 9,4 | 68 |
| như trên, mỗi 80 ms | hàng AX | 6,5 | 13,0 | 15,7 |
| như trên, mỗi 120 ms | hàng AX | 9,7 | 18,4 | 20,1 |
| AX khi app rảnh (Chrome) | hàng AX | 0,5 | 0,2 | 56 |
| `panel.show`, lần hiện đầu | main | 8,7 | 14,6 | 55 |
| `panel.show`, chữ thay đổi | main | 0,5 | 2,8 | 7,1 |
| + SwiftUI/CA commit và vẽ sau khi đổi chữ | main | **6,0** | **9,9** | 18,6 |
| `panel.show`, chữ không đổi | main | 0,5 | 2,6 | 7,5 |

Event tap chạy trên **main thread**: `KeyboardHookManager.start()` được gọi từ `MenuBar`, nguồn sự kiện gắn vào `CFRunLoopGetCurrent()`. Vì vậy `DispatchQueue.main.async` không đưa việc ra khỏi đường gõ phím. Mỗi lần thanh gợi ý đổi chữ, main thread mất khoảng 6–10 ms để vẽ. Nếu phím kế tiếp đến đúng lúc đó, nó phải chờ ngần ấy thời gian.

### Từ lúc bấm phím đến lúc thanh gợi ý cập nhật (mô phỏng từ các số đo trên)

Mô phỏng chạy lại đúng logic của `refreshNow`: cache AX 80 ms, `refreshToken` bỏ kết quả cũ, nhịp gõ lệch ±35 %. Không có số đo AX thật cho Chrome và Electron, nên dòng "app chậm ×4" là ước lượng.

| AX | ms/phím (≈WPM) | mean | p95 | phím bị bỏ kết quả |
|---|---|---|---|---|
| TextEdit (đo thật) | 50 (240) | 9,5 | 21,0 | 0,3 % |
| TextEdit | 80 (150) | 10,6 | 22,4 | 0,1 % |
| TextEdit | 120 (100) | 11,9 | 23,3 | 0 % |
| TextEdit | 200 (60) | 12,8 | 23,5 | 0 % |
| app chậm ×4 (ước lượng) | 50 (240) | 14,8 | 51,6 | 14,4 % |
| app chậm ×4 | 80 (150) | 19,7 | 63,3 | 4,9 % |
| app chậm ×4 | 120 (100) | 24,8 | 69,5 | 2,0 % |

**Kết luận:** về tính toán, thanh gợi ý cập nhật trong khoảng 10–25 ms (p95), tức chưa tới một phím, kể cả ở 240 WPM. Chỉ ở app có AX chậm, khi gõ trên 200 WPM, mới có khoảng 15 % số phím mà kết quả bị bỏ.

## 2. Vì sao vẫn thấy "chậm hơn tay" và "khó chọn"

Số đo dưới đây lấy từ việc gõ lại phần văn bản thử, 26 395 lần bấm phím:

| Chỉ số | Có model cá nhân | Chỉ có kho có sẵn |
|---|---|---|
| Danh sách đang hiện mà đổi ngay ở phím sau | 48,6 % | 44,1 % |
| Ô đầu (ô của Tab) đổi ở phím sau | 36,5 % | 36,0 % |
| Một danh sách đứng yên trung bình | **1,1 phím** | 1,0 phím |
| Danh sách đứng yên từ 3 phím trở lên | 2,1 % | 0 % |
| Số lần thanh ẩn/hiện mỗi từ | 1,9 | 1,7 |
| Đoán đúng từ kế tiếp sau dấu cách, ô đầu / trong 3 ô | 8,8 % / 14,2 % | 4,9 % / 8,1 % |
| Từ đúng lên ô đầu trước khi gõ xong từ | 57 % | 40 % |
| Số chữ tiết kiệm tối đa (Tab ngay khi từ đúng lên ô đầu) | 29 % | 16 % |

Nguyên nhân, xếp theo mức ảnh hưởng:

1. **Danh sách sống chưa tới một phím.** Ở 150 WPM, mỗi danh sách nằm trên màn hình khoảng 90 ms. Người ta cần khoảng 300–600 ms để đọc 3 ô, chọn và bấm (định luật Hick: càng nhiều ô càng lâu). Mắt chưa đọc xong thì chữ đã đổi. Đây là cái cảm giác "chậm hơn tay": máy không chậm, nhưng người không kịp dùng.
2. **Âm tiết tiếng Việt ngắn.** Một từ thường 2–4 chữ cái, nên gợi ý giữa từ chỉ có 1–2 phím để tồn tại. Tôi đã thử hai cách xếp lại danh sách:
   - giữ các ô còn khớp ở nguyên chỗ;
   - lọc danh sách sau dấu cách theo chữ đang gõ.

   Cả hai vẫn chỉ đứng yên 1,1–1,3 phím (`personal+sticky`, `personal+filter-*` trong bench). Xếp lại danh sách không chữa được nguyên nhân 1.
3. **Ẩn rồi hiện lại ở mỗi từ.** Sau dấu cách thanh hiện. Gõ chữ đầu thì thanh ẩn (`minPrefixLength = 2`), chữ thứ hai thì hiện lại với danh sách khác. Trung bình 1,9 lần mỗi từ, nên thanh nhấp nháy liên tục.
4. **Đoán từ kế tiếp còn yếu.** Ô đầu chỉ đúng 9 %, nên phần lớn những gì hiện ra là nhiễu. Ví dụ từ bench: `edge|ed` → "eddie · edward", `một|mộ` → "một · mộng", `một số|` → "tài · điện · 40". Ba ô nhiễu tốn thời gian đọc hơn một ô đúng.
5. **Phím chọn.**
   - Tab bị nuốt mỗi khi thanh hiện, nên lùi dòng và chuyển ô trong form bị hỏng.
   - ⌥1 làm cùng việc với Tab, còn ô của nó lại ghi "Tab".
   - ⌥2 và ⌥3 trên bàn phím US vốn gõ ra ™ và £.
   - Ô đầu đổi 36 % số phím, nên khi đưa tay tới Tab thì chữ dưới tay đã khác.
6. **Main thread.** Mỗi lần đổi chữ mất khoảng 6 ms, p95 10 ms, để vẽ SwiftUI trên đúng luồng xử lý phím. Chưa gây trễ thấy được, nhưng thanh càng đổi nhiều thì càng tốn.

## 3. Đối chiếu

- **macOS Sonoma (inline prediction):** chỉ hiện một gợi ý màu xám ngay trong chữ; bấm Space (hoặc Tab ở một số app) để nhận, gõ tiếp thì bỏ qua ([Apple](https://support.apple.com/guide/mac-help/mchlp2299), [Mimestream](https://mimestream.com/help/user-guide/inline-predictive-text)). Đó là **một** gợi ý, không phải ba ô. LeanKeys đã thử kiểu chữ chìm và người dùng thấy giật, nên không đề xuất lại.
- **Bàn phím điện thoại** (QuickType, Gboard, Laban Key dựa trên bàn phím của Google, theo [Thế Giới Di Động](https://www.thegioididong.com/game-app/laban-key-go-tieng-viet-220631)): thanh 3 ô nằm **cố định** phía trên bàn phím, không chạy theo con trỏ. Người gõ điện thoại thường chỉ khoảng 30–40 WPM, tức 300–400 ms mỗi phím, nên đủ thời gian liếc thanh. Ở tốc độ gõ máy tính thì không còn khoảng thời gian đó. (Phần nhịp gõ trên điện thoại là hiểu biết chung, chưa có nguồn dẫn.)
- Không tìm được tài liệu chính thức mô tả cách Laban Key chọn gợi ý ([kết quả tìm kiếm](https://mytour.vn/en/blog/bai-viet/how-to-disable-prediction-feature-in-laban-key.html) chỉ nói về việc tắt nó).

## 4. Đề xuất, xếp theo mức ảnh hưởng (chưa làm, chờ người dùng chọn)

1. **Chỉ hiện khi có ích, không chạy theo từng phím** (chữa nguyên nhân 1–3). Hai cách:
   - **(a) Hiện khi tay dừng.** Thanh vẫn là popup như hiện giờ. Nó chỉ hiện khi khoảng 250 ms không có phím mới, hoặc ngay sau dấu cách nếu có gợi ý chắc chắn. Trong lúc gõ liền thì không hiện gì, nên không nhấp nháy và không tốn main thread. Lưu ý: bản bị revert (`c41017e`/`bb43241`) chờ 140–220 ms **và** dùng chữ chìm. Chưa rõ người dùng thấy lag vì phải chờ hay vì chữ chìm, nên cần hỏi.
   - **(b) Chỉ hiện ở đầu từ mới.** Thanh hiện sau dấu cách (từ hoặc cụm kế tiếp), rồi giữ nguyên trong lúc gõ chữ đầu của từ mới, chỉ bỏ những ô không còn khớp. Gợi ý giữa từ chỉ bật với từ dài từ 4 chữ cái hoặc từ tiếng Anh. Không đổi danh sách mỗi phím: số lần ẩn/hiện giảm từ 1,9 xuống 1,2 mỗi từ, đổi danh sách giảm từ 49 % xuống 32 %, đổi ô đầu giảm từ 37 % xuống 21 %. Đổi lại, số chữ tiết kiệm được giảm từ 29 % xuống 10–24 %.
2. **Ít mà chắc.** Chỉ hiện khi điểm của ô đầu vượt ngưỡng và cách xa ô thứ hai, và mặc định chỉ hiện 1 ô (ô 2–3 chỉ hiện khi cũng đủ chắc). Bỏ các từ từ điển ngoại lai khi đang gõ tiếng Việt ("eddie", "edward") và các con số ("40"). Một ô đúng đọc nhanh hơn ba ô nhiễu.
3. **Phím chọn.** Giữ Tab cho ô đầu, nhưng chỉ nuốt Tab khi thanh đã đứng yên ít nhất khoảng 150 ms, để Tab gõ nhanh vẫn lùi dòng hay chuyển ô như cũ. Ghi nhãn ô đúng với phím của nó. Cân nhắc dùng ⌃1–⌃3 thay ⌥, để không mất ™ và £.
4. **Bớt việc trên main thread.** Khi thanh ít đổi chữ thì tự khắc đỡ khoảng 6 ms mỗi lần. Có thể thay SwiftUI bằng `NSTextField` thuần, nếu số đo sau khi làm mục 1 vẫn cho thấy cần.
5. **AX cho app chậm.** Nếu kết quả AX về sau khi đã có phím mới thì vẫn lưu vị trí vào cache thay vì bỏ hẳn, và đặt hạn cache từ 150 ms trở lên. Chỉ cần khi gõ trên 200 WPM trong Chrome hoặc Electron. Việc này cần đo AX thật trên các app đó trước.

## Câu hỏi cho người dùng

- Chọn cách nào cho mục 1: (a) hiện khi tay dừng, hay (b) chỉ hiện ở đầu từ mới?
- Bản bị revert lag vì phải chờ mới hiện, hay vì kiểu chữ chìm?
