# webbench: đo LeanKeys trên trình duyệt thật, rồi sửa

Ngày 2026-11-17. Hạng mục 1 trong thứ tự cải tiến (docs/superpowers/research/2026-11-17-vietnamese-users.md).

## Vì sao

Người dùng bộ gõ tiếng Việt phàn nàn nhiều nhất về chữ bị lặp, nhảy hoặc mất, và về việc gõ chậm, trên trình duyệt và các app chat web (Messenger, Facebook, Discord, Telegram web, thanh địa chỉ). LeanKeys dùng chung bộ gửi phím của Gõ Nhanh cho cả hai lõi. Lõi Vikey thường viết lại cả từ khi tự chuyển Việt/Anh, nên số phím xoá lùi nhiều hơn khi dùng Gõ Nhanh thuần. Chưa ai đo xem điều đó làm hỏng chữ trong các trình soạn thảo web hay không. `tools/mixbench` chỉ mô phỏng lõi gõ, không đi qua macOS và trình duyệt.

Người dùng (chủ dự án) chọn cách A: một bộ đo tự động chạy trên trình duyệt thật, có số đo trước và sau, rồi sửa đúng chỗ hỏng.

## Mục tiêu

1. **Bộ đo lặp lại được** (`tools/webbench/`). Nó gõ các câu Việt/Anh thật vào nhiều loại ô trên Chrome, Safari và Firefox trong lúc LeanKeys đang chạy, rồi chấm:
   - **từ sai:** cách chấm giống `tools/mixbench/score.py`;
   - **lặp/mất ký tự:** số ký tự thừa và thiếu so với đích;
   - **độ trễ:** tính cho mỗi từ, lấy p50 và p95. Mốc bắt đầu là lúc công cụ gõ thử gửi phím cuối của từ (giờ hệ thống, mili giây). Mốc kết thúc là sự kiện `input` cuối cùng của ô sau phím đó, quy về cùng giờ hệ thống (`performance.timeOrigin + performance.now()`). Không dùng `keydown` của trang làm mốc: LeanKeys giữ phím lại rồi mới gửi bản sửa, nên trang không thấy phần thời gian LeanKeys tốn. *(Quyết định của người xây, sau builder check.)*
2. **Số đo nền** cho LeanKeys 1.2, ghi vào `tools/webbench/README.md` (giống cách mixbench ghi kết quả).
3. **Sửa** những chỗ hỏng mà số đo chỉ ra, mỗi bản sửa kèm số đo trước/sau.
4. **Số liệu từ bên trong LeanKeys** (phần B mà người dùng gộp vào A): thời gian LeanKeys xử lý một phím và thời gian gửi bản sửa, ghi vào nhật ký gỡ lỗi. Nhật ký vẫn không chứa chữ đã gõ (spec §18.2), chỉ số mili giây.

## Không làm

- Không đăng nhập trang thật (Messenger, Facebook, Zalo web). Thay vào đó dùng **chính các thư viện soạn thảo** mà các trang đó dùng, chạy trên một trang cục bộ.
- Không đo thanh địa chỉ thật của trình duyệt. Bộ đo không đọc lại được nó một cách tin cậy. Trang có một ô mô phỏng gợi ý tự hoàn thành kiểu thanh địa chỉ (phần đuôi được chọn sẵn); thanh địa chỉ thật vẫn để thử tay (checklist mục 1).
- Không đo app desktop (Zalo, Messenger, Telegram, Slack), không có trên máy. Có thể thêm sau, theo cùng cách.
- Không tự động hoá phần ngủ/thức của máy. Phần này đã có cơ chế bật lại bộ bắt phím (watchdog 2 giây, thông báo thức dậy); chỉ thêm một mục thử tay.

## Điều không được để xảy ra (anti-goal)

- **Công cụ gõ thử gõ vào app khác ngoài trang đo.** Trước mỗi câu, nó kiểm tra app đang ở trước là đúng trình duyệt đang đo, và tab đang mở là trang đo (tiêu đề cửa sổ có dấu hiệu riêng, ví dụ `webbench-<token ngẫu nhiên>`). Sai một trong hai thì dừng ngay, không gõ phím nào.
- **Chạy khi người dùng đang dùng máy.** Bộ đo chiếm bàn phím và màn hình trong lúc chạy. Nó in ước tính thời gian, chờ người dùng gõ `y` mới bắt đầu, và dừng khi người dùng bấm phím thật hay dời chuột (phát hiện được bằng sự kiện không mang dấu của công cụ).
- **Sửa lỗi mà làm hỏng chỗ khác.** Mọi bản sửa phải giữ nguyên kết quả của mixbench, capbench và bộ test hiện có, và giữ nguyên số đo trên các ô khác.

## Ràng buộc

- Mọi sửa trong file gốc của Gõ Nhanh phải có `LEANKEYS-HOOK` và qua `sync/check-divergence.sh v1.0.165`. Không sửa `core/`, `vendor/`.
- Công cụ gửi phím cần quyền Trợ năng cho tiến trình chạy nó (Terminal). Người dùng cấp một lần; bộ đo kiểm tra quyền trước và in hướng dẫn nếu thiếu.
- Phím do công cụ gửi phải **đi qua** bộ bắt phím của LeanKeys, như phím thật. Không gắn dấu `kEventMarker` của LeanKeys vào các phím này. Muốn nhận ra phím của công cụ thì dùng một giá trị `eventSourceUserData` riêng.
- Bố cục bàn phím US. Nếu bố cục hiện tại không phải US, bộ đo dừng.
- Các thư viện soạn thảo được tải từ CDN, ghim đúng phiên bản (esm.sh hoặc jsdelivr). Không đưa mã thư viện vào repo.

## Các cách đã cân nhắc

| Cách | Được | Mất |
|---|---|---|
| **A. Bộ đo tự động trên trình duyệt thật** (đã chọn) | Đo đúng thứ người dùng thấy: chữ cuối cùng trong ô. Lặp lại được trước và sau mỗi bản sửa. | Phải viết công cụ gửi phím và trang đo. Cần quyền Trợ năng. Chiếm máy trong lúc chạy. |
| B. Chỉ đo bên trong LeanKeys | Rẻ, không cần quyền thêm | Không biết chữ trên trang có đúng không. Đã gộp vào A thành mục tiêu 4. |
| C. Chỉ đọc mã, so với các bản sửa mới của Gõ Nhanh | Rẻ nhất | Không có số đo, không chứng minh được gì |

## Thiết kế

### Thành phần (`tools/webbench/`)

1. **`page/index.html` và JS của nó:** trang đo, phục vụ ở `http://127.0.0.1:<port>/`.
   - Các loại ô, mỗi ô chọn được bằng tham số URL (`?field=…`):
     - `input`: `<input type=text>`;
     - `textarea`;
     - `contenteditable`: `<div contenteditable>` trần;
     - `autocomplete`: ô mô phỏng thanh địa chỉ, tự điền phần đuôi đã chọn sẵn (như Chrome/Firefox gợi ý URL);
     - `lexical`: Lexical, trình soạn thảo của Messenger và Facebook;
     - `slate`: Slate (Discord);
     - `prosemirror`: ProseMirror (nền của nhiều trình soạn thảo, Tiptap);
     - `quill`: Quill.
   - Khi một ca bắt đầu, trang đặt con trỏ vào ô, ghi `keydown`, `beforeinput` và `input` kèm `performance.now()`. Khi ô yên lặng 800 ms sau phím cuối, trang gửi kết quả về máy chủ cục bộ: chữ cuối cùng và các mốc thời gian.
   - Tiêu đề trang chứa token của lần chạy để công cụ gõ thử kiểm tra (xem anti-goal).
2. **`server.py`:** `http.server` của Python, chỉ nghe trên `127.0.0.1`. Phục vụ trang, nhận kết quả, ghi `results/<thời điểm>.jsonl`.
3. **`typist.swift`:** công cụ dòng lệnh gửi phím.
   - Đọc chuỗi phím Telex (cùng định dạng `.tsv` của mixbench, có `` ` `` là ⌫).
   - Gửi `CGEvent` keyDown/keyUp ở `.cghidEventTap` với mã phím US.
   - Có các chế độ tốc độ: `human`, khoảng 8–12 phím/giây có dao động ngẫu nhiên; `fast`, 25 phím/giây; `burst`, không chờ.
   - Trước mỗi câu, kiểm tra app ở trước và tiêu đề cửa sổ (AX), rồi kiểm tra không có sự kiện bàn phím hay chuột thật nào chen vào.
4. **`run.py`:** điều phối.
   - Với mỗi trình duyệt, ô, lõi gõ và tốc độ: mở URL trên đúng trình duyệt (`open -a`), chờ trang sẵn sàng, gọi `typist`, chờ kết quả.
   - Đặt lõi gõ bằng `defaults write io.github.anlvdt.leankeys LeanKeys.engine …` rồi mở lại LeanKeys.
   - **Bản được đo:**
     - Số đo nền dùng bản 1.2 đã phát hành, đang cài ở `/Applications/LeanKeys.app`.
     - Bản đã sửa được build vào `dist/` (ký `LeanKeys Self-Signed`) và đo từ đường dẫn truyền vào. Quyền Trợ năng gắn với chứng chỉ chứ không với đường dẫn, nên chạy từ `dist/` không mất quyền.
     - Bộ đo không bao giờ ghi đè `/Applications`, và luôn thoát bản đang chạy trước khi mở bản kia, để không có hai LeanKeys cùng bắt phím. Chạy xong, nó mở lại bản ở `/Applications`. *(Quyết định của người xây.)*
   - **Mốc so sánh "không có LeanKeys":** thoát hẳn LeanKeys rồi gõ cùng chuỗi phím. Chữ ra là chữ thô, không có dấu, nên chỉ dùng để lấy độ trễ gốc của trình duyệt. *(Quyết định của người xây.)*
   - Kết thúc, trả lõi gõ và các cài đặt đã đổi về như cũ.
5. **`score.py`:** đọc `results/*.jsonl`. In bảng theo trình duyệt × ô × lõi × tốc độ: % từ sai, ký tự thừa/thiếu, p50/p95 độ trễ. Dùng lại cách chấm từ của mixbench.
6. **Kho câu:**
   - khoảng 40 câu, lấy từ `tools/mixbench/mine.tsv` (câu văn phòng/kỹ thuật trộn Việt/Anh) và `chat_messages` của Vikey (câu chat);
   - cộng một nhóm ca ⌫ lấy từ `typo.py` (`dbl`, `extra`);
   - cộng các ca vừa tìm ra trong nghiên cứu: kéo dài chữ, `k` cuối. Hai nhóm này dùng để đo hạng mục 2 sau này và được đánh dấu riêng, để không làm lẫn số đo nền.

### Số liệu bên trong LeanKeys (mục tiêu 4)

Khi nhật ký gỡ lỗi đang bật, LeanKeys ghi thêm thời gian xử lý mỗi phím (từ lúc vào bộ bắt phím tới lúc trả về) và thời gian gửi một bản sửa (số phím xoá lùi, độ dài chữ chèn, thời gian chờ). Phím đi thẳng không được ghi gì (spec §18.2). Khi tắt nhật ký thì không có chi phí gì: không đo giờ, không định dạng chuỗi.

`webbench/run.py` có cờ để bật nhật ký trong lúc chạy và gom các số này vào báo cáo.

### Vòng sửa

1. Chạy số đo nền trên LeanKeys 1.2 (lõi Vikey và lõi Gõ Nhanh, tốc độ human và fast, cả ba trình duyệt).
2. Với mỗi ô có lỗi, tìm nguyên nhân bằng nhật ký và bản ghi sự kiện của trang, rồi sửa. Hướng sửa có thể có, chỉ là giả thuyết cho tới khi số đo xác nhận:
   - chọn cách gửi phím theo loại ô trong trình duyệt: `emptyCharPrefix` cho thanh địa chỉ và ô có gợi ý, cách khác cho vùng soạn thảo (`AXTextArea` hay `AXWebArea` trong một trình soạn thảo web);
   - giảm số phím xoá lùi khi Vikey viết lại cả từ, chỉ gửi phần khác nhau;
   - chỉnh khoảng chờ theo loại ô.
   - gửi từng ký tự bằng một sự kiện phím riêng, thay vì cả chuỗi trong một sự kiện. Gõ Nhanh đã làm vậy cho Safari (`charByChar`); MKey bật sẵn cách này cho Chrome, Google Docs/Sheets, Zalo Web (`vSendKeyStepByStep`). Đây là giả thuyết hàng đầu cho các trình soạn thảo web.
3. Mỗi bản sửa: chạy lại webbench trên ô bị ảnh hưởng và trên toàn bộ ma trận, cộng `pre-push --all`, mixbench và capbench.

### Thành công là gì

- **Bộ đo:** chạy một lệnh, ra bảng số liệu; chạy lại cho cùng kết quả (chênh nhỏ ở phần độ trễ là bình thường).
- **Ở tốc độ `human`:** 0 ký tự lặp/mất trên mọi ô của Chrome và Safari, với cả hai lõi; tỉ lệ từ sai không cao hơn mixbench mô phỏng trên cùng câu.
- **Độ trễ:** ngưỡng p95 được đặt sau khi có số đo nền. Mặc định đề xuất là p95 không tệ hơn khi tắt LeanKeys quá 30 ms.
- **Các lỗi còn lại** ở tốc độ `fast` và `burst`, hay trên Firefox, được ghi rõ trong README nếu không sửa được.

### Thử tay thêm vào checklist

- Gõ trong khung chat Messenger hoặc Facebook thật, và thanh địa chỉ Chrome/Safari/Firefox, ở tốc độ bình thường: không lặp, không mất chữ.
- Cho máy ngủ 5 phút rồi mở lại: gõ được ngay ở phím đầu tiên.

## Phần để người xây dựng tự quyết

- Cổng của máy chủ, tên file, cấu trúc JSON kết quả.
- Phiên bản ghim của từng thư viện soạn thảo, và cách dựng mỗi trình soạn thảo ở mức tối thiểu.
- Cách mở lại LeanKeys sau khi đổi lõi (`osascript quit` rồi `open`, giống thủ tục cài bản 1.2).
- Cách chính xác để phát hiện người dùng chen vào.
- Số câu chính xác, miễn đủ để số đo ổn định qua hai lần chạy.
