# LeanKeys — Tự học chỉ khi người dùng cho phép (bản phát hành), bật hết trên máy phát triển

Viết ngày 2026-11-28. Người dùng yêu cầu: trên máy phát triển bật mọi tính năng tự học, nhật ký và tự động; bản phát hành tắt hết các tính năng thu thập dữ liệu, người dùng tự bật, có cảnh báo rõ dữ liệu chỉ nằm trên máy. Người dùng chọn phương án A cho người đang dùng (xem 3). Quy tắc này phải được ghi vào quy trình phát hành (xem 5).

## 1. Thu thập dữ liệu là gì

Một tính năng "thu thập dữ liệu" khi nó ghi xuống đĩa điều gì đó suy ra từ chữ người dùng gõ:

| Tính năng | Tệp | Mặc định cũ | Mặc định mới (bản phát hành) |
|---|---|---|---|
| Nhớ từ bạn sửa (⌫⌫, ⌃⌫, từ ghim), gồm học tên riêng bạn tự viết hoa | `undo-rules.bin`, `learned-names.bin` | Bật, không hỏi | **Tắt**, bật phải đồng ý |
| Gợi ý gõ tắt (4B) | `learn.bin` | Tắt, bật phải đồng ý | Giữ nguyên, sửa câu đồng ý cho thống nhất |
| Nhật ký gỡ lỗi | `~/Library/Logs/LeanKeys/debug.log` | Tắt, tự tắt sau 24 giờ | Giữ nguyên; thêm câu "chỉ ghi trên máy" |

Không thuộc nhóm này (giữ nguyên): viết hoa tên riêng từ từ điển có sẵn, sửa gõ đúp phím dấu, bỏ phím dính khi Enter, phím ⌃⌫ và ⌫⌫ (vẫn chạy khi tắt học, chỉ không ghi nhớ).

## 2. Đồng ý khi bật

Bật "Nhớ từ bạn sửa" lần đầu hiện hộp đồng ý, theo đúng mẫu của Gợi ý gõ tắt (`consentPending`, xác nhận mới ghi cài đặt). Khoá mới `LeanKeys.undoLearning.consented`.

- Tiêu đề: `Cho LeanKeys nhớ từ bạn sửa?`
- Nội dung: `LeanKeys sẽ ghi lại những từ bạn sửa bằng ⌫⌫ hoặc ⌃⌫ và những tên bạn tự viết hoa, để lần sau gõ đúng ngay. Dữ liệu chỉ nằm trên máy này, được mã hoá, không bao giờ gửi đi đâu. Không học trong ô mật khẩu, terminal và các app bạn loại trừ. Bạn xem và xoá được bất cứ lúc nào ở Cài đặt › Nâng cao.`
- Nút: `Cho phép` / `Không`.
- Câu đồng ý của Gợi ý gõ tắt thêm cụm "không bao giờ gửi đi đâu" cho thống nhất.
- Dòng phụ của công tắc nhật ký gỡ lỗi thêm: `Chỉ ghi trên máy này, không chứa chữ bạn gõ, không gửi đi đâu.`

## 3. Người đang dùng khi cập nhật (phương án A)

Chạy một lần (cờ `LeanKeys.privacyDefaultsApplied`):
- Người **chưa từng tự gạt** "Nhớ từ bạn sửa" (không có giá trị lưu): theo mặc định mới là tắt. Dữ liệu đã học vẫn nằm trên đĩa, không bị xoá, nhưng không áp dụng khi tắt (như hiện nay).
- Người đã tự lưu một giá trị: giữ nguyên lựa chọn của họ. Giá trị `true` do người dùng tự bật được coi là đã đồng ý.
- Nếu người dùng thuộc nhóm đầu **và** có dữ liệu đã học (tệp tồn tại, có luật hoặc tên), ô nổi hiện một thẻ một lần: `LeanKeys giờ chỉ tự học khi bạn cho phép. Những từ đã học vẫn được giữ trên máy.` với nút `Bật lại…` (mở hộp đồng ý ở 2) và `Để tắt`. Bấm một trong hai thì thẻ không hiện nữa.

## 4. Máy phát triển này

Không có bản build riêng. Mọi thứ là cài đặt của máy (`defaults`), không đi vào DMG:
- `LeanKeys.undoLearning = 1`, `LeanKeys.undoLearning.consented = 1`, `LeanKeys.learn.enabled = 1`, `LeanKeys.learn.consented = 1`, `LeanKeys.autoCapitalize = 1`, `LeanKeys.doubleKeyFix = 1`, `LeanKeys.strayEnter = 1`, `LeanKeys.autoFix = 1`.
- Nhật ký gỡ lỗi bật, và không tự tắt sau 24 giờ khi có tệp `~/Library/Logs/LeanKeys/debug.keep` (cờ chỉ có trên máy phát triển; `DebugLog.isOnAfterExpiry` bỏ qua hạn khi tệp này tồn tại). Bản phát hành không tạo tệp này.

## 5. Quy tắc phát hành

Ghi vào `sync/release.sh` và tài liệu phát hành:
- **Quy tắc:** bản phát hành không được thu thập dữ liệu khi người dùng chưa đồng ý. Mọi tính năng ở bảng 1 phải mặc định tắt trong code; cài đặt của máy phát triển không ảnh hưởng vì không nằm trong DMG.
- `release.sh` chạy một bước kiểm tra trước khi tạo tag: `swift test --filter PrivacyDefaultsTests`. Test này khẳng định với `UserDefaults` trống: `UndoLearning.learning == false`, `ShortcutSuggestionsModel.enabled == false`, `DebugLog` tắt, và DMG/app không chứa `debug.keep`. Test hỏng thì `release.sh` dừng, không phát hành.
- Thêm mục vào `sync/manual-checklist.md`: cài bản mới trên một tài khoản máy sạch, mở Cài đặt › Nâng cao, mọi công tắc học đều tắt; bật "Nhớ từ bạn sửa" phải hiện hộp đồng ý.
- Thêm dòng vào bản bàn giao (quy tắc bắt buộc).

## 6. Nơi đặt code

- `leankeys/LeanKeysKit/Learn/UndoLearning.swift`: mặc định `false`, cặp `learningConsentPending` / `confirmLearningConsent()` / `cancelLearningConsent()`, khoá consent, migration một lần, cờ "có dữ liệu đã học".
- `leankeys/LeanKeysKit/UI/UndoLearningSection.swift`, `LearnSettingsSection.swift`: hộp đồng ý, câu chữ.
- `leankeys/LeanKeysKit/UI/StatusPopoverView.swift`: thẻ một lần.
- `leankeys/LeanKeysKit/Engine/DebugLog.swift`: tệp `debug.keep`.
- `platforms/macos/AdvancedSettingsView.swift`: dòng phụ của nhật ký (dòng đã có hook `copy`).
- `sync/release.sh`, `tests/sync/test_release.sh`, `sync/manual-checklist.md`, test mới `PrivacyDefaultsTests.swift`.

## 7. Cách làm đã chọn

| Cách | Đánh đổi |
|---|---|
| **Cài đặt máy + mặc định tắt trong code** (chọn) | Một bản build cho mọi người; máy phát triển chỉ khác ở `defaults`. |
| Cờ build riêng cho bản phát hành | Hai bản build dễ lệch nhau; bản thử không giống bản phát hành. |
