# Tối ưu sau audit

## Các thay đổi

- PersonalPredictionModel dùng khóa riêng để xuất bản/copy chỉ mục đọc. Mutations, load, save và erase được tuần tự hóa, tránh snapshot cũ ghi đè sau erase hoặc sau snapshot mới.
- Xây chỉ mục ngoài khóa đọc. Dự đoán tiếp tục dùng chỉ mục hoàn chỉnh trước đó trong lúc learner xử lý câu mới.
- Ứng dụng gộp lưu cá nhân theo cửa sổ 2 giây, đã được người dùng cho phép. Lưu ngay khi kết thúc bình thường và khi giải phóng model. Xóa dữ liệu hủy lần lưu chờ. Crash có thể làm mất các câu học chưa lưu trong cửa sổ này. Độ trễ scheduler và tác vụ đang chạy có thể kéo dài thời điểm ghi thực tế.
- Store mặc định của API vẫn lưu ngay; ứng dụng bật saveDelay=2 rõ ràng. Định dạng file mã hóa giữ nguyên.
- Bảng gợi ý chỉ thay attributed text ở các dòng khác, cache thêm kind để định dạng shortcut đúng, giữ cache khi ẩn để tái sử dụng.
- Timer kiểm tra cập nhật mỗi giờ cho phép macOS gộp lịch với tolerance 60 giây.
- Bao gồm tối ưu metadata DebugLog từ lượt audit đầu.

## Phép đo ban đầu sau sửa

Stress đọc đồng thời học cho p95 0.111 ms ở lượt đầu, 0.146 ms ở lượt tiếp theo, so với 8.163 ms trong audit. UI AppKit đổi nội dung p95 4.566 ms so với 12.601 ms trước đó. Đây là các lượt chạy khác nhau trên máy đang có tải nền, không phải paired A/B cô lập. Test UI dùng show/commit, chưa đo tới pixel.

## Thử Word

Đã thử override slow:word từ 3000/8000/3000 xuống 1000/3000/1000 µs trên tài liệu trắng, khoảng phát 100 và 33 ms. Cả bốn lượt baseline/tuned giữ đúng dấu và thứ tự chữ trong hai câu ngắn. Chữ hoa đầu câu thay đổi theo trạng thái auto-capitalization của Word. Override đã được phục hồi sau thử, tài liệu mẫu đóng không lưu. Mẫu này chưa đủ để thay mặc định cho mọi phiên Word; cần corpus dài, undo và workload sửa giữa dòng trước khi giữ tuning.

## Phần còn mở

QuickType, AX và các khoảng chờ tiêm phụ thuộc hệ điều hành/ứng dụng đích. Audit chưa chứng minh giá trị thay thế an toàn cho mọi ứng dụng. Cold launch lặp lại, timer một giờ, pixel latency và cập nhật thực tế vẫn là các khoảng trống đo lường. Những mục đó chưa có bản sửa được xác nhận.

## Kiểm tra cuối

22 test chọn lọc qua. Ở lượt cuối, đọc dưới tải học p95 0.119 ms (audit 8.163 ms), học có gộp lưu p95 4.516 ms (audit lưu ngay 30.294 ms). UI AppKit đổi nội dung p95 8.909 ms, cho thấy dao động giữa các lượt 4.566–8.909 ms. Không dùng một lượt UI để khẳng định tỷ lệ tăng tốc cố định.

Build universal Release với các thay đổi cuối thành công. Bản build tại dist/LeanKeys.app; ứng dụng cài sẵn trên máy vẫn là bản được dùng cho phép thử Word. Chưa xác nhận trải nghiệm đầu-cuối của binary mới.

Full suite cuối chạy 639 test, 13 skipped, 0 failures. Các benchmark opt-in được chạy riêng trong lượt 22 test ở trên. Test mới kiểm tra lưu tự động theo deadline, flush snapshot mới nhất, phục hồi và erase hủy lưu chờ.
