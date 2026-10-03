# SplitNote

Ứng dụng iOS ghi chi tiêu bằng **note dạng văn bản tự nhiên** — gõ một dòng, tự động parse ra số tiền, danh mục, và cách chia — rồi lưu vào **Google Sheets** của chính bạn (mỗi workspace là một spreadsheet, mỗi tháng là một tab).

## Tính năng

- **Quick Add bằng note** — gõ kiểu `"Ăn trưa 300k /3"` hoặc `"Cafe 90k @Lan,Hoa /trừ Minh"`, app tự parse số tiền (hỗ trợ hậu tố `k`/`tr`), danh sách người tham gia (`@Tên1,Tên2`), chia đều (`/N`), và loại trừ người (`/trừ Tên`).
- **Workspace Cá nhân & Gia đình** — mỗi loại workspace map với một Google Sheet riêng, tháng mới tự thêm tab mới.
- **Danh mục chi tiêu cố định** (Ăn uống, Điện nước, Mua sắm, Di chuyển, ...) — được enforce bằng data validation ngay trên Google Sheet để dữ liệu nhất quán, dễ pivot/tổng hợp về sau.
- **Thống kê theo danh mục & so sánh theo tháng** — biểu đồ "Theo loại tháng này" và so sánh chi tiêu giữa các tháng.
- **Quản lý thành viên gia đình** — thêm/xoá thành viên tham gia chia chi phí trong workspace Gia đình.
- **Đăng nhập bằng Google** — dữ liệu là Google Sheet thật trong Drive của bạn, không có backend riêng, bạn toàn quyền sở hữu dữ liệu.

## Kiến trúc

SwiftUI + MVVM, không phụ thuộc backend — toàn bộ dữ liệu đọc/ghi trực tiếp qua Google Sheets & Drive API.

```
SplitNote/
├── Models/           Domain models (ExpenseEntry, ExpenseCategory, ParsedNote, WorkspaceType, ...)
├── Services/          Google Sign-In, Drive, Sheets (HTTP, layout, setup, rows, summary) và NoteParserService
├── ViewModels/         Một ViewModel cho mỗi màn hình chính
├── Views/             SwiftUI views (Login, WorkspaceList, ExpenseList, QuickAddExpense, CategoryBreakdown, MonthComparison, FamilyMembers)
└── Extensions/         Tiện ích dùng chung (Decimal+VND, View+DestructiveRowAction)
```

- `NoteParserService` — parser cho cú pháp note (xem docstring trong file để biết đầy đủ các marker).
- `SheetsService` và các service `Sheets*` — tạo/đọc/ghi spreadsheet qua Google Sheets API, mỗi service phụ trách một nhóm trách nhiệm riêng (setup, layout, rows, summary, members).
- `WorkspaceStore` — quản lý ánh xạ workspace ↔ spreadsheet ID.

## Yêu cầu

- Xcode 15+
- iOS 17+ (SwiftUI)
- Tài khoản Google (để đăng nhập và chứa Google Sheet dữ liệu)
- Google Sign-In SDK (đã cấu hình OAuth client ID trong `SplitNoteApp.swift`)

## Chạy dự án

```bash
open SplitNote.xcodeproj
```

Build & run bằng Xcode (⌘R). Lần đầu mở app, đăng nhập bằng Google — app sẽ tự tạo/khám phá spreadsheet tương ứng với workspace bạn chọn.

## Quy ước code

Xem [CLAUDE.md](CLAUDE.md) — flatten code bằng `guard`, comment ngắn 1 dòng, đánh số bước `// 1. // 2.` cho hàm nhiều bước tuần tự, tuân theo SRP.
