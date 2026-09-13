# CLAUDE.md

## Code Style

- **Ưu tiên "chải phẳng" (flatten) code, tránh lồng nhiều tầng if/else.**
  Dùng `guard let ... else { return }` để xử lý điều kiện lỗi/không hợp lệ
  ngay đầu hàm, giữ phần thân hàm còn lại chỉ là happy path — không viết
  `if let { if let { ... } }` lồng nhau (pyramid of doom).
  - Theo đúng convention hiện có trong `SheetsService.swift`: mỗi hàm dùng
    `guard` liên tiếp ở đầu, không có if lồng nhau.
  - Nếu một hàm cần quá nhiều `guard` (>5-6) rải rác, ưu tiên tách hàm nhỏ
    hơn thay vì chỉ chải phẳng bằng guard.
  - Dùng optional chaining (`?.`) và `flatMap`/`compactMap` khi phù hợp thay
    vì if-let lồng để truy cập/biến đổi giá trị optional/mảng lồng nhau.

- **Comment ngắn gọn, chỉ 1 dòng.** Không viết đoạn comment dài nhiều dòng;
  chỉ giải thích WHY khi không hiển nhiên, không giải thích WHAT (code đã
  tự nói qua tên biến/hàm).

- **Hàm nhiều bước tuần tự → đánh số comment `// 1. ... // 2. ...`** ngay
  trước mỗi bước, như `SheetsService.createSpreadsheet` đang làm. Giúp dễ
  đọc thứ tự và dễ tách hàm nhỏ hơn khi refactor sau này.

- **Tuân theo Single Responsibility Principle (SRP)** — mỗi hàm/type chỉ nên
  làm một việc, một lý do để thay đổi. Hàm dài làm nhiều việc khác nhau nên
  tách thành các hàm private nhỏ hơn, mỗi hàm một bước/trách nhiệm rõ ràng.
