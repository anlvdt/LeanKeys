# mixbench: gõ trộn Việt/Anh, Gõ Nhanh vs Vikey

Gõ mô phỏng từng câu bằng Telex qua engine thật của cả hai (người dùng **không bấm gì thêm**: không đổi ngôn ngữ, không ESC), rồi đếm số từ ra sai.

```sh
P=../../vendor/vikey/Tools/autoswitch/sim
E=../../vendor/vikey/Engine
clang++ -std=c++17 -O2 -w -I$E -I$E/platforms -include cstring -o vk vk.cpp $E/Driver.cpp $E/Engine.cpp $E/Vietnamese.cpp $E/SmartSwitchKey.cpp
(cd gn && cargo build --release)
python3 -I prep2.py $P/prep.py mine.txt > mine.tsv
gn/target/release/gnbench < mine.tsv > mine.gn ; ./vk < mine.tsv > mine.vk
python3 -I score.py mine.tsv mine.gn "Gõ Nhanh"; python3 -I score.py mine.tsv mine.vk "Vikey"
python3 -I overlap.py mine.tsv mine.gn mine.vk
```

## Kết quả 2026-11-15 (Gõ Nhanh v1.0.165, Vikey v1.0.33)

Tỉ lệ từ ra sai. Hai kiểu đặt dấu `hoà`/`hòa` đều tính là đúng.

| Kho câu | Số từ | Gõ Nhanh (không auto-restore) | Gõ Nhanh (auto-restore) | Vikey (tự chuyển) |
|---|---|---|---|---|
| mine.txt (40 câu văn phòng/kỹ thuật, viết riêng) | 437 | 5.26% | 0.46% | **0.23%** |
| Vikey chat_messages | 20,676 | 9.26% | 1.90% | **0.20%** |
| Vikey synthetic_val | 87,038 | 11.32% | 3.50% | **0.13%** |

- Gõ Nhanh gần như không sai từ tiếng Việt (≤0.05%), nhưng sai 4–7% từ tiếng Anh (thêm dấu vào từ tiếng Anh).
- Vikey sai 0.1–0.3% ở cả hai phía. Lỗi riêng của nó (12 trên chat, 21 trên synthetic) là các cặp từ trùng nhau giữa tiếng Anh và Telex: `cos/có`, `car/cả`, `sex/sẽ`, `nos/nó`, `its/ít`, `queen/quên`, `moon/môn`. Không có lỗi hệ thống nào kiểu một quy tắc sai.

**Giới hạn của phép đo:**
- Hai kho chat và synthetic là dữ liệu chính Vikey dùng để tinh chỉnh, nên có lợi cho Vikey. Kho trung lập `mine.txt` còn nhỏ.
- Đây là mô phỏng gõ sạch. Phép đo không phản ánh lỗi ở tầng app macOS (thời gian gửi phím, trình duyệt…).
- `vk.cpp` gửi ký tự Shift (`? ! ( ) :` …) như phím gốc cộng Shift. Bản đầu của harness bỏ qua chúng, làm từ đứng trước `?` không được chốt (đã sửa).
