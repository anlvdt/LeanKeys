# Gợi ý gõ tắt (4B): vì sao gợi ý kém, và thiết kế sửa

Ngày 2026-11-24. **Người dùng đã duyệt bậc 1–4 và đổi R17 thành ≥ 3 chữ; bậc 5 để đợt sau.** Bản này bổ sung cho spec chính, mục 11.1.

## 1. Cách đo

Dữ liệu mẫu tự tạo, không dùng dữ liệu học thật trên máy. Bộ mẫu giả lập 30 ngày gõ trong Slack:
- mỗi ngày một câu cảm ơn, có 4 biến thể;
- 9 câu chat ngắn, mỗi câu gõ cách ngày;
- vài câu công việc, chữ ký, một email và một số điện thoại.

Chạy qua `PhraseLearner` (ngưỡng 3 lần, 30 ngày, tối thiểu 8 ký tự) và `Abbreviation.suggest` thật, có engine Vikey.

Kết quả hiện tại: 18 gợi ý, xếp theo số lần gặp.

| Lần | Từ tắt | Nội dung |
|---|---|---|
| 15 | `xgv` | anh xem giúp em với |
| 15 | `dva` | dạ vâng ạ |
| 15 | `eco2` | em cảm ơn |
| 15 | `oen` | ok em nhé |
| 15 | `dektlrbas` | để em kiểm tra lại rồi báo anh sau |
| 12 | `eml` | an.nguyen@congty.vn |
| 8 | `decoacdqta` | Dạ em cảm ơn anh chị đã quan tâm ạ |
| 8 | `ecoacdqt` | Em cảm ơn anh chị đã quan tâm |
| 7 | `coacdqtn` | Cảm ơn anh chị đã quan tâm nhé |
| 7 | `decoacdqt` | dạ em cảm ơn anh chị đã quan tâm |
| 6 | `cl` | Email của em là an.nguyen@congty.vn |
| 3 | `sdt` | 0912 345 678 |
| 3 | `egabctna` | Em gửi anh báo cáo tuần này ạ |
| 3 | `mtmxlhpktqs` | Mọi thắc mắc xin liên hệ phòng kế toán qua số 0912 345 678 |
| 3 | `ttnva` | Trân trọng, Nguyễn Văn An |

Tóm tắt:
- 6/18 là câu chat ngắn. Mỗi lần dùng chỉ tiết kiệm vài phím, mà lại đứng đầu danh sách.
- 4/18 là biến thể của cùng một câu.
- 9/16 từ tắt của cụm từ khó nhớ: dài từ 6 chữ trở lên, có số, hoặc bị chặn (`cl`). Nếu tính cả `xgv` (dùng chữ không đứng đầu từ) thì là 10/16.
- Nhận dạng địa chỉ sai 2/4 câu thử.

## 2. Nguyên nhân

**N1. Chỉ đếm nguyên câu, và câu phải trùng y hệt.**
- `PhraseLearner.observe` đếm cả cụm mà `TextMirror` đưa ra: một dòng, hoặc một câu kết thúc bằng `. ! ?`. Có thêm phần nhận dạng SĐT, MST, email, địa chỉ.
- Câu thật hay khác nhau một chút: "Dạ…", "…ạ", "…nhé", chữ hoa đầu câu. Vì vậy phần cốt lõi "cảm ơn anh chị đã quan tâm" gặp 30 lần nhưng không bao giờ được đếm thành một mục. Thay vào đó có 4 mục, mỗi mục 7–8 lần.

**N2. Câu chat ngắn chiếm chỗ.**
- Điều kiện hiện tại là ≥ 8 ký tự và ≥ 2 từ. "ok em nhé" và "dạ vâng ạ" đều qua được. Đây là những câu lặp nguyên văn nhiều nhất.
- Đây cũng là lời chê chính với tính năng Suggested Snippets của TextExpander: gợi ý "too commonplace and short" (Macworld, 2015).

**N3. Xếp hạng chỉ theo số lần gặp.**
- Không tính số phím tiết kiệm được.
- "dạ vâng ạ" (15 lần, khoảng 5 phím mỗi lần) đứng trên "Mọi thắc mắc xin liên hệ phòng kế toán qua số 0912 345 678" (3 lần, khoảng 50 phím mỗi lần).

**N4. Cách đặt từ tắt.** Hàm nằm ở `Abbreviation.swift`, ngoài danh sách file được giao.
- Lấy chữ đầu của mọi từ, không giới hạn độ dài, nên có `dektlrbas` và `mtmxlhpktqs`.
- Từ tắt phải gõ ra đúng nó trong Telex (R15). Khi chữ đầu chứa phím dấu, ví dụ `axgev` có "ax" thành "ã", hàm lùi về:
  - bỏ nguyên âm: `xgv`;
  - hoặc lấy "hai phụ âm đầu" của cả câu: `cl`. `cl` là teencode tục.
- Khi chữ đầu là từ có thật (`eco`), hàm thêm số: `eco2`, dù chưa có `eco` nào trong bảng.
- Kiểm tra "từ có thật" chỉ dùng từ điển của Vikey, nên không biết teencode mà người dùng tự gõ hằng ngày: `ntn`, `cl`, `vl`… Nếu đặt một từ như vậy làm từ tắt, nó sẽ tự bung ra mỗi lần người dùng gõ từ đó.

**N5. Nhận dạng địa chỉ sai.**
- "số" và "xã" là từ thường, nên các câu sau bị coi là địa chỉ:
  - "bảo hiểm **xã** hội **số** tiền…";
  - "**Số** lượng đơn hàng ở **quận** 1…".
- Phần địa chỉ chạy tới hết câu, nên "…quận 1 nhé" bị lấy cả chữ "nhé".

**N6. Gợi ý trùng nhau.** "Email của em là an.nguyen@congty.vn" được gợi ý cùng lúc với chính email đó.

**N7. Gặp nhiều lần trong một ngày.** Một câu gõ lại 3 lần trong một buổi là đủ ngưỡng.

## 3. Các công cụ khác làm thế nào

- **TextExpander** (Suggested Snippets):
  - theo dõi cụm gõ lặp lại;
  - không lưu chữ gốc mà lưu một "abstracted sequence";
  - gợi ý *không kèm* từ tắt, người dùng tự đặt;
  - bị chê là gợi ý quá ngắn và quá thông thường.

  Nguồn: [Macworld](https://www.macworld.com/article/225639/textexpander-5-review-typing-shortcut-utility-makes-you-more-productive-by-learning-your-habits.html), [TextExpander help](https://textexpander.com/learn/using/snippets/create/suggested-snippets).
- **Cách đặt từ tắt** (TextExpander và giới dùng lâu năm):
  - tránh từ có thật;
  - từ tắt không dài hơn mức cần thiết, và không quá trừu tượng;
  - dùng tiền tố như `;` hoặc `zz`.

  Nguồn: [TextExpander prefixes](https://textexpander.com/blog/the-abbreviation-prefixes-textexpander-experts-use), [Dr. Drang](https://leancrew.com/all-this/2010/03/textexpander-abbreviation-design/).

  Tiền tố `;` không dùng được ở LeanKeys: `;` là dấu ngắt từ trong `TextMirror` và trong cách Gõ Nhanh khớp gõ tắt.
- **Cách người dùng tự viết tắt**: bỏ nguyên âm không đứng đầu và phụ âm đôi, giảm khoảng 26% ký tự. Chữ đầu của từ là phần giữ lại chắc nhất ([Shieber & Nelken 2007](https://www.cambridge.org/core/journals/natural-language-engineering/article/abbreviated-text-input-using-language-modeling/E6F7AFD0D25AF289F829EA14EDFC63C5); [Adhikary et al., ACL 2021](https://aclanthology.org/2021.acl-long.514)).
- **Bộ gõ Việt**:
  - Unikey và OpenKey chỉ có bảng macro người dùng tự soạn, không tự gợi ý;
  - Laban Key có gợi ý từ và tự sửa, nhưng không có tài liệu về gợi ý gõ tắt.

  LeanKeys là bộ đầu tiên tự đề xuất, nên chuẩn đúng nhất là bài học từ TextExpander.

## 4. Thiết kế đề xuất, theo bậc

Hai engine đều giữ chữ hoa theo từ tắt: Gõ Nhanh dùng `CaseMode::MatchCase`, Vikey dùng `ShortcutExpander`. Gõ "Abc" thì bung thành câu viết hoa chữ đầu.

**Bậc 1. Xếp hạng và lọc theo số phím tiết kiệm** (rẻ, ít rủi ro; sửa N2, N3, N7).
- Điểm = số lần × (phím Telex để gõ câu − phím của từ tắt − 1).
  - Phím Telex được tính thật: "ầ" là 3 phím.
- Câu chỉ được hiện khi tiết kiệm ≥ 10 phím mỗi lần và gặp trong ≥ 2 ngày khác nhau. **(Người dùng yêu cầu loại ba câu chat còn lọt, nên ngưỡng nâng lên 15 phím, 2026-11-24.)**
- SĐT, MST, email và địa chỉ giữ ngưỡng cũ.
- Danh sách xếp theo điểm.

**Bậc 2. Gộp gợi ý trùng** (sửa N6, một phần N1).
- Lấy gợi ý điểm cao nhất trước.
- Ẩn các gợi ý khác chứa nó hoặc nằm trong nó.
- Ẩn chứ không bỏ qua: mục bị ẩn vẫn được đếm và có thể quay lại.

**Bậc 3. Đặt từ tắt dễ nhớ** (sửa N4; phải sửa `Abbreviation.swift`).
- Dài 3–5 chữ: lấy chữ đầu của các từ đầu tiên. Ví dụ "để em kiểm tra lại rồi báo anh sau" → `dektl`.
- Khi chữ đầu vướng phím dấu Telex, thử theo thứ tự:
  1. bỏ các từ đệm (dạ, ạ, nhé, à, ừ, thì, là, mà…);
  2. đổi điểm bắt đầu hoặc bỏ bớt chữ đầu;
  3. thêm chữ thứ hai của từ đầu.

  Không bao giờ dùng chữ không phải chữ đầu từ, như `cl`.
- Có danh sách chặn teencode và từ tục (`cl`, `vl`, `ntn`, `ko`, `dc`, `ok`…) trong một file tài nguyên.
- Cụm từ cần ít nhất 3 chữ. **Điều này thay ruling R17** (hiện là ≥ 2).
- Chỉ thêm số khi tên gốc đã có trong Bảng gõ tắt.
- Nội dung lưu vào gõ tắt bỏ chữ hoa đầu câu, trừ khi từ thứ hai cũng viết hoa (như tên). Người dùng gõ `Coacd` ở đầu câu thì vẫn ra chữ hoa.

**Bậc 4. Sửa nhận dạng địa chỉ** (sửa N5).
- "số" chỉ tính khi đứng ngay trước một con số.
- "xã" theo sau là "hội" thì không tính.
- Phải có ít nhất một từ hành chính thật: phường, quận, huyện, tỉnh, TP, thị xã, xã, đường, phố.
- Địa chỉ kết thúc ở cuối tên đứng sau từ hành chính cuối cùng:
  - tên là con số, hoặc các từ cho đến dấu phẩy hoặc từ đệm cuối câu (nhé, nha, ạ, giúp…);
  - không dựa vào chữ hoa, vì người ta hay gõ "quận ba đình".

**Bậc 5. Đếm cụm con** (giá trị lớn nhất, rủi ro lớn nhất; sửa hẳn N1). Tách thành bước riêng, đo trước rồi mới làm.
- Ngoài nguyên câu, đếm cả các đoạn 3–8 từ liên tiếp. Mỗi đoạn chỉ lưu dưới dạng HMAC với khoá riêng `sub:`.
  - Khoá `phrase:` của nguyên câu giữ nguyên, để mục đã bỏ qua và số đếm cũ không mất.
- Một đoạn không được cắt ngang SĐT, email hay MST, và phải qua `looksLikeSecret` và `containsSensitiveNumber`.
- Bậc 2 chọn đoạn cốt lõi "cảm ơn anh chị đã quan tâm" thay cho 4 biến thể.
- Rủi ro:
  - File tăng mạnh: một câu 20 từ sinh khoảng 90 mục.
  - Hiện file được ghi lại sau mỗi câu, nên cần giới hạn số mục, có cách bỏ bớt, và ghi theo lô.
  - Giới hạn số mục làm rơi các cụm lặp chậm. Phải đo tỉ lệ rơi bằng bench, khoảng 200 câu/ngày trong 30 ngày, trước khi chốt.
  - Màn đồng ý và spec 11.1 phải sửa câu chữ: sẽ có thêm đoạn chữ thật được giữ khi đạt ngưỡng.

**Đo.** Bộ mẫu trên được đưa thành bench, có kèm test. Bench in ra các số sau, đo trước và sau mỗi bậc:
- số gợi ý;
- số câu chat ngắn;
- số biến thể trùng;
- số từ tắt khó nhớ;
- số địa chỉ sai.

## 5. Đã làm (bậc 1–4) và kết quả

Code:
- `SuggestionRanking` (mới): số phím Telex, lọc, xếp hạng, gộp trùng, bỏ chữ hoa đầu câu. Model gọi nó trong `publishReady`.
- `Abbreviation.phraseNames`: cách đặt tên mới.
- `TriggerBlocklist.txt`: danh sách chặn.
- `PhraseDetector`: nhận dạng địa chỉ.
- `Candidate.days`: số ngày đã gặp.

Khoá HMAC `phrase:` không đổi, nên với câu, mục đã bỏ qua và số đếm cũ vẫn còn.

Ngoại lệ là địa chỉ:
- Khoá `address:` tính từ đoạn địa chỉ, mà đoạn này giờ dừng sớm hơn.
- Địa chỉ nào trước đây kéo theo "nhé", "giúp em"… thì giờ có khoá mới: số đếm bắt đầu lại, và nếu đã bị bỏ qua thì có thể được đề xuất lại một lần.
- Không chuyển được, vì khoá cũ không có chữ thật đi kèm.

**Bỏ qua và mục bị ẩn.**
- Việc ẩn chỉ xét giữa các mục đang đạt ngưỡng. Mục đã Bỏ qua chỉ còn mã HMAC, không còn chữ, nên không ẩn được mục nào.
- Vì vậy, bỏ qua `an.nguyen@congty.vn` thì câu "Email của em là an.nguyen@congty.vn" đang bị ẩn có thể hiện ra ngay sau đó. Bỏ qua một biến thể câu cảm ơn cũng vậy.
- Đúng với thiết kế đã duyệt (ẩn chứ không bỏ qua), nhưng người dùng nên biết trước.

Khác thiết kế ban đầu ở hai điểm, rút ra từ bench:
- Khi hai mục chồng nhau, SĐT, MST, email và địa chỉ được ưu tiên hơn câu chứa nó, dù câu có điểm cao hơn. Nếu không, "Email của em là an.nguyen@congty.vn" sẽ che mất chính email đó.
- Bỏ từ đệm trước khi lấy chữ đầu: "Dạ em cảm ơn anh chị…" thành `ecoac` thay vì `decoa`.

Bench `SuggestionBenchTests`, cùng bộ mẫu, trước → sau:

| | Trước | Sau |
|---|---|---|
| Số gợi ý | 18 | 9 |
| Câu chat ngắn ("ok em nhé", "dạ vâng ạ", "em cảm ơn", "đúng rồi anh", "haha đúng rồi", "để em check lại") | 6 | 0 |
| Biến thể câu cảm ơn | 4 | 2 (còn 2 vì không câu nào chứa câu kia; cần bậc 5) |
| Từ tắt của câu khó nhớ (≥ 6 chữ, có số, hoặc bị chặn; tiêu chí của bench) | 9/16 | 0/6 |
| Câu thử bị nhận nhầm là địa chỉ | 2/4 | 0 |

Kết quả sau khi sửa:

| Lần | Từ tắt | Nội dung |
|---|---|---|
| 15 | `dektl` | để em kiểm tra lại rồi báo anh sau |
| 7 | `dchi` | số 12 đường Lê Lợi phường Bến Nghé quận 1 |
| 8 | `ecoac` | dạ em cảm ơn anh chị đã quan tâm ạ |
| 15 | `xgev` | anh xem giúp em với |
| 7 | `coacd` | cảm ơn anh chị đã quan tâm nhé |
| 12 | `eml` | an.nguyen@congty.vn |
| 3 | `egabc` | em gửi anh báo cáo tuần này ạ |
| 3 | `ttnva` | trân trọng, Nguyễn Văn An |
| 3 | `sdt` | 0912 345 678 |

**Còn lại:**
- Ngưỡng đã nâng lên 15 phím (`minPhraseSaving`), nên "đúng rồi anh", "haha đúng rồi" và "để em check lại" (tiết kiệm 12, 13 và 14 phím mỗi lần) không còn được đề xuất.
- Bậc 5 (đếm cụm con) chưa làm.
- Câu mở đầu bằng một tên riêng rồi tới chữ thường ("Lan ơi…") cũng bị bỏ chữ hoa đầu, nên gõ giữa câu sẽ ra "lan ơi…".
