//
//  SheetsLayout.swift
//  SplitNote
//

import Foundation

/// Bố cục cột/tab dùng chung để mọi service Sheets thống nhất dữ liệu nằm ở đâu.
enum SheetsLayout {
    // MARK: - Giới hạn hàng

    /// Hàng cuối được đọc/cộng trong 1 tab tháng.
    static let maxDataRow = 10000
    /// Hàng cuối được đọc trong tab "Tổng hợp".
    static let maxSummaryRow = 1000
    /// Hàng cuối của danh sách thành viên/bảng cân đối.
    static let maxMemberRow = 200

    // MARK: - Tab tháng

    /// Cột A-D của mỗi tab tháng; "Tổng cộng" đặt cách 1 cột trống phía sau.
    static let headerColumns = ["Ngày", "Loại", "Nội dung", "Số tiền"]
    static let totalLabel = "Tổng cộng"
    static let totalFormula = "=SUM(D2:D\(maxDataRow))"
    /// Cột chứa `totalFormula` (F) — sau `headerColumns` 1 cột trống.
    static let totalColumn = SheetsHTTP.columnLetter(headerColumns.count + 2)
    static let categoryValues = ExpenseCategory.allCases.map(\.rawValue)

    /// Cột gia đình H-J, sau cụm "Tổng cộng" để không đụng cột A-D của workspace cá nhân.
    static let familyHeaderColumns = ["Ai chi", "Chi cho ai", "Số người chia"]
    /// Bảng cân đối L-O, tách xa cột gia đình cho dễ nhìn.
    static let balanceHeaderColumns = ["Người", "Đã chi (ứng trước)", "Phải chi (chia đều)", "Chênh lệch"]

    /// Tab ẩn làm mẫu cho `duplicateSheet` — mọi tab tháng đều nhân bản từ đây nên không bao giờ lệch nhau.
    static let templateTabTitle = "_Mẫu"

    // MARK: - Tab "Tổng hợp"

    /// Tab ghim đầu, mỗi tháng 1 hàng công thức trỏ thẳng vào tab tháng đó nên không bao giờ phải ghi lại.
    static let summaryTabTitle = "Tổng hợp"
    static let summaryHeaderColumns = ["Tháng", "Tổng cộng"] + categoryValues
    static let lastSummaryColumn = SheetsHTTP.columnLetter(summaryHeaderColumns.count)
    /// Cột danh sách thành viên, cách cột loại chi cuối 1 cột trống.
    static let membersColumn = SheetsHTTP.columnLetter(summaryHeaderColumns.count + 2)
    static let membersHeaderLabel = "Thành viên"
    /// Email được cấp quyền Drive của từng thành viên, cùng thứ tự hàng với `membersColumn`.
    static let memberEmailsColumn = SheetsHTTP.columnLetter(summaryHeaderColumns.count + 3)
    static let memberEmailsHeaderLabel = "Email"

    // MARK: - Bố cục cũ (chỉ dùng để migrate)

    /// Đọc G1 ("Tổng cộng" cũ) và I1 ("Ai chi" cũ) để nhận diện tab bị lệch 1 cột.
    static let legacyProbeCells = "G1:I1"
    /// Bản cũ đặt "Tổng cộng" ở cột G thay vì F.
    static let legacyTotalCells = "G1:G2"
    /// Bản cũ đặt tiêu đề gia đình/cân đối lệch sang phải 1 cột.
    static let legacyFamilyHeaderCells = ["I1:K1", "M1:P1"]
    /// Bản rất cũ có cột B là "Nội dung" (đổi chỗ với "Loại").
    static let legacySwappedHeaderB = "Nội dung"
}
