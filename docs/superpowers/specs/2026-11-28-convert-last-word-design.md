# LeanKeys — Phím "đổi từ vừa gõ" (⌃⌫) và tự học hai chiều

Viết ngày 2026-11-28. Đề xuất 2 của báo cáo "Gõ trộn Anh–Việt" ([doc](https://claude.ai/artifact/4D1i9HNfHdVLHXACM6S6cZ)). Spec chính: `2026-11-15-leankeys-design.md` (mục 12 là nền của bản này).

## 1. Vì sao

Vikey tự chọn Việt/Anh sai dưới 0,3% số từ (mixbench), nhưng khi sai thì người dùng gần như không có cách sửa nhanh:

- ⌫⌫ chỉ hoàn tác được **một lần Vikey tự sửa**. Đo `--undo-bad-fix` trên `chat_messages`: Vikey tự sửa 1.254 lần, không lần nào làm hỏng từ. **Mọi** từ sai trên văn bản sạch là từ Vikey **để nguyên** ở ngôn ngữ sai (`cos implement` định gõ "có", `bể` định gõ "beer", `lát`/last, `mĩ`/mix). ⌫⌫ không cứu được chúng.
- Phím Esc "trả về phím gốc" của Gõ Nhanh bị ẩn khi dùng Vikey (`SettingsLayout.showsGoNhanhOnlySettings`).
- Bằng chứng từ người dùng: Gõ Nhanh ghi rõ `mix/box/six` phải nhấn ESC; Vikey #49 xin từ điển riêng; các phần mềm đổi layout (langSwitcher, Punto Switcher) đều có "đổi từ cuối" cạnh tự động.

LeanKeys có sẵn bộ học từ ⌫⌫ (mục 12.2). Nối phím sửa tay vào bộ học biến mỗi lần sửa thành luật lâu dài: đây là chỗ LeanKeys hơn cả Gõ Nhanh (ESC, không học) và Vikey (⌫⌫ chỉ sau khi tự sửa, chỉ học chiều "giữ").

## 2. Mục tiêu, không làm, coi là thất bại

**Mục tiêu**
- G1. Bấm ⌃⌫ ngay sau một từ (đang gõ, hoặc vừa kết thúc bằng Space/dấu câu) thì từ đó đổi sang ngôn ngữ kia, giữ nguyên phần sau nó (Space, dấu câu), con trỏ ở đúng chỗ cũ.
- G2. LeanKeys nhớ lần đổi đó; lần sau gặp đúng từ ấy (cùng từ đứng trước: ngay; không ngữ cảnh: từ lần thứ 2) thì tự ra đúng ngôn ngữ.
- G3. Đổi ý được: bấm ⌃⌫ lần nữa ngay sau đó trả từ về như cũ; ⌃⌫ ngay sau một lần LeanKeys tự đổi theo luật là "đổi ý" (huỷ và chặn luật, như hoàn tác ngược chiều ở 12.2).
- G4. Một danh sách "Từ đã học" trong Cài đặt, xem và xoá được, có ghi chiều (giữ như gõ / đổi).
- G5. "Từ của tôi": dán sẵn một danh sách từ luôn giữ như gõ (tên sản phẩm, viết tắt), không cần sửa tay trước.

**Không làm**
- Không đổi từ ở xa con trỏ (chỉ từ cuối cùng trước con trỏ, trên cùng dòng, chưa có phím nào khác chen vào sau phím ngắt).
- Không đổi một cụm nhiều từ.
- Không áp dụng cho engine Gõ Nhanh (giữ nguyên hành vi "trả về phím gốc" của nó trên cùng ô phím).
- Không gợi ý, không hiện bảng chọn.

**Coi là thất bại dù chạy đúng**
- ⌃⌫ xoá mất chữ hoặc làm lệch dòng trên trình duyệt, Slack, ô địa chỉ.
- Bộ học ghi luật từ phím giả hay từ ô mật khẩu.
- ⌃⌫ nuốt phím khi không có gì để đổi (người dùng mất hành vi gốc của app).
- Luật "đổi" làm hỏng từ đúng ở chỗ khác (văn bản sạch trên mixbench phải không đổi).

## 3. Ràng buộc

- Không sửa `vendor/vikey`, `core/`. Mọi dòng sửa trong file gốc của Gõ Nhanh có `LEANKEYS-HOOK`, đăng ký `sync/hooks.txt`, qua `sync/check-divergence.sh v1.0.165`.
- Không hỏi AX trên luồng phím (12.3). Không học trong Secure Input, ô mật khẩu, app loại trừ (dùng đúng `includedProbe` hiện có).
- Một bản sửa duy nhất cho mỗi lần bấm (không nhấp nháy), gửi qua đường tiêm phím hiện có (`sendReplacement`), nên thừa hưởng các cách gửi theo app/ô (mục 21).
- Sao lưu `learn*.bin`/`undo-rules.bin` trước khi thử bằng phím giả (bộ nhớ dự án).

## 4. Cách làm đã chọn

### Bắt phím: dùng lại ô phím "trả về phím gốc" của Gõ Nhanh (người dùng chọn 1a)

| Cách | Đánh đổi |
|---|---|
| **1a. Dùng lại ô phím của Gõ Nhanh** (chọn) | Đã có ô chọn phím, bắt tổ hợp bổ trợ, cho Esc/Tab đi tiếp, bỏ qua ô đăng nhập. Chỉ đổi điều kiện hiện ô và chỗ chuyển phím trong `RustBridge.swift` (vài dòng hook). Một ô phím dùng chung cho hai engine. |
| 1b. Ô phím riêng của LeanKeys | Phải viết lại bộ chọn phím và bắt tổ hợp; hai bộ bắt phím song song; vẫn cần hook. |

### Lưu luật: thêm loại luật vào `UndoRuleBook` (người dùng chọn 2a)

| Cách | Đánh đổi |
|---|---|
| **2a. Một sổ luật, hai loại `keep`/`convert`** (chọn) | Dùng lại file mã hoá, LRU 5.000, danh sách và nút xoá trong Cài đặt. Một từ (theo ngữ cảnh) chỉ mang một loại; luật mới thay luật cũ. Phải nâng định dạng file (có phiên bản). |
| 2b. Sổ luật riêng | Thêm file, thêm danh sách, hai luật ngược nhau có thể cùng tồn tại. |

### Phạm vi học (người dùng chọn B)

Phím đổi **và** học cả hai chiều. Phần "chỉ phím đổi" (A) nằm trọn trong B, nên kế hoạch có thể làm A trước rồi thêm học.

### Phím mặc định (người dùng chọn): **⌃⌫** (Control + Delete)

Esc không hợp: khi dùng Vikey, Esc đi tiếp tới app, trong chat nó đóng ô hoặc xoá nội dung. ⌃⌫ gần với ⌫⌫ đã quen, và trên Mac gần như không app nào dùng.

## 5. Thiết kế

### 5.1 Hành vi của ⌃⌫ (engine Vikey)

"Từ đích" là:
- (a) từ đang gõ, nếu con trỏ ngay sau một chữ; hoặc
- (b) từ ngay trước các ký tự ngắt vừa gõ (Space, `,` `.` `;` `?` `!`, ngoặc/nháy đóng) nếu từ lúc kết thúc từ đó chỉ có các phím ngắt ấy, không có phím khác, bấm chuột, mũi tên hay chuyển app.

Không có từ đích (dòng trống, sau Return, sau mũi tên/bấm chuột, trong app/ô cho phím đi thẳng, trong terminal/trình soạn mã theo `CodeApps`): ⌃⌫ **đi thẳng tới app** như chưa có LeanKeys.

Có từ đích: LeanKeys nuốt ⌃⌫ và gửi một bản sửa: xoá từ đích (và các ký tự ngắt sau nó), gõ lại từ đã đổi, gõ lại đúng các ký tự ngắt ấy.

Đổi theo chiều nào:
- Từ đang hiện **dạng Telex đã biến đổi** (có dấu, đ, ơ…: "có", "bể", "mĩ") → **phím thô** đã gõ ("cos", "beer", "mix"). Ngôn ngữ sau đó: Anh.
- Từ đang hiện **chữ thô** ("cos" Vikey để nguyên, hay "test" Vikey vừa trả về từ "tét") → **dạng Telex** của chính các phím đó ("cos" → "có", "test" → "tét"). Ngôn ngữ sau đó: Việt. Phím thô mà Telex không biến đổi gì ("sdt", "ok") thì không có gì để đổi: ⌃⌫ đi thẳng.
- Phím thô lấy từ bản ghi phím của từ (shim đã có `model.wordKeys`); khi không biết (có ⌫ giữa từ, từ dán vào), dùng `telexKeys()` dựng lại từ chữ trên màn hình. Không dựng được thì ⌃⌫ đi thẳng.
- Sau khi đổi, engine được nạp lại từ đó ở ngôn ngữ mới (như `rebuildEngineWord`), nên gõ tiếp (dấu, Space) chạy đúng; Vikey tiếp tục tự quyết các từ sau.

Bấm ⌃⌫ lần nữa ngay sau đó (không phím nào chen vào): đổi ngược lại về như trước lần bấm đầu. Đây là "đổi ý", không ghi luật nào (lần bấm đầu cũng không được ghi: xem 5.3).

Viết hoa: giữ nguyên chữ hoa/thường theo từng vị trí như bản gõ ("Cos" ↔ "Có", "CORS" ↔ "CÓR" theo luật hoa của shim hiện có). Nếu từ đích vừa được LeanKeys tự viết hoa (17.1), ⌃⌫ đổi trên dạng đã viết hoa.

### 5.2 Nơi đặt code

- **Shim** (`leankeys/VikeyShim/lk_vikey.cpp`, `include/lk_vikey.h`):
  - `int lk_vikey_convert_last_word(double now, lk_edit* out, lk_fix* converted)`: tìm từ đích theo mô hình màn hình (`model.line`), tính bản sửa (xoá, gõ lại, gõ lại ký tự ngắt), nạp lại engine, đặt ngôn ngữ. Trả 0 khi không có từ đích (Swift cho phím đi thẳng). `converted` báo chữ trước/sau và từ đứng trước, như `lk_fix`.
  - Bộ lọc mới cho luật "đổi": `typedef int (*lk_convert_filter)(const lk_fix*)` (thêm trường phím thô `keys` vào `lk_fix`) gọi **ở phím ngắt khi Vikey không tự sửa** từ vừa kết thúc ("cos " giữ "cos"). Trả 1 thì shim đổi từ đó ngay trong bản sửa của phím ngắt (một bản sửa), như `vetoFix` làm cho chiều "giữ".
  - Sự kiện học: mở rộng `lk_undo` bằng trường `kind` (0 = hoàn tác ⌫⌫ như cũ, 1 = đổi bằng phím, 2 = đổi ý sau một lần đổi theo luật). Swift lấy qua `lk_vikey_take_undo` như hiện nay.
- **Swift** (`leankeys/LeanKeysKit`):
  - `Engine/EngineRouter.swift`: hàm `convertLastWord()` cho RustBridge gọi; chặn khi `CodeApps`, master switch tắt (`autoFix`), engine không phải Vikey; đồng bộ `TextMirror` và trạng thái viết hoa như các bản sửa khác.
  - `Engine/VikeyEngine.swift`: bọc hàm C mới; `takeUndo()` trả thêm `kind`.
  - `Learn/UndoRuleBook.swift`: `UndoRule` có thêm `kind: keep | convert`; `record(...)` nhận loại; `shouldKeep` chỉ xét luật `keep`; hàm mới `shouldConvert(word:previous:)` chỉ xét `convert`. Ngưỡng như 12.2 (có ngữ cảnh: 1 lần; không ngữ cảnh: 2 lần). Một khoá (ngữ cảnh, chữ) chỉ một loại: ghi loại ngược lại thì thay. File lưu có số phiên bản; file cũ (không có `kind`) đọc là `keep`.
  - `Learn/UndoLearning.swift`: đăng ký bộ lọc thứ hai (`convert`), ghi sự kiện theo `kind`, dùng chung `includedProbe` (không học trong Secure Input, ô mật khẩu, app loại trừ).
  - `UI/UndoLearningSection.swift`: danh sách đổi tên thành "Từ đã học", mỗi dòng ghi chiều ("giữ như gõ" / "đổi"), xoá từng dòng; nút "Thêm từ giữ nguyên…" mở ô dán nhiều từ (một từ mỗi dòng) → luật `keep` không ngữ cảnh, đánh dấu `pinned` (không bị LRU đẩy ra, đếm như đã đủ 2 lần).
- **Gõ Nhanh (hook)**:
  - `platforms/macos/RustBridge.swift`: điều kiện ô phím restore (`showsGoNhanhOnlySettings`, khoảng dòng 1559 và 1633) cho phép cả khi engine là Vikey; `triggerRestoreShortcut` gọi `EngineRouter.shared.convertLastWord()` khi engine là Vikey và gửi bằng `sendReplacement`; trả false (cho phím đi thẳng) khi không có từ đích.
  - Ô phím trong `MainSettingsView.swift` (khoảng dòng 1102): nhãn khi dùng Vikey là "Đổi từ vừa gõ Việt ⇄ Anh", dòng phụ "Bấm ngay sau một từ: cos → có, bể → beer. LeanKeys nhớ cho lần sau."; khi dùng Gõ Nhanh giữ nhãn gốc.
  - Mặc định: lần chạy đầu của bản này, nếu người dùng **chưa từng** lưu phím restore và chưa bật nó, đặt phím ⌃⌫ và bật. Người đã tự đặt phím giữ nguyên.
  - Dùng lại các tên hook có sẵn trong `sync/hooks.txt` (`engine-dispatch` cho `RustBridge.swift`, `settings-engine` cho `MainSettingsView.swift`), không thêm tên mới: `check-divergence` giới hạn tên hook tối đa 12 ký tự.

### 5.3 Học

- **Ghi luật khi ⌃⌫ được bấm** trên từ đích:
  - Từ đích vừa được **Vikey tự sửa** ở phím ngắt (shim còn giữ `lastFix`): ⌃⌫ tương đương ⌫⌫ hoàn tác → ghi luật `keep` cho chữ trước khi sửa (đúng như 12.2, kể cả quy tắc 12.2a).
  - Từ đích **không bị Vikey sửa**: ghi luật `convert` khoá theo **phím thô đã gõ** (viết thường, ví dụ `cos`, `last`), kèm từ đứng trước. Khoá theo phím chứ không theo chữ hiện: `last` và `lats` cùng hiện "lát", luật học từ `last` không được đụng tới `lats`. Khi shim không biết phím thô của từ (có ⌫ giữa từ, từ dán vào) thì không ghi luật.
- **Ghi lúc nào:** như 12.2a, sự kiện được giữ cho tới phím kế tiếp; nếu phím kế tiếp là ⌃⌫ (đổi ý) thì bỏ, không ghi. Phím khác, bấm chuột, chuyển app → ghi.
- **Áp dụng:** ở phím ngắt, Vikey không sửa từ vừa kết thúc → shim hỏi bộ lọc `convert` → có luật thì đổi luôn trong bản sửa của phím ngắt. Ngôn ngữ sau đó theo chiều đổi (như 5.1).
- **Đổi ý sau khi luật áp dụng:** ⌃⌫ ngay sau một lần tự đổi theo luật → trả về chữ gốc, ghi sự kiện `kind = 2` → bộ học bỏ mọi luật `convert` của chữ đó và chặn nó (cần thêm 2 lần đổi tay mới tạo lại), như hoàn tác ngược chiều ở 12.2. ⌫⌫ ngay sau một lần tự đổi theo luật cũng làm đúng như vậy.
- **"Từ của tôi"** là luật ghim, khoá theo phím thô (= chính các chữ người dùng dán, vì đó là chữ họ muốn thấy). Ở phím ngắt, một từ có phím thô trùng luật ghim luôn ra đúng các chữ đó: nếu Vikey định sửa thì chặn (như `keep`), nếu Vikey để nguyên một dạng Telex khác ("mĩ") thì đổi về chữ thô (như `convert` về phía Anh). Trong lúc gõ, trước phím ngắt, màn hình vẫn có thể hiện dạng Telex ("Ỏca"); lời hứa trong Cài đặt là "ra đúng khi gõ xong từ".

### 5.4 Cài đặt và bảo mật

- Ô phím ở trang Phím tắt (5.2), bật/tắt và đổi phím như hiện nay.
- Công tắc "Nhớ từ bạn giữ nguyên" (12.3) đổi nhãn thành "Nhớ từ bạn sửa" và bao cả luật `convert`. Tắt: phím ⌃⌫ vẫn đổi, nhưng không ghi và không áp dụng luật.
- Lưu trữ, mã hoá, giới hạn 5.000, không học trong Secure Input/ô mật khẩu/app loại trừ: như 12.3. Chữ có dạng bí mật không được ghi (`isSecretShaped`).

## 6. Đo và test

- **mixbench** (`tools/mixbench/lk.cpp`):
  - Cờ `--convert-wrong`: sau mỗi từ kết thúc mà đầu ra sai so với đích, người gõ bấm ⌃⌫ một lần (gọi `lk_vikey_convert_last_word`). Báo: số từ sai trước/sau, số lần ⌃⌫ đưa từ về đúng, số lần làm sai thêm. Chạy trên `mine.txt` và `chat_messages`, với cả `--chain --end return-fix`.
  - Cờ `--learn`: một bộ lọc giả bằng C++ (bản rút gọn của `UndoRuleBook`, cùng ngưỡng) ghi luật khi `--convert-wrong` bấm và áp dụng ở các câu sau, để đo số lần ⌃⌫ cần bấm giảm dần qua kho.
  - Tiêu chí: văn bản sạch không dùng cờ mới cho đầu ra giống hệt từng byte; `--convert-wrong` không làm từ nào đang đúng thành sai.
- **XCTest**:
  - Shim: các ví dụ 5.1 (đang gõ, sau Space, sau dấu câu, đổi ý, không có từ đích → 0, viết hoa); bộ lọc `convert` áp dụng trong một bản sửa; sự kiện `kind`.
  - `UndoRuleBook`: hai loại, thay loại, ngưỡng, đổi ý chặn, file cũ đọc thành `keep`, `pinned` không bị LRU.
  - `EngineRouter`: `convertLastWord` trả nil trong `CodeApps`, khi tắt master switch, khi không có từ đích.
- **Thử tay** (thêm vào `sync/manual-checklist.md`): TextEdit, Chrome (ô thường và thanh địa chỉ), Slack, Messenger web, Terminal (phải đi thẳng):
  - `cos ` ⌃⌫ → "có "; ⌃⌫ lần nữa → "cos ".
  - `beer ` → (Vikey ra "bể") ⌃⌫ → "beer ".
  - Gõ "toi thich cos " rồi ⌃⌫ → "có"; câu sau "toi thich cos " tự ra "có ".
  - Thanh địa chỉ Chrome không mất chữ gợi ý.

## 7. Để lại cho người làm

- Cách tìm từ đích trên `model.line` khi ký tự ngắt là ngoặc/nháy đóng, và giới hạn độ dài từ (theo `kFixWordMax`).
- Cách đọc/ghi phiên bản file luật (khoá JSON mới, giữ đọc được file cũ).
- Cách bọc C callback thứ hai trong Swift (mẫu `undoFixFilter`).
- Câu chữ cuối cùng trong Cài đặt (theo mục 14.3: một dòng phụ, đủ chữ trong tooltip).

## 8. Quyết định khi soát (người viết tự chốt, đọc lại để kiểm)

Một người đọc độc lập đã soát bản này. Các câu sau được chốt mà không cần hỏi lại:

1. **Khoá luật `convert` theo phím thô và chiều**, không theo chữ hiện (5.3), để `last`/`lats` không lẫn nhau. Luật mang chiều (dạng Telex → phím thô, hoặc phím thô → dạng Telex) và chỉ chạy khi từ ở phím ngắt đang hiện đúng dạng "từ" của luật; nếu không, luật chỉ khoá theo phím chạy sai chiều trên `cos/có`, `nos/nó`, `last/lát` (đo bằng mixbench). Shim không dựng lại engine để quyết định ở phím ngắt: hỏi bộ lọc trước, chỉ dựng dạng Telex khi đổi.
2. **"Từ của tôi" ra đúng chữ đã dán khi gõ xong từ**: vừa chặn Vikey sửa, vừa đổi dạng Telex Vikey để nguyên ("mĩ" → "mix") về chữ thô (5.3).
3. **Ô phím dùng chung hai engine.** Lần chạy đầu bản này, nếu người dùng chưa từng lưu phím restore và chưa bật nó, đặt ⌃⌫ và bật, cho cả hai engine. Khi dùng Gõ Nhanh, ⌃⌫ làm đúng việc gốc của Gõ Nhanh (trả về phím gốc), nên hành vi Gõ Nhanh không đổi, chỉ đổi phím mặc định. Đổi engine không đổi phím đã lưu. Nếu phím đã lưu là Esc mà engine là Vikey: Esc đổi từ khi có từ đích, không có thì đi thẳng tới app.
4. **Thứ tự với 12.2a.**
   - ⌃⌫ khi đang giữ một lần hoàn tác 12.2a (đã ⌫⌫ sau "test "): bỏ lần hoàn tác đang giữ, không ghi gì, rồi đổi từ đang hiện như 5.1.
   - ⌫⌫ hay ⌃⌫ ngay sau một lần LeanKeys tự đổi theo luật: là đổi ý (`kind = 2`), áp dụng ngay, không giữ chờ phím kế như 12.2a (12.2a chỉ cho lần Vikey tự sửa).
5. **Ngôn ngữ sau khi đổi** mang sang từ kế tiếp, như sau một lần Vikey tự sửa; Vikey vẫn tự chuyển ở các từ sau theo quy tắc của nó.
6. **"Không có phím nào chen vào"**: phím bổ trợ đơn lẻ (Shift, Caps Lock) không tính; phím có ⌘/⌃ (dán, ⌘Z…), mũi tên, bấm chuột, chuyển app đều đặt lại ngữ cảnh như hiện nay (`resetContext`), nên mất từ đích.
7. **Từ đích chỉ là dãy chữ cái** liền trước con trỏ (hoặc trước các ký tự ngắt). "don't" → từ đích là "t"; "file.txt" → "txt". Nếu đổi không ra chữ khác thì ⌃⌫ đi thẳng.
8. **Tắt "Nhớ từ bạn sửa"**: ngừng ghi và ngừng áp dụng cả hai loại luật; luật vẫn giữ, danh sách vẫn hiện; luật ghim cũng ngừng áp dụng.
9. **Nhập "Từ của tôi"**: một từ mỗi dòng; chỉ chữ cái ASCII, 2–38 chữ; bỏ dòng khác và báo số dòng bỏ; viết thường khi so khớp nhưng ra đúng hoa/thường đã dán; tối đa 500 từ ghim, không tính vào giới hạn 5.000 và không bị LRU; trùng khoá với luật đã học thì luật ghim thay luật đó.
10. Bộ lọc chưa đăng ký (nil) thì không đổi gì, như bộ lọc 12.2.
