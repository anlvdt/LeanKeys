# Thử tay trước khi đăng bản

Cài bản trong DMG (kéo `LeanKeys.app` vào Applications, cấp quyền Accessibility nếu được hỏi). Mục có hai ô làm hai lần: một lần với engine **Gõ Nhanh**, một lần với **Vikey** (menu bar → Cài đặt → Engine gõ). Mục chỉ có ô Vikey (— ở cột Gõ Nhanh) làm một lần với Vikey. Kiểu gõ Telex.

Câu thử: `Tieengs Vieejt truowfng hojc` phải ra "Tiếng Việt trường học". Gõ thêm một từ tiếng Anh rồi Space, từ đó phải giữ nguyên: `push` với Gõ Nhanh, `more` với Vikey.

| # | Ở đâu | Thử gì | Gõ Nhanh | Vikey |
|---|-------|--------|:--------:|:-----:|
| 1 | Chrome | Gõ câu thử vào thanh địa chỉ (gợi ý tự hoàn thành không nuốt dấu), rồi vào một ô nhập trên trang web. | [ ] | [ ] |
| 2 | Spotlight | ⌘Space, gõ câu thử. Chữ không bị lặp hay mất dấu. | [ ] | [ ] |
| 3 | VS Code | Gõ câu thử trong một file và trong ô tìm kiếm (⌘F). | [ ] | [ ] |
| 4 | Terminal | Gõ câu thử sau dấu nhắc lệnh, xoá bằng Backspace giữa chừng rồi gõ tiếp. | [ ] | [ ] |
| 5 | Slack | Gõ câu thử trong ô soạn tin nhắn (chưa gửi). | [ ] | [ ] |
| 6 | Đổi engine khi đang gõ | Gõ dở một từ (`vieej`), đổi engine trong Cài đặt, quay lại gõ tiếp. Ô nhập không hỏng, từ sau gõ đúng với engine mới. | [ ] | [ ] |
| 7 | Đổi app có nhớ ngôn ngữ | Bật nhớ ngôn ngữ theo app. Tắt tiếng Việt ở Terminal, bật ở Slack; chuyển qua lại vài lần, mỗi app giữ đúng trạng thái của nó. | [ ] | [ ] |
| 8 | Return/Enter sau từ Vikey khôi phục | Gõ `more` (Vikey giữ nguyên tiếng Anh) rồi Return ngay: tin nhắn được gửi trong một ô chat (Slack, kênh thử riêng) và một form trên trang web được gửi. Chữ trước đó không đổi. | — | [ ] |
| 9 | Dấu câu sau từ đã sửa | Gõ một từ Vikey sửa (`more`, `vieejt`) rồi `,`; làm lại với `.`. Dấu phẩy, dấu chấm hiện đúng một lần. | — | [ ] |
| 10 | Caps Lock | Bật Caps Lock, gõ câu thử: ra "TIẾNG VIỆT TRƯỜNG HỌC". Tắt Caps Lock, gõ tiếp bình thường. | [ ] | [ ] |
| 11 | Cập nhật | Bản Developer ID: có bản mới, để máy rảnh hơn 30 giây; app tự cập nhật, tự mở lại, gõ được ngay. Bản ad-hoc: menu hiện "⟳ Khởi động lại để cập nhật", bấm một lần là cập nhật; màn "LeanKeys vừa được cập nhật" hiện ra, làm theo (chọn LeanKeys trong Trợ năng, bấm − rồi + thêm lại) thì gõ lại được. | — | [ ] |
| 12 | Mở cùng máy | Khởi động lại máy (launch at login bật sẵn): LeanKeys tự chạy, gõ được ngay. | — | [ ] |
| 13 | Cài mới | Trên máy hoặc tài khoản chưa từng cài: mở app, chỉ một màn hình với nút "Mở cài đặt Trợ năng"; cấp quyền xong app tự mở lại và gõ được. | — | [ ] |
| 14 | Secure Input | Chuyển sang tiếng Anh, vào một ô mật khẩu (Terminal: `sudo -v`): cảnh báo Secure Input vẫn hiện trên menu bar. | — | [ ] |
| 15 | Tắt hẳn ở Terminal | Tắt tiếng Việt ở Terminal (menu bar), gõ `vieejt ` và `treen `: giữ nguyên tiếng Anh, biểu tượng vẫn ở trạng thái tắt. | — | [ ] |
| 16 | Tự chuyển không bị nhớ | Vikey: gõ trộn tới khi tự chuyển sang Anh, chuyển app khác rồi quay lại → vẫn tự chuyển về Việt khi gõ từ tiếng Việt (`vieejt `). Thoát và mở lại LeanKeys: vẫn như vậy. | — | [ ] |
| 17 | Gõ nhanh | Gõ thật nhanh (từ 8 phím/giây trở lên) câu `Nguwowfi Vieejt Nam vieets tieesng Vieejt` → "Người Việt Nam viết tiếng Việt" ở: thanh địa chỉ Chrome và một ô nhập trên trang web, VS Code, Terminal, Notes, Slack (chưa gửi). Không mất chữ, không đảo thứ tự chữ, không sót dấu. | [ ] | [ ] |
| 18 | Nếu mục 17 lỗi | Ghi lại app bị lỗi. Tăng thời gian chờ sau mỗi lần sửa chữ (micro giây, 0–30000; mặc định fast 1000, slow 8000): `defaults write io.github.anlvdt.leankeys LeanKeys.settleMicros.fast -int 5000` (Chrome, Notes, Slack…) hoặc `defaults write io.github.anlvdt.leankeys LeanKeys.settleMicros.slow -int 20000` (Terminal, VS Code), thoát và mở lại LeanKeys, thử lại mục 17. Đạt khi mục 17 không lỗi, hoặc đã đạt sau khi tăng (ghi giá trị vào ghi chú bản phát hành). Bỏ chỉnh: `defaults delete io.github.anlvdt.leankeys LeanKeys.settleMicros.fast` (và `.slow`). | [ ] | [ ] |

Chỉ gõ `yes` khi cả 28 ô đều đạt.
