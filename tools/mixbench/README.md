# mixbench: gõ trộn Việt/Anh, Gõ Nhanh vs Vikey

Gõ mô phỏng từng câu bằng Telex qua engine thật của cả hai (người dùng **không bấm gì thêm**: không đổi ngôn ngữ, không ESC), rồi đếm số từ ra sai.

```sh
cd tools/mixbench   # from the repository root
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
| Vikey chat_messages | 20.676 | 9.26% | 1.90% | **0.20%** |
| Vikey synthetic_val | 87.038 | 11.32% | 3.50% | **0.13%** |

- Gõ Nhanh gần như không sai từ tiếng Việt (≤0.05%), nhưng sai 4–7% từ tiếng Anh (thêm dấu vào từ tiếng Anh).
- Vikey sai 0.1–0.3% ở cả hai phía. Lỗi riêng của nó (12 trên chat, 21 trên synthetic) là các cặp từ trùng nhau giữa tiếng Anh và Telex: `cos/có`, `car/cả`, `sex/sẽ`, `nos/nó`, `its/ít`, `queen/quên`, `moon/môn`. Không có lỗi hệ thống nào kiểu một quy tắc sai.

**Giới hạn của phép đo:**
- Hai kho chat và synthetic là dữ liệu chính Vikey dùng để tinh chỉnh, nên có lợi cho Vikey. Kho trung lập `mine.txt` còn nhỏ.
- Đây là mô phỏng gõ sạch. Phép đo không phản ánh lỗi ở tầng app macOS (thời gian gửi phím, trình duyệt…).
- `vk.cpp` gửi ký tự Shift (`? ! ( ) :` …) như phím gốc cộng Shift. Bản đầu của harness bỏ qua chúng, làm từ đứng trước `?` không được chốt (đã sửa).

## Lỗi rồi sửa bằng ⌫ (4C)

`lk` gõ qua shim thật của LeanKeys (`leankeys/VikeyShim/lk_vikey.cpp`, có bản sửa ⌫ sau phím gõ đúp, spec §12.1). `lk --no-fix` tắt bản sửa đó, tức là hành vi của Vikey qua cùng harness. `typo.py` chèn một lỗi mà người gõ sửa ngay bằng ⌫ vào 30% số từ tiếng Việt (chế độ VN) hoặc 50% số từ tiếng Anh (chế độ EN); đích chấm điểm giữ nguyên.

- Phím trong tsv: `` ` `` là ⌫; `|` đánh dấu độ dài từ đang gõ; `^` bấm ⌫ cho tới khi từ về đúng độ dài đó.
- Chế độ: `dbl` phím dấu bấm đúp rồi ⌫ (`hocjj⌫`); `extra` chữ thừa rồi ⌫; `mid` sai một chữ giữa từ, cuối từ mới thấy, xoá lùi về đó rồi gõ lại; `endbl`, `enextra`, `enmid` tương tự cho từ tiếng Anh (`endbl`: chữ cuối bấm đúp rồi ⌫).
- `vk` không đọc được đầu ra của `typo.py` (nó gửi `|` `^` thành phím có Shift và bỏ `` ` ``). Với văn bản sạch, `vk` và `lk --no-fix` cho đầu ra giống hệt từng byte trên cả hai kho.

```sh
cd tools/mixbench   # from the repository root
P=../../vendor/vikey/Tools/autoswitch/sim
E=../../vendor/vikey/Engine
S=../../leankeys/VikeyShim
clang++ -std=c++17 -O2 -w -I$E -I$E/platforms -I$S/include -include cstring -o lk lk.cpp $S/lk_vikey.cpp $E/Driver.cpp $E/Engine.cpp $E/Vietnamese.cpp $E/SmartSwitchKey.cpp
python3 -I prep2.py $P/prep.py mine.txt > mine.tsv
python3 -I prep2.py $P/prep.py $P/corpus/chat_messages.txt > chat.tsv
for c in mine chat; do for m in dbl extra mid endbl enextra enmid; do
  python3 -I typo.py $c.tsv $m 5 > $c.$m.tsv
  ./lk --no-fix < $c.$m.tsv > $c.$m.vk.out; ./lk < $c.$m.tsv > $c.$m.lk.out
  python3 -I score.py $c.$m.tsv $c.$m.vk.out "Vikey $c $m"; python3 -I score.py $c.$m.tsv $c.$m.lk.out "LeanKeys $c $m"
done; done
```

### Kết quả 2026-11-16 (seed 5)

Số từ ra sai trên tổng số từ, kèm tỉ lệ sai ở phía bị chèn lỗi (VN hoặc EN). Vikey = `lk --no-fix`, LeanKeys = `lk`.

| Lỗi rồi sửa bằng ⌫ | mine.txt (437 từ): Vikey | mine.txt: LeanKeys | chat_messages (20.676 từ): Vikey | chat_messages: LeanKeys |
|---|---|---|---|---|
| Không có lỗi | 1 (VN 0.36% · EN 0.00%) | 1 (như cũ) | 41 (VN 0.15% · EN 0.25%) | 41 (như cũ) |
| `dbl` phím dấu bấm đúp | 58 (VN 21.01%) | **1 (VN 0.36%)** | 2.143 (VN 18.89%) | **95 (VN 0.63%)** |
| `extra` chữ thừa | 18 (VN 5.43%) | 18 (VN 5.43%) | 671 (VN 5.76%) | 641 (VN 5.50%) |
| `mid` sai giữa từ | 15 (VN 5.43%) | 15 (VN 5.43%) | 529 (VN 4.50%) | 529 (VN 4.50%) |
| `endbl` chữ cuối bấm đúp (EN) | 11 (EN 6.21%) | **5 (EN 2.48%)** | 738 (EN 7.37%) | **461 (EN 4.43%)** |
| `enextra` chữ thừa (EN) | 9 (EN 4.97%) | 9 (EN 4.97%) | 476 (EN 4.75%) | 470 (EN 4.69%) |
| `enmid` sai giữa từ (EN) | 5 (EN 3.11%) | 5 (EN 3.11%) | 305 (EN 3.06%) | 305 (EN 3.06%) |

- Không chế độ nào có số từ sai tăng khi bật bản sửa; văn bản sạch cho đầu ra giống hệt.
- Chat `dbl`: số từ tiếng Anh sai là 22 với Vikey và 24 với LeanKeys. 24 chính là mức của văn bản sạch: Vikey "đúng" thêm 2 từ tiếng Anh chỉ vì nó đã chuyển sang tiếng Anh ở từ tiếng Việt gõ lỗi ngay trước.
- Bảng ở spec §12 đo với 50% số từ tiếng Việt (bản thử `typo2.py`), không phải 30%. Đổi tỉ lệ VN trong `typo.py` thành 0.5 thì harness này ra đúng các số đó trên chat: `dbl` VN 28.64% → 0.95%, `extra` 9.54% → 9.09%, `mid` 7.43% → 7.43%. Các chế độ EN (50%) trùng với spec ở cả hai cách.
