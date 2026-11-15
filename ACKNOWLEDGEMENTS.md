# Ghi công

LeanKeys được xây trên ba dự án mã nguồn mở dưới đây. Cảm ơn các tác giả và cộng đồng của họ.

| Dự án | Tác giả | Repo | Giấy phép | Phiên bản dùng |
| --- | --- | --- | --- | --- |
| Gõ Nhanh | khaphanspace và cộng đồng Gõ Nhanh | https://github.com/khaphanspace/gonhanh.org | BSD-3-Clause | v1.0.165 |
| Vikey | Tony Dinh | https://github.com/tonyminibot/Vikey | GPL-3.0 | v1.0.33 |
| OpenKey | Mai Vũ Tuyên | https://github.com/tuyenvm/OpenKey | GPL-3.0 | (qua Vikey) |

## Gõ Nhanh

Nền tảng của LeanKeys: ứng dụng macOS, giao diện, cài đặt, cập nhật và engine gõ mặc định (lõi Rust trong `core/`). LeanKeys là bản fork của Gõ Nhanh; mã gốc giữ nguyên, mọi chỗ sửa được đánh dấu `LEANKEYS-HOOK` và liệt kê trong `sync/hooks.txt`. Danh sách người đóng góp của Gõ Nhanh nằm trong `CONTRIBUTORS.md`.

Gõ Nhanh phát hành theo giấy phép BSD-3-Clause (bản gốc tại `LICENSES/gonhanh-BSD-3.txt`), trích nguyên văn:

```
BSD 3-Clause License

Copyright (c) 2025, Gõ Nhanh Contributors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Vikey

Engine Vikey (C++, trong `vendor/vikey`, không sửa), chọn được trong Cài đặt: tự chuyển Việt/Anh theo ngữ cảnh. Tác giả Tony Dinh, phát hành theo GPL-3.0 (`vendor/vikey/LICENSE`). Engine của Vikey có dùng thống kê từ nhiều bộ dữ liệu; nguồn và giấy phép của chúng được liệt kê trong `vendor/vikey/ACKNOWLEDGEMENTS.md`.

## OpenKey

Vikey phát triển từ engine của OpenKey, tác giả Mai Vũ Tuyên, phát hành theo GPL-3.0.

## LeanKeys

LeanKeys phát hành theo GPL-3.0 (`LICENSE`). Tên, icon và bundle ID (`io.github.anlvdt.leankeys`) là của riêng LeanKeys; LeanKeys không dùng tên hay logo của ba dự án trên làm thương hiệu.
