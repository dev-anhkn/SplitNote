//
//  SheetsRowService.swift
//  SplitNote
//

import Foundation

/// Thêm/đọc/sửa/xoá khoản chi trong 1 tab tháng (A:D) và cột gia đình đi kèm (H:J).
struct SheetsRowService {
    nonisolated init() {}

    func appendRow(spreadsheetId: String, tabTitle: String, date: String, category: String, content: String, amount: String, paidBy: String?, sharedWith: String?) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        // 1. Tìm hàng trống kế tiếp — không dùng values.append vì nó có thể ghi đè hàng đã xoá trắng ở giữa.
        let row = try await nextRowIndex(spreadsheetId: spreadsheetId, tabTitle: tabTitle, accessToken: accessToken)
        // 2. Ghi A:D.
        try await SheetsHTTP.writeValues(spreadsheetId: spreadsheetId, tabTitle: tabTitle, range: "A\(row):D\(row)", values: [[date, category, content, amount]], accessToken: accessToken)
        // 3. Workspace gia đình thì ghi thêm H:J.
        guard let paidBy, let sharedWith else { return }
        try await writeFamilyRow(spreadsheetId: spreadsheetId, tabTitle: tabTitle, row: row, paidBy: paidBy, sharedWith: sharedWith, accessToken: accessToken)
    }

    /// Đọc dạng `FORMATTED_VALUE` (mặc định) để ô ngày trả về đúng như hiển thị, khỏi đổi số serial.
    func fetchRows(spreadsheetId: String, tabTitle: String) async throws -> [ExpenseEntry] {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        // Đọc tới J để lấy luôn Ai chi (H)/Chi cho ai (I).
        let rows = try await SheetsHTTP.readValues(spreadsheetId: spreadsheetId, tabTitle: tabTitle, range: "A2:J\(SheetsLayout.maxDataRow)", accessToken: accessToken)
        return rows.enumerated().compactMap { offset, row in
            Self.entry(from: row, rowIndex: offset + 2)
        }
    }

    /// `date` nil thì chỉ ghi B:D, không đụng ô Ngày.
    func updateRow(spreadsheetId: String, tabTitle: String, rowIndex: Int, date: String?, category: String, content: String, amount: String, paidBy: String?, sharedWith: String?) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        // 1. Ghi đè đúng hàng `rowIndex`.
        let firstColumn = date == nil ? "B" : "A"
        let values = [date, category, content, amount].compactMap { $0 }
        try await SheetsHTTP.writeValues(spreadsheetId: spreadsheetId, tabTitle: tabTitle, range: "\(firstColumn)\(rowIndex):D\(rowIndex)", values: [values], accessToken: accessToken)
        // 2. Workspace gia đình thì ghi lại H:J.
        guard let paidBy, let sharedWith else { return }
        try await writeFamilyRow(spreadsheetId: spreadsheetId, tabTitle: tabTitle, row: rowIndex, paidBy: paidBy, sharedWith: sharedWith, accessToken: accessToken)
    }

    /// Xoá trắng thay vì xoá hàng — xoá hàng sẽ dịch các hàng dưới, lệch `rowIndex` và công thức Tổng cộng.
    func deleteRow(spreadsheetId: String, tabTitle: String, rowIndex: Int) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        // 1. Xoá trắng A:D — `fetchRows` sẽ tự bỏ qua hàng này.
        try await SheetsHTTP.clearValues(spreadsheetId: spreadsheetId, tabTitle: tabTitle, range: "A\(rowIndex):D\(rowIndex)", accessToken: accessToken)
        // 2. Xoá luôn H:J — vô hại với tab cá nhân vì ở đó không có gì.
        try await SheetsHTTP.clearValues(spreadsheetId: spreadsheetId, tabTitle: tabTitle, range: "H\(rowIndex):J\(rowIndex)", accessToken: accessToken)
    }

    /// Ghi H:J của 1 hàng; J luôn là công thức đếm tên trong I nên tự đúng khi sửa người chia.
    private func writeFamilyRow(spreadsheetId: String, tabTitle: String, row: Int, paidBy: String, sharedWith: String, accessToken: String) async throws {
        let countFormula = "=IF(I\(row)=\"\",0,LEN(I\(row))-LEN(SUBSTITUTE(I\(row),\",\",\"\"))+1)"
        try await SheetsHTTP.writeValues(spreadsheetId: spreadsheetId, tabTitle: tabTitle, range: "H\(row):J\(row)", values: [[paidBy, sharedWith, countFormula]], accessToken: accessToken)
    }

    /// Hàng ngay sau hàng cuối còn dữ liệu ở A:D — bỏ qua chỗ trống do `deleteRow` để lại, không dùng lại.
    private func nextRowIndex(spreadsheetId: String, tabTitle: String, accessToken: String) async throws -> Int {
        let rows = try await SheetsHTTP.readValues(spreadsheetId: spreadsheetId, tabTitle: tabTitle, range: "A2:D\(SheetsLayout.maxDataRow)", accessToken: accessToken)
        let lastUsedRow = rows.lastIndex { !$0.allSatisfy(\.isEmpty) }.map { $0 + 2 } ?? 1
        return lastUsedRow + 1
    }

    /// Hàng không có số tiền hợp lệ (vd đã xoá trắng) thì bỏ qua.
    private static func entry(from row: [String], rowIndex: Int) -> ExpenseEntry? {
        guard let amount = SheetsHTTP.parseAmount(SheetsHTTP.cell(row, 3)) else { return nil }
        return ExpenseEntry(
            rowIndex: rowIndex,
            date: SheetsHTTP.cell(row, 0),
            category: SheetsHTTP.cell(row, 1),
            content: SheetsHTTP.cell(row, 2),
            amount: amount,
            paidBy: SheetsHTTP.cell(row, 7),
            sharedWith: SheetsHTTP.cell(row, 8)
        )
    }
}
