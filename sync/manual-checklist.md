# Thử tay trước khi đăng bản

Cài bản trong DMG (kéo `LeanKeys.app` vào Applications, cấp quyền Trợ năng nếu được hỏi). Mục có hai ô làm hai lần: một lần với engine **Gõ Nhanh**, một lần với **Vikey** (menu bar → Cài đặt → Nâng cao → mở "Lõi gõ": **Chỉ dùng Gõ Nhanh** là Gõ Nhanh, **Tự động (khuyên dùng)** là Vikey, mặc định). Mục chỉ có ô Vikey (— ở cột Gõ Nhanh) làm một lần với Vikey. Kiểu gõ Telex.

Câu thử: `Tieengs Vieejt truowfng hojc` phải ra "Tiếng Việt trường học". Gõ thêm một từ tiếng Anh rồi Space, từ đó phải giữ nguyên: `push` với Gõ Nhanh, `more` với Vikey.

| # | Ở đâu | Thử gì | Gõ Nhanh | Vikey |
|---|-------|--------|:--------:|:-----:|
| 1 | Chrome | Gõ câu thử vào thanh địa chỉ (gợi ý tự hoàn thành không nuốt dấu), rồi vào một ô nhập trên trang web. | [ ] | [ ] |
| 2 | Spotlight | ⌘Space, gõ câu thử. Chữ không bị lặp hay mất dấu. | [ ] | [ ] |
| 3 | VS Code | Gõ câu thử trong một file và trong ô tìm kiếm (⌘F). | [ ] | [ ] |
| 4 | Terminal | Gõ câu thử sau dấu nhắc lệnh, xoá bằng Backspace giữa chừng rồi gõ tiếp. | [ ] | [ ] |
| 5 | Slack | Gõ câu thử trong ô soạn tin nhắn (chưa gửi). | [ ] | [ ] |
| 6 | Đổi engine khi đang gõ | Gõ dở một từ (`vieej`), đổi engine trong Cài đặt → Nâng cao → Lõi gõ, quay lại gõ tiếp. Ô nhập không hỏng, từ sau gõ đúng với engine mới. | [ ] | [ ] |
| 7 | Đổi app có nhớ ngôn ngữ | Bật "Nhớ Việt/Anh theo từng ứng dụng" (Cài đặt → Chung). Tắt tiếng Việt ở Terminal, bật ở Slack; chuyển qua lại vài lần, mỗi app giữ đúng trạng thái của nó. | [ ] | [ ] |
| 7b | Tuỳ chỉnh theo ứng dụng | Cài đặt → Nâng cao → Tuỳ chỉnh theo ứng dụng: thêm Notes, đặt "Tiếng Việt: Luôn tắt". Chuyển sang Notes: icon hiện E, gõ `vieejt ` ra nguyên chữ. Chuyển app khác: về lại như trước. Bỏ tuỳ chỉnh (nút ✕) sau khi thử. | [ ] | [ ] |
| 8 | Return/Enter sau từ Vikey khôi phục | Gõ `more` (Vikey giữ nguyên tiếng Anh) rồi Return ngay: tin nhắn được gửi trong một ô chat (Slack, kênh thử riêng) và một form trên trang web được gửi. Chữ trước đó không đổi. | — | [ ] |
| 9 | Dấu câu sau từ đã sửa | Gõ một từ Vikey sửa (`more`, `vieejt`) rồi `,`; làm lại với `.`. Dấu phẩy, dấu chấm hiện đúng một lần. | — | [ ] |
| 10 | Caps Lock | Bật Caps Lock, gõ câu thử: ra "TIẾNG VIỆT TRƯỜNG HỌC". Tắt Caps Lock, gõ tiếp bình thường. | [ ] | [ ] |
| 11 | Cập nhật | Bản Developer ID: có bản mới, để máy rảnh hơn 30 giây; app tự cập nhật, tự mở lại, gõ được ngay. Bản self-signed: cập nhật ngầm như Developer ID, không cần cấp quyền lại. Bản ad-hoc: menu hiện "Cài bản mới X và mở lại", bấm một lần là cập nhật; màn "LeanKeys vừa được cập nhật" hiện ra. Nếu LeanKeys đã tự reset mục Trợ năng: bật lại công tắc cạnh LeanKeys là gõ được. Nếu không: làm theo hướng dẫn trên màn (chọn LeanKeys, bấm −, rồi + thêm lại). | — | [ ] |
| 12 | Mở cùng máy | Khởi động lại máy (launch at login bật sẵn): LeanKeys tự chạy, gõ được ngay. | — | [ ] |
| 13 | Cài mới | Trên máy hoặc tài khoản chưa từng cài: mở app, chỉ một màn hình với nút "Cấp quyền Trợ năng"; cấp quyền xong app tự mở lại và gõ được. | — | [ ] |
| 14 | Secure Input | Chuyển sang tiếng Anh, vào một ô mật khẩu (Terminal: `sudo -v`): cảnh báo Secure Input vẫn hiện trên menu bar. | — | [ ] |
| 15 | Tắt hẳn ở Terminal | Tắt tiếng Việt ở Terminal (menu bar), gõ `vieejt ` và `treen `: giữ nguyên tiếng Anh, biểu tượng vẫn ở trạng thái tắt. | — | [ ] |
| 16 | Tự chuyển không bị nhớ | Vikey: gõ trộn tới khi tự chuyển sang Anh, chuyển app khác rồi quay lại → vẫn tự chuyển về Việt khi gõ từ tiếng Việt (`vieejt `). Thoát và mở lại LeanKeys: vẫn như vậy. | — | [ ] |
| 17 | Gõ nhanh | Gõ thật nhanh (từ 8 phím/giây trở lên) câu `Nguwowfi Vieejt Nam vieets tieesng Vieejt` → "Người Việt Nam viết tiếng Việt" ở: thanh địa chỉ Chrome và một ô nhập trên trang web, VS Code, Terminal, Notes, Slack (chưa gửi). Không mất chữ, không đảo thứ tự chữ, không sót dấu. | [ ] | [ ] |
| 18 | Nếu mục 17 lỗi | Ghi lại app bị lỗi. Tăng thời gian chờ sau mỗi lần sửa chữ (micro giây, 0–30000; mặc định fast 1000, slow 8000): `defaults write io.github.anlvdt.leankeys LeanKeys.settleMicros.fast -int 5000` (Chrome, Notes, Slack…) hoặc `defaults write io.github.anlvdt.leankeys LeanKeys.settleMicros.slow -int 20000` (Terminal, VS Code), thoát và mở lại LeanKeys, thử lại mục 17. Đạt khi mục 17 không lỗi, hoặc đã đạt sau khi tăng (ghi giá trị vào ghi chú bản phát hành). Bỏ chỉnh: `defaults delete io.github.anlvdt.leankeys LeanKeys.settleMicros.fast` (và `.slow`). | [ ] | [ ] |
| 19 | Gõ tắt với Vikey | Vikey: gõ `vn` + cách trong Notes, Chrome, Slack → `Việt Nam`. | — | [ ] |
| P1 | Menu bar | Bấm trái vào icon: ô nổi mở ra, nút Tiếng Việt/English đổi ngay. | — | [ ] |
| P2 | Menu bar | Bấm phải, hoặc Option + bấm: mở menu cũ, không mở ô nổi. | — | [ ] |
| P3 | Menu bar | Ở chế độ English (icon hiện E), gõ `treen `: Vikey tự chuyển sang Tiếng Việt, icon mờ dần từ E sang V, ô nổi đang mở đổi theo ngay. | — | [ ] |
| P4 | Menu bar | Chế độ tối: ô nổi và cửa sổ Cài đặt đều đọc rõ. | — | [ ] |
| P5 | Menu bar | Bật "Giảm chuyển động" của macOS: icon đổi ngay, không mờ dần. Ở Cài đặt → Nâng cao, đổi "Lõi gõ" rồi về Chung: các mục chỉ dành cho Gõ Nhanh hiện hoặc ẩn ngay. | — | [ ] |
| P6 | Menu bar | Bấm icon lần nữa thì ô nổi đóng, không mở lại. | — | [ ] |
| A1 | Cài mới (Trợ năng) | Trên máy mới: bấm "Cấp quyền Trợ năng", LeanKeys hiện trong danh sách Trợ năng; bật một công tắc là gõ được. | — | [ ] |
| A2 | Cửa sổ chào bị che hoặc đã đóng | Đưa cửa sổ chào của LeanKeys ra sau một cửa sổ khác, hoặc đóng hẳn cửa sổ đó, rồi cấp quyền Trợ năng: LeanKeys tự mở lại đúng một lần và gõ được. | — | [ ] |
| A3 | Cập nhật self-signed | Cập nhật từ bản self-signed sang bản self-signed khác: gõ vẫn được, không phải cấp quyền lại. | — | [ ] |
| A4 | Từ ad-hoc lên self-signed | Máy đang chạy bản ad-hoc đã cấp quyền. Cập nhật lên bản self-signed đầu tiên: LeanKeys tự reset mục của chính nó trong Trợ năng, chỉ cần gạt một công tắc là gõ được. | — | [ ] |
| S1 | Gợi ý gõ tắt | Cài đặt → Chung → bật "Gợi ý gõ tắt": màn giải thích hiện ra; bấm Huỷ thì công tắc vẫn tắt, bấm Bật thì công tắc bật. | — | [ ] |
| S2 | Gợi ý gõ tắt | Làm với từng engine: gõ cùng một số điện thoại thử (`0900 000 000`) rồi Return, 3 lần trong Notes: ô nổi hiện "Có 1 gợi ý gõ tắt". Bấm vào, bấm Thêm; gõ `sdt` + cách thì ra đúng số đó, đúng một lần (với Gõ Nhanh: Gõ Nhanh tự bung, không bung đôi). Gõ `sdt` + Return thêm 3 lần: không có gợi ý mới. | [ ] | [ ] |
| S3 | Gợi ý gõ tắt | Gõ cùng một chuỗi 3 lần trong ô mật khẩu của Safari (Return sau mỗi lần): không có gợi ý nào. | — | [ ] |
| S4 | Gợi ý gõ tắt | Cài đặt → Nâng cao → "Xoá dữ liệu gợi ý gõ tắt" → Xoá: ô nổi không còn dòng gợi ý, danh sách gợi ý trống; Bảng gõ tắt, "Từ giữ nguyên" và "Tên đã học" vẫn còn. | — | [ ] |
| S5 | Chữ hoa với Shift | Gõ `DDaif Loan` trong Notes, giữ Shift (không bật Caps Lock) khi gõ `DD` và `L`: ra "Đài Loan", không ra "đài Loan". | [ ] | [ ] |
| C1 | 4C · ⌫ sau phím gõ đúp | Vikey, tiếng Việt: gõ `hocjj` rồi ⌫ trong Notes: ra "học", biểu tượng vẫn là V. | — | [ ] |
| C2 | 4C · Tự học có ngữ cảnh | Trong một câu tiếng Anh (`about its`), gõ "its" rồi ⌫⌫ để giữ nguyên. Lần sau gõ lại `about its`: "its" được giữ nguyên ngay. | — | [ ] |
| C3 | 4C · Tự học không ngữ cảnh | Gõ "cos" ở hai câu khác nhau, mỗi lần ⌫⌫ để giữ nguyên. Lần thứ ba, ở một câu khác nữa, "cos" được giữ nguyên ngay. Cài đặt → Nâng cao → "Từ giữ nguyên" có dòng "cos". | — | [ ] |
| C4 | 4C · Ô mật khẩu | Trong ô mật khẩu của Safari, gõ "its" rồi ⌫⌫ hai lần: "Từ giữ nguyên" không có thêm dòng nào. | — | [ ] |
| U1 | Cập nhật trong ô nổi | Bản Release, máy đang có mạng, đang chạy bản mới nhất: bấm trái icon → "Kiểm tra cập nhật". Thấy vòng quay "Đang kiểm tra cập nhật…", rồi "Bạn đang dùng bản mới nhất". Đóng ô nổi, mở lại: nút "Kiểm tra cập nhật" hiện lại. | — | [ ] |
| U2 | Cập nhật trong ô nổi | Bản Release self-signed cũ hơn bản trên GitHub: bấm "Kiểm tra cập nhật" một lần, không bấm gì thêm. Thấy thanh tiến độ "Đang tải bản mới… N%", rồi "Đang cài — LeanKeys sẽ tự mở lại". App tự thoát, tự mở lại ở bản mới (Giới thiệu hiện đúng số bản), gõ được ngay, không phải cấp lại quyền Trợ năng. Đóng ô nổi giữa chừng cũng không làm dừng việc cài. | — | [ ] |
| U3 | Cập nhật trong ô nổi | Tắt Wi-Fi, bấm "Kiểm tra cập nhật": một dòng "Lỗi kết nối, hãy kiểm tra mạng" và nút "Thử lại"; không có chữ tiếng Anh. Bật Wi-Fi, bấm "Thử lại": chạy như U1 hoặc U2. | — | [ ] |
| U4 | Cập nhật trong ô nổi | Bản mới ký ad-hoc (`leankeys/build.sh` trên máy không có chứng chỉ, đặt DMG làm bản tải về): ô nổi báo "Không cài được bản mới", app vẫn chạy bản cũ, gõ được. | — | [ ] |
| K1 | Phím đi thẳng · ô đăng nhập | Safari, một trang đăng nhập: gõ `nguyenvana` vào ô Email hoặc Username khi đang bật tiếng Việt: chữ giữ nguyên, không thành "nguyễnvana". | — | [ ] |
| K2 | Phím đi thẳng · điều khiển từ xa | Điều khiển một máy Windows qua MacViewer, TeamViewer hoặc AnyDesk, bật bộ gõ bên Windows: gõ `tieengs vieejt` ra "tiếng việt" một lần, không bị lỗi hay bỏ dấu hai lần. | — | [ ] |
| K3 | Không học mật khẩu | Bật "Gợi ý gõ tắt". Trong Terminal chạy `sudo -k; sudo true` ba lần, gõ mật khẩu rồi Enter; trong TextEdit gõ một từ trộn chữ và số (ví dụ `Thu@2024`) rồi Enter ba lần: không có gợi ý gõ tắt nào. | — | [ ] |
| K4 | Nhật ký gỡ lỗi không lộ chữ gõ | Cài đặt → Nâng cao: bật "Nhật ký gỡ lỗi", gõ `xin chào bạn` rồi Enter, mở `~/Library/Logs/LeanKeys/debug.log`: không có chữ nào đã gõ, phím chữ hiện là `char`, chỉ có độ dài như `<3>`; không có tệp `/tmp/gonhanh_debug.log` mới. Tắt "Nhật ký gỡ lỗi": tệp bị xoá. | — | [ ] |
| D1 | 4D · Tự viết hoa tên riêng | Vikey, tiếng Việt, Notes: gõ `tooi owr haf nooij ` ra "tôi ở Hà Nội". | — | [ ] |
| D2 | 4D · Tự viết hoa tên riêng | Vikey, Notes: gõ `nguyeenx vawn an ` ra "Nguyễn Văn An". | — | [ ] |
| D3 | 4D · Tên tự học | Vikey, Notes: gõ `anh Hufng ` (tự gõ chữ H hoa) ở hai câu khác nhau, rồi gõ `anh hufng ` (chữ thường): ra "anh Hùng". Cài đặt → Nâng cao → "Tên đã học" có dòng "Hùng". | — | [ ] |
| D4 | 4D · Hoàn tác viết hoa | Vikey, Notes: gõ `owr haf nooij ` (LeanKeys viết thành "ở Hà Nội"), bấm ⌫ ngay: trả lại chữ thường "ở hà nội". Rồi Cài đặt → Nâng cao → "Từ giữ nguyên" có dòng "hà nội (giữ chữ thường)" sau "ở"; bấm xoá dòng đó (để D1 vẫn đạt ở lần thử sau). | — | [ ] |
| D5 | 4D · Bỏ phím lỡ bấm cùng Enter | Vikey, Notes: gõ "xong." rồi bấm `\` và Enter gần như cùng lúc: dòng kết thúc ở "xong.", không có `\`. | — | [ ] |
| D6 | 4D · Bỏ phím lỡ bấm cùng Enter | Vikey, Terminal: gõ `\` rồi Enter: `\` vẫn được giữ. | — | [ ] |

Chỉ gõ `yes` khi cả 66 ô đều đạt.
