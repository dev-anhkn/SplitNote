---
description: Quét code Swift trong project và áp dụng các quy ước clean code trong CLAUDE.md
---

Đọc `CLAUDE.md` ở root project để nắm các quy ước code style hiện tại (chải
phẳng bằng guard, comment ngắn 1 dòng, đánh số bước tuần tự, SRP).

Nếu người dùng truyền tham số (`$ARGUMENTS`), chỉ quét file/thư mục đó.
Nếu không có tham số, quét toàn bộ file `.swift` trong `SplitNote/`.

Với mỗi file:
1. Tìm các đoạn if/else lồng nhau có thể thay bằng `guard let ... else { return }`.
2. Tìm comment nhiều dòng/dài dòng giải thích WHAT thay vì WHY — rút gọn còn 1 dòng, chỉ giữ phần WHY thật sự cần thiết.
3. Tìm hàm có nhiều bước tuần tự (nhiều lệnh gọi hàm khác nhau liên tiếp) chưa có comment đánh số `// 1. ...`, `// 2. ...` — thêm vào nếu hàm đủ dài để cần.
4. Tìm hàm/type vi phạm Single Responsibility Principle (làm nhiều việc không liên quan) — đề xuất tách thành hàm private nhỏ hơn.

Sau khi quét xong toàn bộ, liệt kê danh sách các chỗ vi phạm tìm được (file:line + mô tả ngắn), rồi hỏi xác nhận trước khi áp dụng sửa — không tự ý sửa hàng loạt khi chưa được đồng ý, vì đây là thay đổi trên diện rộng.
