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

## Gõ kiểu chat: Return, mang trạng thái, ⌫⌫ sau Space (2026-11-28)

Các bảng trên đều cho mỗi câu bắt đầu ở tiếng Việt và kết thúc bằng Space, nên không thấy ba lỗi xảy ra khi chat. `lk` và `vk` có thêm các cờ sau (không cờ nào thì đầu ra giống hệt từng byte bản cũ, trên cả hai kho):

- `--end space|return|return-fix`: câu kết thúc bằng Space (mặc định) hay Return.
  - `return`: như ô một dòng hoặc thanh địa chỉ. Vikey D62 để nguyên từ cuối như đã gõ.
  - `return-fix` (chỉ `lk`): như ô AXTextArea, nơi LeanKeys cho Return chốt từ như Space (`lk_vikey_set_fix_at_return`).
- `--chain`: cả kho là một cuộc chat. Việt/Anh mang sang câu sau. Sau Return chỉ reset ngữ cảnh gõ, như `VikeyEngine` làm trong app.
- `--start-en`: câu đầu (hoặc mọi câu, khi không có `--chain`) bắt đầu ở tiếng Anh.
- `--langs FILE`: ghi `V`/`E` cho ngôn ngữ lúc bắt đầu mỗi câu. Đưa file này cho `score.py --langs FILE` để tách lỗi theo ngôn ngữ đầu câu. `score.py --detail` tách riêng lỗi ở từ cuối câu.
- `--undo-bad-fix` (chỉ `lk`): người gõ bấm ⌫⌫ ngay sau mỗi lần Vikey tự sửa làm hỏng từ (từ trước khi sửa đúng là đích), rồi gõ lại phím ngắt. Số đếm in ra stderr.

`typo.py` có thêm hai chế độ:
- `bsbs` (30% từ tiếng Việt) và `enbsbs` (50% từ tiếng Anh).
- Ngay sau Space kết thúc từ, người gõ bấm ⌫ hai lần (xoá Space và chữ cuối), rồi gõ lại chữ đó và Space. Đây là một lần sửa, không phải hoàn tác.
- Chỉ áp dụng cho từ có chữ cuối trên màn hình chính là phím cuối (`coong` → công; không áp dụng cho `laf` → là).

```sh
cd tools/mixbench   # from the repository root; lk, vk, mine.tsv, chat.tsv built as above
for o in "--end space" "--end return" "--chain --end return"; do
  ./vk ${=o} --langs chat.langs < chat.tsv > chat.out; python3 -I score.py chat.tsv chat.out "Vikey $o" --langs chat.langs
done
for o in "--end return" "--end return-fix" "--chain --end return" "--chain --end return-fix"; do
  ./lk ${=o} --langs chat.langs < chat.tsv > chat.out; python3 -I score.py chat.tsv chat.out "LeanKeys $o" --langs chat.langs
done
for m in bsbs enbsbs; do
  python3 -I typo.py chat.tsv $m 5 > chat.$m.tsv
  ./lk < chat.$m.tsv > chat.$m.out; python3 -I score.py chat.$m.tsv chat.$m.out "LeanKeys $m"
done
./lk --undo-bad-fix < chat.tsv > /dev/null
```

(`${=o}` là cách zsh tách chuỗi thành nhiều đối số; với bash thì viết `$o`.)

### Kết quả (LeanKeys 1.10, Vikey v1.0.34 `79547aa`)

Return và mang trạng thái: số từ ra sai trên tổng số từ, kèm số từ cuối câu sai trên tổng số câu.

| Cấu hình | mine.txt (437 từ, 40 câu) | Từ cuối sai | chat_messages (20.676 từ, 1.869 câu) | Từ cuối sai |
|---|---|---|---|---|
| Space, mỗi câu reset (như bảng cũ) | 1 (0.23%) | 0 | 41 (0.20%) | 5 (0.27%) |
| Return, ô một dòng (`--end return`; Vikey và LeanKeys như nhau) | 6 (1.37%) | 5 (12.5%) | **169 (0.82%)** | **132 (7.06%)** |
| Return trong AXTextArea (`lk --end return-fix`) | 1 (0.23%) | 0 | 41 (0.20%) | 5 (0.27%) |
| `--chain --end return` | 6 (1.37%) | 5 | 169 (0.82%) | 132 |
| `lk --chain --end return-fix` | 1 (0.23%) | 0 | 42 (0.20%) | 5 |
| `--start-en`, Space | 1 (0.23%) | 0 | 38 (0.18%) | 5 (0.27%) |

- **Lỗi lớn nhất là từ cuối tin nhắn khi Return không chốt từ.** Lỗi tăng gấp 4 lần (0.20% → 0.82%), và 132 trên 169 lỗi là từ cuối câu.
  - LeanKeys sửa đúng chỗ này, nhưng chỉ ở ô mà `FocusedField.allowsFixAtReturn` nhận là AXTextArea.
  - Bộ đo không biết Slack, Messenger, Zalo hay Discord có lọt vào nhánh đó không. Phải thử tay, hoặc ghi lại vai trò AX của từng app.
- **Mang trạng thái sang câu sau gần như không thêm lỗi** (41 → 42 với `return-fix`; 169 → 169 với `return`).
  - Với `--chain --end return`, 408 câu bắt đầu ở tiếng Anh, sai 0.93%. 1.461 câu bắt đầu ở tiếng Việt, sai 0.79%.
  - Vậy "kẹt tiếng Anh" có lỗi đo được chủ yếu là do từ cuối không được chốt, không phải do câu sau bắt đầu sai.
- **`--undo-bad-fix`: 1.254 lần Vikey tự sửa trên chat, 0 lần làm hỏng từ** (mine.txt: 23 và 0).
  - Mọi lỗi trên văn bản sạch là từ Vikey **để nguyên** ở ngôn ngữ sai (`cos implement`, `nos ra sao`, `bể`/beer, `lát`/last).
  - ⌫⌫ không cứu được các lỗi này, vì không có lần sửa nào để hoàn tác. Phải có phím "đổi từ vừa gõ" (đề xuất 2 của báo cáo gõ trộn).

⌫⌫ ngay sau Space để sửa chữ cuối (seed 5):

| Chế độ | mine.txt | chat_messages |
|---|---|---|
| Không sửa (văn bản sạch) | 1 (0.23%) | 41 (0.20%) |
| `bsbs` từ tiếng Việt (16 / 907 lần sửa) | 1 (VN 0.36%) | 42 (VN 0.16%) |
| `enbsbs` từ tiếng Anh (70 / 3.885 lần sửa), trước bản sửa §12.2a | **14 (EN 8.07%)** | **638 (EN 6.62%)** |
| `enbsbs`, sau bản sửa §12.2a | 1 (EN 0.00%) | 44 (EN 0.30%) |

- **`enbsbs` là lỗi mới tìm ra, và đúng là ví dụ `test` → `tét` người dùng hay than.**
  - Phím Telex `test` hiện "tét", rồi Space khôi phục thành "test".
  - ⌫⌫ ngay sau đó bị Vikey hiểu là **hoàn tác lần khôi phục**: màn hình quay về "tét", gõ lại `t` thành "tétt".
  - Gặp ở mọi từ tiếng Anh có phím dấu hoặc phím biến đổi: `push` → púhh, `merge` → mẻgee, `window` → ưindowư, `database` → dâtbasee.
  - `--no-fix` cho cùng số: đây là hành vi của Vikey, không phải của bản sửa 12.1.
  - Bộ học ⌫⌫ (UndoLearning) còn có thể ghi một luật "giữ như gõ" từ lần hoàn tác ngoài ý muốn này. Bộ đo không cài bộ lọc học nên không đếm được.
- **Đã sửa ngày 2026-11-28** trong shim (spec §12.2a): sau lần hoàn tác đó, phím chữ được hiểu là sửa từ. `enbsbs` trên chat giảm từ 638 (EN 6.62%) xuống **44 (EN 0.30%)**; trên mine.txt giảm từ 14 xuống 1. Mọi chế độ khác và văn bản sạch cho đầu ra giống hệt từng byte. Phần lớn lỗi còn lại là các từ trùng ở cả hai ngôn ngữ mà Vikey để nguyên dạng tiếng Việt (`mix` → mĩ, ⌫⌫ xoá "ĩ").
- `bsbs` phía tiếng Việt gần như vô hại: từ tiếng Việt hiếm khi bị sửa ở Space, nên ⌫⌫ là ⌫ thường.
- **Giới hạn của chế độ này:**
  - Người gõ thật thường xoá rồi gõ một chữ *khác*, chứ không gõ lại đúng chữ cũ.
  - Không có khoảng thời gian giữa hai lần ⌫.
  - Tỉ lệ 50% là giả định, không phải số đo hành vi.
  - Con số chỉ cho thấy độ lớn của vùng va chạm, không phải tần suất gặp thật.

Gõ Nhanh (`gn`) không có các cờ mới. Nó không có trạng thái Việt/Anh mang sang câu sau, và ESC là phím hoàn tác của nó, không phải ⌫⌫.

## ⌃⌫ đổi từ vừa gõ (2026-11-28)

`lk` có thêm hai cờ để đo phím "đổi từ vừa gõ" (`lk_vikey_convert_last_word`) và bộ học luật `convert` (spec `2026-11-28-convert-last-word-design.md`). Không cờ nào thì đầu ra giống hệt từng byte bản trước: so bằng `cmp` với `lk` build từ `e19d871` (main) trên `mine.tsv`, `chat.tsv`, 8 chế độ `typo.py` seed 5, và các cờ `--no-fix`, `--end`, `--chain`, `--start-en`, `--undo-bad-fix` (64 cặp, 0 khác).

- `--convert-wrong`: người gõ bấm ⌃⌫ **một lần** khi từ vừa chốt hiện khác đích (so như `score.py`: không phân biệt hoa thường và chỗ đặt dấu). Kiểm ở phím ngắt của từ (`Space , . ; ? ! ) ] " '`; chữ số, `-` và `/` không chốt từ). Với `--end return`, từ cuối được kiểm ngay trước Return. Với `return-fix` thì không kiểm, vì người gõ tin Return sẽ chốt từ. Đếm ra stderr: `presses` (số lần bấm), `fixed` (từ bằng đích ngay sau lần bấm), `still wrong`.
- `--learn`: bộ luật trong tiến trình với ngưỡng của spec §12.2.
  - Luật có ngữ cảnh (từ đứng trước không rỗng) áp dụng sau 1 sự kiện, không ngữ cảnh sau 2 sự kiện cùng chữ.
  - Hoàn tác ngược xoá luật của chữ đó và chặn tới khi có thêm 2 sự kiện cùng loại.
  - Hai bảng `keep` và `convert` riêng; ghi một loại cho (từ đứng trước, chữ) thì xoá loại kia.
  - Nuôi bằng `lk_vikey_take_undo` sau mỗi lần bấm; trả lời cả bộ lọc `keep` (`lk_vikey_set_fix_filter`) lẫn bộ lọc `convert`. Luật `convert` khoá theo **phím thô và chiều** (Ruling 5): `toTelex` khi học trên từ đang hiện đúng phím thô, `toRaw` khi học trên dạng Telex. Luật chỉ chạy khi từ ở phím ngắt đang hiện đúng dạng "từ" của luật; hoàn tác ngược chỉ xoá luật cùng chiều của chữ đó.
  - Cùng `--convert-wrong` thì in số lần bấm ⌃⌫ mỗi 500 tin.

```sh
cd tools/mixbench   # from the repository root; lk, mine.tsv, chat.tsv built as above
for c in mine chat; do for o in "" "--chain --end return-fix" "--end return" "--chain --end return"; do
  echo "== $c $o"
  ./lk ${=o} < $c.tsv > $c.out;                         python3 -I score.py $c.tsv $c.out "sạch"
  ./lk ${=o} --convert-wrong < $c.tsv > $c.out;         python3 -I score.py $c.tsv $c.out "--convert-wrong"
  ./lk ${=o} --convert-wrong --learn < $c.tsv > $c.out; python3 -I score.py $c.tsv $c.out "--convert-wrong --learn"
done; done
```

### Kết quả (LeanKeys 1.10, Vikey v1.0.34 `79547aa`)

Số từ ra sai (tỉ lệ). Mỗi ô là một lần chạy cả kho.

| Cấu hình | mine.txt sạch | mine `--convert-wrong` | chat sạch | chat `--convert-wrong` | chat `--convert-wrong --learn` |
|---|---|---|---|---|---|
| Space, mỗi câu reset | 1 (0.23%) | 1 (0.23%), 0 lần bấm | 41 (0.20%) | **13 (0.06%)** | 13 (0.06%) |
| `--chain --end return-fix` | 1 (0.23%) | 1 (0.23%), 0 lần bấm | 42 (0.20%) | **16 (0.08%)** | 16 (0.08%) |
| `--end return` | 6 (1.37%) | **1 (0.23%)**, 5/5 sửa được | 169 (0.82%) | **14 (0.07%)** | 14 (0.07%) |
| `--chain --end return` | 6 (1.37%) | **1 (0.23%)** | 169 (0.82%) | **14 (0.07%)** | 14 (0.07%) |

Số lần bấm ⌃⌫ trên chat (tổng, trong ngoặc: sửa được / còn sai sau khi bấm):

| Cấu hình | `--convert-wrong` | `--convert-wrong --learn` |
|---|---|---|
| Space, mỗi câu reset | 52 (46 / 6) | **41** (35 / 6) |
| `--chain --end return-fix` | 50 (45 / 5) | **40** (35 / 5) |
| `--end return` | 177 (171 / 6) | **167** (161 / 6) |
| `--chain --end return` | 179 (173 / 6) | **168** (162 / 6) |

Số lần bấm theo từng khối 500 tin với `--learn` (chat, 1.869 tin, khối cuối 369 tin):

| Cấu hình | Số lần bấm mỗi khối |
|---|---|
| Space | 9 · 14 · 8 · 10 |
| `--chain --end return-fix` | 9 · 12 · 8 · 11 |
| `--end return` | 48 · 39 · 45 · 35 |

mine.txt: 0 lần bấm (Space, return-fix) hoặc 5 lần (`--end return`), học không đổi gì (5 sự kiện, không luật nào áp dụng).

- **⌃⌫ xoá gần hết lỗi còn lại và không làm hỏng từ nào.** So từng từ với bản sạch cùng cấu hình: chat Space có 28 từ sai thành đúng, 0 từ đúng thành sai, 13 từ vẫn sai. Chat `--end return`: 155 sai thành đúng, 0 đúng thành sai.
  - Chat Return: từ cuối không được chốt là lỗi lớn nhất (169 từ sai). ⌃⌫ kéo về 14, ngang mức Space.
  - Số từ sai khi bật `--convert-wrong` **không** bằng số từ sai của bản sạch trừ số lần sửa được (41 − 46 < 0). Vikey tự sửa 18 trong 46 từ đó về sau: chúng trông sai ở phím ngắt nhưng đúng khi gõ xong, nên bản sạch đã tính chúng là đúng. Người gõ thật cũng sẽ bấm ở các từ đó. 28 + 13 = 41: 28 từ sai thành đúng, 13 từ vẫn sai.
- **13 từ vẫn sai trên chat Space.**
  - 6 từ đã bấm mà ⌃⌫ không dựng lại được: chữ ngoài từ điển Telex thường (`pâté`, `Mbappé`, `Lumière`, `bthường`, `tượo`).
  - 7 từ không bấm vì phép đo không thấy chúng sai ở một phím ngắt: từ nối bằng `-` hoặc `/` (`air-con`), hoặc Vikey đổi từ **sau** phím ngắt, khi từ kế tiếp được gõ (`Bên marketing` ra `Been marketing` trên mine.txt, 1 từ).
- **Bộ học giảm số lần bấm, nhưng ít: 52 xuống 41 (-21%) trên Space, 177 xuống 167 (-6%) trên `--end return`.** Số từ sai cuối cùng không đổi (13 / 14 / 16).
  - Nhỏ vì chat_messages hầu như không lặp lại một cặp (từ đứng trước, chữ): luật có ngữ cảnh ít khi gặp lại, luật không ngữ cảnh cần 2 sự kiện cùng chữ. Mỗi khối 500 tin vẫn bấm 8–14 lần (Space), 35–48 lần (Return), chỉ dốc xuống nhẹ. Người gõ thật lặp lại cùng từ nhiều hơn, nhưng bộ đo này không cho thấy điều đó.
  - Luật mang chiều (Ruling 5), nên luật học từ một chiều không chạy khi Vikey để chữ ở chiều ngược lại (`last` lát/last, `cos`, `nos`, `this`): chỉ còn 1 lần huỷ một luật trên cả chat.
- **Giới hạn:**
  - Người gõ lý tưởng: nhìn đúng chỗ, bấm đúng một lần, không bấm nhầm, không dùng ⌫⌫. Cả chat chỉ có 1 sự kiện `keep`.
  - Không có thời gian giữa các phím.
  - `mine.txt` chỉ có 5 lần bấm nên không nói được gì về bộ học.
