# Người dùng Việt cần gì ở bộ gõ: nghiên cứu 2026-11-17

Mục đích: chọn và xếp thứ tự các cải tiến tiếp theo của LeanKeys dựa trên phàn nàn thật của người dùng, không dựa trên đoán.

## Nguồn

- **Issue GitHub** (cả mở lẫn đóng, tải ngày 2026-11-17), tổng 1.225 issue:

  | Kho | Số issue |
  |---|---|
  | khaphanspace/gonhanh.org | 257 |
  | tonyminibot/Vikey | 65 |
  | tuyenvm/OpenKey | 288 |
  | lamquangminh/EVKey | 71 |
  | BambooEngine/ibus-bamboo | 520 |
  | vn-input/ibus-unikey | 24 |

  Riêng chuỗi #26 của Gõ Nhanh ("Auto-restore tiếng Anh - Feedback", 51 bình luận) được đọc hết.
- **UniKey**: tài liệu chính thức ([x-unikey-manual.pdf](https://www.unikey.org/support/x-unikey-manual.pdf)) và các bài hướng dẫn (fptshop, quantrimang).
- **Laban Key**: trang App Store ([id929865547](https://apps.apple.com/app/id929865547)), Chrome Web Store, bài giới thiệu (thegioididong, cellphones), thảo luận voz.vn ([1](https://voz.vn/p/43037138/), [2](https://voz.vn/p/43045589/)). Laban Key là bàn phím di động, mã nguồn đóng, nên chỉ học được từ tính năng và nhận xét, không từ mã.
- **Thử trực tiếp**: các trường hợp người dùng báo lỗi được gõ qua đúng đường gõ Vikey của LeanKeys (`tools/mixbench/lk`, Vikey v1.0.34 cùng shim LeanKeys).

## Người dùng phàn nàn gì nhiều nhất

Xếp theo trọng số (1 điểm cho mỗi issue, cộng số lượt phản ứng, cộng 1 điểm cho mỗi 5 bình luận). Việc phân loại dựa trên từ khoá nên chỉ dùng để xếp hạng thô.

| Nhóm | Ví dụ tiêu biểu | Có liên quan tới LeanKeys trên macOS? |
|---|---|---|
| Lặp, nhảy, mất chữ trên trình duyệt và app chat web | Messenger/Facebook trên Chrome gõ cực chậm (Gõ Nhanh #388); lặp chữ trên thanh địa chỉ Firefox/Opera (#21, 25 bình luận); ibus-bamboo #352, #245 | **Có**, nhiều nhất. LeanKeys dùng chung cách gửi phím của Gõ Nhanh. |
| Bộ gõ ngừng chạy sau khi máy ngủ dậy, khi khởi động, hoặc tự nhiên | Gõ Nhanh #405, OpenKey #87, #169, EVKey #30, #81 (macOS 26) | **Có.** Chưa có số đo riêng cho LeanKeys. |
| Từ không gõ được hoặc bị tự khôi phục sai | Chuỗi #26 của Gõ Nhanh: `đây→ddaay`, `tiếp`, `sắp xếp`, `thêm`, `chơ` (phương ngữ), `Đắk Lắk`; Gõ Nhanh #393 (`zạ`, `kưng`), #403 | **Một phần.** Xem phần thử trực tiếp bên dưới. |
| Tự chuyển Anh/Việt sai | Vikey #112 (chuyển sang English bằng tay rồi thì phải gõ thêm 1–2 từ mới tự về Việt), #86 và #119 (gõ đúp phím dấu làm cả từ chuyển sang Anh), #90 (`ref ref`) | **Có.** #86 và #119 chính là lỗi LeanKeys đã sửa ở 4C. |
| Terminal và IDE | Gõ Nhanh #364, #258 (Claude Code CLI), #408; Vikey #48, #24 | Đã xử lý ở 1.2: terminal để phím đi thẳng. |
| Gõ tắt | Vikey #85 (13 bình luận), #77: xin đưa gõ tắt trở lại; Gõ Nhanh #86: `Ko` không ra "Không" | Đã có (gõ tắt chạy với cả lõi Vikey, theo quy tắc chữ hoa). |
| Phím chuyển E/V tự kích hoạt | Gõ Nhanh #407 (Cmd+Tab), #399 (tổ hợp của Raycast) | Cần thử trong app. |
| Phím hoàn tác dấu là Esc | Gõ Nhanh #157, và bình luận trong #26: "Esc nhiều app tự đóng ô nhập" | LeanKeys đã có ⌫⌫ của Vikey. Phím khôi phục Esc chỉ có khi dùng lõi Gõ Nhanh. |
| Kéo dài chữ trong tin nhắn | Gõ Nhanh #211: "nhéee", "hảaa", "áaaa", "thường xuyên sử dụng trong tin nhắn với gia đình" | **Lỗi**, xem bên dưới. |
| Âm thanh khi chuyển E/V | Gõ Nhanh #40, EVKey #46, OpenKey | Chưa có. |
| Sửa dấu cho từ đã gõ xong | Gõ Nhanh #32: quên bỏ dấu thì phải xoá cả từ gõ lại | Cần thử trong app. |
| Ưu tiên bộ gõ tiếng Nhật, Trung, Hàn | Gõ Nhanh #19, OpenKey #310 (32 bình luận) | Ít người cần. |
| Emoji, clipboard | Vikey #84, #80, #120 | Ít người xin (trọng số 39). |
| Bảng mã cũ, chuyển mã | OpenKey, ibus-bamboo (trọng số 45) | Ít người xin. |
| Mật khẩu, bảo mật | Vikey #15 (nhật ký ghi mật khẩu gõ trong terminal của IDE), #3 | Đã xử lý ở 1.2. |

## Thử trực tiếp trên LeanKeys (lõi Vikey)

**Đúng**, kể cả những từ làm hỏng bộ gõ khác:

- `chafo toafn` → "chào toàn": đặt dấu ngay sau nguyên âm (Vikey #110).
- `vajan thajat thury chiuj` → "vận thật thuỷ chịu".
- `zaj zoif kuwng kawng` → "zạ zòi kưng kăng" (Gõ Nhanh #393).
- `ddaay ddaau tieeps sawsp xeeps theme lwu tuji moef ofo` → "đây đâu tiếp sắp xếp thêm lưu tụi moè ồ".
- `Buoon Ma Thuootj` → "Buôn Ma Thuột".
- Từ tiếng Anh giữ nguyên: `Orca cowork Nassr ref ref users offline massive coupon respect`, `Shopee TikTok Grab ChatGPT`.

**Sai**:

| Gõ | Ra | Mong đợi |
|---|---|---|
| `nheee`, `nhesee` | "nhee", "nhesee" | "nhéee" |
| `asaaa`, `hayaaa` | giữ nguyên chữ thô | "áaaa", "hảaa" |
| `ooiii`, `owiii` | giữ nguyên chữ thô | "ôiii", "ơiii" |
| `Ddawsk Lawsk` | "Đắ Lawsk" | "Đắk Lắk" |
| `Kroong` | giữ nguyên | "Krông" |

Kéo dài chữ là cách viết rất phổ biến khi nhắn tin. Phụ âm cuối `k` xuất hiện trong địa danh Tây Nguyên (Đắk Lắk, Đắk Nông, Krông Pắc, Kon Tum…). Gõ Nhanh đã thêm `k` cuối cho các địa danh này (theo chuỗi #26).

## Học được từ UniKey và Laban Key

**UniKey** (Windows, bộ gõ phổ biến nhất ở Việt Nam):
- **Bộ công cụ (Ctrl+Shift+F6):** chuyển mã, bỏ dấu, đổi chữ hoa/thường, cho file và cho clipboard. Ctrl+Shift+F9 chuyển mã ngay nội dung đang copy. Người dùng văn phòng dùng thường xuyên, như bỏ dấu để đặt tên file hay viết email không dấu, hoặc sửa văn bản dán từ nguồn TCVN3.
- **Gõ tắt:** gõ từ tắt rồi Space là bung ra.
- **Gõ tự do, kiểm tra chính tả, tự khôi phục phím với từ sai.** LeanKeys đã có các thứ tương đương qua hai lõi.

**Laban Key** (bàn phím di động phổ biến nhất ở Việt Nam):
- **Telex nâng cao:** cc→ch, gg→gi, kk→kh, nn→ng, qq→qu, pp→ph, tt→th, uu→ươ. Còn có gõ tắt phụ âm đầu (f→ph, j→gi, w→qu) và phụ âm cuối (g→ng, h→nh, k→ch). Mục đích là bớt phím bấm, và người quen Laban Key trên điện thoại sẽ tìm cách gõ này.
- **Gợi ý từ tiếp theo và tự sửa lỗi.** Đây là tính năng được khen nhiều nhất, nhưng trên voz.vn cũng có người chê phần sửa lỗi gõ phím. Nếu làm gợi ý, phải để người dùng tắt được và không bao giờ tự sửa từ đã gõ đúng.
- **Ghi chú và gõ tắt** được khen là tiện. Bảng nhớ tạm thì bị chê.

**MKey** (Maclife, [maclife.vn/product/mkey](https://maclife.vn/product/mkey), mã nguồn [maclifevn/mkey](https://github.com/maclifevn/mkey), GPL-3.0). Là bản fork của OpenKey, giao diện SwiftUI, phiên bản 1.6.5. Không xét phần clipboard, theo yêu cầu của người dùng. Những điểm đáng học:
- **Gửi phím từng bước.** Mỗi ký tự là một sự kiện phím riêng, thay vì cả chuỗi trong một sự kiện (`vSendKeyStepByStep` trong `Sources/Platform/MKEngineHook.mm`). Bật sẵn từ 1.6.3 để chạy được trên Chrome, Google Docs, Google Sheets, Zalo Web. Liên quan thẳng tới hạng mục 1, nên đã đưa vào giả thuyết sửa lỗi của webbench.
- **"Tắt MKey cho [tên app]" ngay trên menu**, và loại trừ app bằng kéo-thả. Trang của Maclife gọi đây là tính năng cộng đồng xin nhiều nhất. LeanKeys đã có tuỳ chỉnh theo app trong Cài đặt, nhưng chưa có lối tắt một chạm ngay trên ô nổi.
- **Secure Input:** báo tên app đang giữ Secure Input và tự gõ lại được khi app đó nhả ra. Cần kiểm tra LeanKeys đã báo tên app chưa.
- **Spotlight trên macOS 26 (tiến trình "Campo"):** sửa lỗi nhảy chữ. Cần kiểm tra cách LeanKeys nhận ra Spotlight trên macOS 26.
- **Phụ âm đầu nhanh và "gõ nhanh"**, giống Telex nâng cao của Laban Key (hạng mục 5).
- **Đồng bộ gõ tắt qua iCloud Drive** (thử nghiệm, tắt sẵn).
- Kho issue nhỏ (6 issue). Có một issue về hiệu năng: gõ tắt tra bằng `std::map` ở mỗi phím, và một bộ hẹn giờ iCloud chạy từ lúc mở app.

## Khuyến nghị: thứ tự mới

So với thứ tự đã đồng ý trước đó, có ba thay đổi:
- **Đo hiệu năng** trở thành "độ tin cậy và hiệu năng trên trình duyệt và chat web", vì đó là nhóm phàn nàn lớn nhất.
- **Thêm một hạng mục nhỏ** cho hai lỗi vừa tìm ra khi thử: kéo dài chữ và `k` cuối.
- **Bảng mã cũ** đổi thành "Bộ công cụ kiểu UniKey" (bỏ dấu, hoa/thường, chuyển mã clipboard), vì người dùng cần công cụ hơn là bảng mã.

1. **Độ tin cậy và hiệu năng trên trình duyệt và chat web**: Messenger, Facebook, Zalo web, thanh địa chỉ Chrome/Safari/Arc/Firefox, và sau khi máy ngủ dậy. Đo độ trễ và lỗi lặp/mất chữ trong app thật, rồi sửa.
2. **Kéo dài chữ và địa danh có `k` cuối** (mới).
3. **Giảm lỗi gõ còn lại**: chữ thừa rồi ⌫ (9,1%), sai giữa từ (7,4%).
4. **Viết hoa tên thương hiệu và tên riêng phổ biến.**
5. **Telex nâng cao kiểu Laban Key** (mới): tuỳ chọn, tắt sẵn.
6. **Nhớ Việt/Anh theo website.**
7. **Gợi ý từ khi gõ (4A)**: tắt được, không bao giờ tự sửa từ đã đúng.
8. **Bộ công cụ kiểu UniKey**: bỏ dấu, đổi hoa/thường, chuyển mã clipboard bằng phím tắt (thay cho "bảng mã cũ").
9. **Bảng chọn emoji**: ít người xin nhất, làm cuối.

Việc nhỏ, làm chung khi tiện: âm thanh khi chuyển E/V (tắt sẵn); "Tắt LeanKeys cho [app]" một chạm trên ô nổi (học từ MKey); báo tên app đang giữ Secure Input; thử lại Gõ Nhanh #407/#399 (phím chuyển tự kích hoạt) và #32 (sửa dấu cho từ đã gõ) trên LeanKeys.

Tệp issue đã tải: scratchpad của phiên, không đưa vào repo.
