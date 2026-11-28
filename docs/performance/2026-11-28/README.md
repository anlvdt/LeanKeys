# Audit hiệu năng LeanKeys — 28/11/2026

## Phạm vi và nhận dạng

Mã nguồn c6eb6ddb97df9985fb428dae6b8fd4cc59bf3114, nhánh codex/performance, macOS arm64. Worktree có tối ưu DebugLog từ lượt trước và benchmark bổ sung. Bản cài 1.15 có SHA256 3632e155d8042704acf5bfdea4bf00740c13f651808fb90c67ac26a2de62f995. Chưa chứng minh binary cài đặt được tạo từ đúng commit này.

## Phép đo và kết quả

| Thành phần | Kết quả | Giới hạn |
|---|---|---|
| Callback phím thực tế TextEdit | p95 17.555 / 15.476 / 16.958 ms với khoảng chờ phát 100 / 50 / 33 ms | 24 mẫu mỗi lượt, gồm thao tác xóa vùng thử, log bật, chưa đo đến pixel hiển thị |
| Tiêm thay chữ thực tế | tối đa 14.405 / 12.578 / 13.227 ms | 4 lần thay chữ mỗi lượt |
| Độ đúng | Cả 3 lượt ra đúng “Chào bạn chào bạn ” | Chuỗi ngắn, chưa bao phủ tốc độ gõ kéo dài hay nhiều ứng dụng |
| Engine mẫu ngắn | p95 2.334 µs | Lặp chuỗi 11 phím, engine đã ấm trong suite |
| Dự đoán cá nhân giữa từ | p95 0.162 ms, p99 0.446 ms, max 4.649 ms | Replay corpus, chưa có tranh chấp khóa với learner |
| QuickType | p95 8.857 ms, p99 15.527 ms | 1.318 lượt, gọi từ harness |
| AppKit list đổi nội dung | p95 12.601 ms, p99 15.009 ms | 120 lượt, show + CATransaction.flush + runloop, chưa đo pixel |
| AX TextEdit | 149/150 thành công, p95 0.422 ms, p99 41.380 ms | Một cửa sổ trắng; lấy mẫu liên tiếp |
| AX Chrome | 150/150 thành công, p95 0.322 ms | Trạng thái ứng dụng tại thời điểm đo |
| Học cá nhân RAM | p50 2.427 ms, p95 4.274 ms | 1.869 câu mẫu, gồm câu bị bộ lọc loại |
| Học cá nhân có file mã hóa | p50 25.377 ms, p95 30.294 ms, max 84.327 ms | Cùng corpus; trạng thái cuối hơi khác do thời gian và thứ tự loại bản ghi |

Mỗi lượt gõ dùng CGEventPost qua agent-desktop press, kiểm tra kết quả qua AX. type theo PID dùng Unicode đã bị loại khỏi phép đo vì bỏ qua đường phím cần đánh giá. Khoảng chờ phát cộng thêm overhead công cụ, nên 33 ms không tương đương chính xác 30 phím/giây.

## Kiểm tra kiến trúc và ưu tiên

1. Tiêm phím đồng bộ chiếm phần lớn thời gian trong các callback có thay chữ đã quan sát. Cần thử workload dài ở từng ứng dụng trước khi giảm delay.
2. UI và QuickType có chi phí mili giây đáng kể. PredictionController còn có thời gian chờ QuickType tối đa 25 ms. Các chặng có thể chồng lấp nên không cộng các p95.
3. PersonalPredictionModel xây lại chỉ mục trong khóa chung với truy vấn dự đoán mỗi câu, rồi JSON encode và lưu toàn bộ snapshot. Lưu chạy trên learner queue. Cần benchmark tranh chấp khóa trước khi kết luận mức ảnh hưởng tới gõ. Gộp lưu cần quyết định rõ giới hạn mất dữ liệu khi crash.
4. AX có hai đường riêng. CaretLocator của gợi ý chạy trên axQueue. detectMethod trong RustBridge chạy đồng bộ trên event tap và cache 200 ms. Benchmark CaretLocator không đo detectMethod.
5. UpdateManager dùng URLSession và timer giờ. Delegate download trên main có thao tác xóa/di chuyển file, cần đo với file cập nhật lớn. Chưa thực hiện tải hay cài cập nhật.
6. PhraseLearner cũng lưu sau observe. Chưa đo riêng ở dữ liệu lớn.

## Kiểm tra đúng

Suite Release chạy 635 test, 3 skipped, 0 failures. LearningCostBenchTests bổ sung chạy riêng, 1 test qua. Suite bao gồm engine, prediction, learner, store, UI và các chính sách cập nhật thuộc SwiftPM. Đây không phải xác nhận build ứng dụng Xcode hay toàn bộ shell integration.

## Tái lập

Chạy từ gốc repository.

```sh
LEANKEYS_PREDICT_BENCH=1 LEANKEYS_BENCH_OUT=/tmp/leankeys-audit swift test -c release
LEANKEYS_PREDICT_BENCH=1 swift test -c release --filter LearningCostBenchTests
```

live.py là bản ghi quy trình CLI lần chạy này. AX ref gắn với cửa sổ thử đã quan sát nên phải lấy ref mới trước khi chạy lại. Chỉ chạy sau khi có cửa sổ trắng và quyền phát phím.

## Những phần còn thiếu để kết luận toàn diện

- Build binary có provenance rõ ràng, so sánh trước/sau trên cùng cấu hình.
- Timestamp từng chặng detect AX, engine/router, log, injection và xác nhận đầu ra trên cùng sự kiện.
- Đo cold launch nhiều lần tới event tap sẵn sàng.
- Gõ dài, macro, undo, paste, Unicode tổ hợp, đổi app và Word/browser/editor thực tế.
- Tải đồng thời learner/predictor, RAM theo thời gian, disk bytes, timer một giờ và cập nhật.
- Cửa sổ idle thu thập trong phiên audit có cả thời gian gõ, chỉ được diễn giải là nền/tải nhẹ hỗn hợp.

Các khoảng trống này ngăn việc tuyên bố tối ưu toàn ứng dụng hoặc xác định một nút thắt duy nhất.

## Kết quả bổ sung

Build universal Release từ worktree thành công, self-signed. Binary mới SHA256 427d330730b4a2e5487b78412173e0724f6242ca3f6e1e9952fbe0ff83a87688, tại dist/LeanKeys.app. Các phép gõ thực tế ở trên dùng bản cài cũ.

Hai cửa sổ 30 giây không phát phím đo được CPU 0.87 và 0.96 ms, footprint 26.70 MiB, 17 interrupt wakeup mỗi cửa sổ, không có package idle wakeup. Máy vẫn có tác vụ build/test nền, đây là CPU riêng tiến trình ứng dụng.

Stress đọc đồng thời học liên tục cho p95 8.652 ms so với 0.119 ms khi chỉ đọc. Kịch bản học liên tục nặng hơn sử dụng bình thường và lần đo này trùng một phần build. Cần xem kết quả chạy lại sau build trước khi quy tác động cho trải nghiệm thực tế.

Sau build, stress đọc/học được chạy lại. p95 đọc đơn 0.159 ms, đọc đồng thời học 8.163 ms; p99 tương ứng 0.456 và 13.015 ms. Kết quả tái hiện ảnh hưởng tranh chấp khóa trong stress workload. Không suy ra mọi lần gõ bình thường chịu mức trễ này.

Benchmark engine đã được chỉnh để đặt Vietnamese/pure Telex/reset rõ ràng và kiểm tra toàn bộ đầu ra 1.000 câu. Test qua; p50 0.833 µs, p95 1.042 µs, p99 1.583 µs. Cấu hình pure Telex khác phép đo cũ nên không dùng chênh lệch này để tuyên bố tăng tốc.

Tài liệu trắng TextEdit do audit tạo đã đóng và bỏ nội dung mẫu. Không thay đổi delay tiêm phím trong lượt audit này.
