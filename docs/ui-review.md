# Đánh giá giao diện — màn danh sách khoản chi (macOS)

Ngày: 2026-10-03 · Điểm trước khi sửa: **7/10** · Đã sửa cả 7 điểm + đổi tông màu vàng Golden Gate (chờ chạy thử để chấm lại)

Cách dùng: đánh dấu cột **Quyết định** bằng `Làm` / `Bỏ` / `Để sau`, ghi chú thêm nếu cần.

## Điểm đã tốt

- Không còn lặp tên tháng (tiêu đề = tên workspace, tháng nằm trong thẻ).
- Phân cấp rõ: số tổng chi lớn, nổi bật; danh sách dễ đọc.
- Thẻ tổng chi có màu theo workspace (vàng cát = Cá nhân, tím chàm = Gia đình).
- Danh sách xếp theo ngày, mới nhất trên đầu.

## Cần cải thiện

| # | Ưu tiên | Vấn đề | Đề xuất | Quyết định |
|---|---|---|---|---|
| 1 | Cao | Ngày `2026-10-02` lặp lại ở mọi dòng, khô và tốn chỗ | Nhóm khoản chi theo ngày: tiêu đề nhóm "Hôm nay" / "Hôm qua" / "Thứ Năm, 1 thg 10" kèm tổng tiền ngày đó; bỏ ngày khỏi từng dòng | Đã làm |
| 2 | Cao | Nút reload trong thẻ màu cam, lệch tông với thẻ xanh | Đổi sang kiểu trung tính giống nút "Google Sheet", hoặc chỉ để icon nhỏ | Đã làm |
| 3 | Cao | Có 2 nút reload giống hệt nhau trên màn hình (sidebar + thẻ), dù khác chức năng, nên dễ bị hiểu là trùng | Phân biệt kiểu dáng, hoặc gộp reload của thẻ thành icon nhỏ, phím tắt ⌘R vẫn giữ | Đã làm |
| 4 | Trung bình | Tiêu đề "Khoản chi" có nền xám và vạch kẻ dày, trông kiểu macOS cũ, không hợp với thẻ bo tròn | Bỏ nền và vạch kẻ; tự hết nếu làm điểm 1 | Đã làm |
| 5 | Trung bình | Thẻ tổng chi cao, bên phải trống nhiều trên màn hình rộng | Hiện 2–3 loại chi nhiều nhất (vd "Mua sắm 486k · Ăn uống 338k"), hoặc thu gọn chiều cao thẻ | Đã làm |
| 6 | Thấp | Mô tả workspace ở sidebar bị cắt ("Chi tiêu của riêng b...") | Cho xuống 2 dòng hoặc bỏ dòng mô tả | Đã làm |
| 7 | Thấp | Icon loại chi ở từng dòng hơi to (36pt) | Giảm còn ~32pt cho danh sách thoáng hơn | Đã làm |

## Ghi chú

- Mới đánh giá màn danh sách khoản chi trên macOS. Chưa xem: form thêm/sửa khoản chi, màn thống kê, so sánh tháng, quản lý thành viên, và bản iOS.

## Đợt 2 — màn danh sách (sau khi đổi tông vàng)

| # | Ưu tiên | Vấn đề | Cách sửa | Quyết định |
|---|---|---|---|---|
| 8 | Cao | Màu vàng hiện thành cam/nâu: trên macOS `AccentColor` bị màu nhấn hệ thống ghi đè | Màu thương hiệu riêng `GoldenSand` (`AppStyle.gold`) + `.tint` ở gốc app | Đã làm |
| 9 | Trung bình | Loại "Ăn uống" (cam) trùng tông với màu thương hiệu | Đổi "Ăn uống" sang màu san hô | Đã làm |
| 10 | Trung bình | Nền thẻ tổng chi ở dark mode bị đục (vàng mờ trên nền tối thành nâu) | Dark mode pha vàng → tím chàm như wallpaper Golden Gate | Đã làm |
| 11 | Thấp | Khoảng trống lớn giữa thẻ và danh sách | Bỏ lề trên của List, giảm khoảng cách | Đã làm |
| 12 | Trung bình | Không có phím tắt thêm khoản chi trên macOS | ⌘N cho nút + | Đã làm |
| 13 | Trung bình | Sửa/xoá bị ẩn: menu chuột phải chỉ có "Xoá" | Thêm "Sửa" vào menu, làm nổi dòng khi rê chuột | Đã làm |
| 14 | Thấp | Top loại chi trong thẻ chỉ để xem | Bấm vào để lọc danh sách theo loại | Để sau |

## Màn đăng nhập

| # | Ưu tiên | Vấn đề | Cách sửa | Quyết định |
|---|---|---|---|---|
| 15 | Cao | App chưa có icon; logo màn chào giống nút tạm dừng | Icon vàng Golden Gate + biểu đồ tròn (iOS + macOS), màn chào dùng chính icon này | Đã làm |
| 16 | Cao | Câu giới thiệu không đúng: "chỉ bằng một dòng chữ", "tự phân loại" (`NoteParserService` chưa được dùng) | Sửa nội dung cho đúng tính năng hiện có | Đã làm |
| 17 | Trung bình | Logo, nút, icon dùng màu cam hệ thống | Dùng `AppStyle.gold` | Đã làm |
| 18 | Trung bình | Nút Google tự chế (chữ "G" trên nền cam), sai hướng dẫn thương hiệu Google | Nút theo chuẩn Google: logo G chính thức, nền trắng/tối, viền xám | Đã làm |
| 19 | Thấp | Nút đăng nhập bị đẩy xuống sát đáy, tách xa nội dung (macOS) | macOS: nút ngay dưới thẻ tính năng, căn giữa cả khối; iOS giữ ở đáy | Đã làm |
| 20 | Thấp | Thiếu thông tin về dữ liệu | Dòng "Dữ liệu nằm trong Google Drive của bạn — SplitNote không có máy chủ riêng" | Đã làm |

Còn mở:
- App xin quyền `spreadsheets` (đọc/ghi mọi sheet). Nên xem có thu hẹp được về `drive.file` không trước khi phát hành.
- Loại "Nhà ở" màu vàng vẫn gần với màu thương hiệu.
