//
//  SheetsMembersService.swift
//  SplitNote
//

import Foundation

/// Quản lý danh sách thành viên `.family` trong "Tổng hợp" và cột gia đình/bảng cân đối của từng tab.
struct SheetsMembersService {
    nonisolated init() {}

    func fetchMembers(spreadsheetId: String) async throws -> [String] {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        return try await fetchMembers(spreadsheetId: spreadsheetId, accessToken: accessToken)
    }

    func fetchMemberEmails(spreadsheetId: String) async throws -> [String] {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        return try await fetchMemberEmails(spreadsheetId: spreadsheetId, accessToken: accessToken)
    }

    func setMemberList(spreadsheetId: String, names: [String], emails: [String]) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        try await setMemberList(spreadsheetId: spreadsheetId, names: names, emails: emails, accessToken: accessToken)
    }

    /// Bỏ ô trống — chỉ trả về tên thật.
    func fetchMembers(spreadsheetId: String, accessToken: String) async throws -> [String] {
        try await fetchColumn(spreadsheetId: spreadsheetId, column: SheetsLayout.membersColumn, accessToken: accessToken)
            .compactMap { $0 }
            .filter { !$0.isEmpty }
    }

    /// Giữ đúng thứ tự hàng với `fetchMembers`, "" nếu thành viên chưa gắn email.
    func fetchMemberEmails(spreadsheetId: String, accessToken: String) async throws -> [String] {
        try await fetchColumn(spreadsheetId: spreadsheetId, column: SheetsLayout.memberEmailsColumn, accessToken: accessToken)
            .map { $0 ?? "" }
    }

    /// Ghi tên + email trong 1 request để 2 cột không bao giờ lệch nhau, kể cả khi lỗi giữa chừng.
    func setMemberList(spreadsheetId: String, names: [String], emails: [String], accessToken: String) async throws {
        let lastRow = SheetsLayout.maxMemberRow
        let namesColumn = SheetsLayout.membersColumn
        let emailsColumn = SheetsLayout.memberEmailsColumn
        try await SheetsHTTP.batchWriteValues(spreadsheetId: spreadsheetId, ranges: [
            (SheetsHTTP.bodyRange(tabTitle: SheetsLayout.summaryTabTitle, cells: "\(namesColumn)1:\(namesColumn)\(lastRow)"), Self.paddedColumn(header: SheetsLayout.membersHeaderLabel, values: names)),
            (SheetsHTTP.bodyRange(tabTitle: SheetsLayout.summaryTabTitle, cells: "\(emailsColumn)1:\(emailsColumn)\(lastRow)"), Self.paddedColumn(header: SheetsLayout.memberEmailsHeaderLabel, values: emails))
        ], accessToken: accessToken)
    }

    /// Ghi lại toàn bộ khối gia đình của 1 tab — công thức không có tiền tố tên tab nên vẫn đúng sau `duplicateSheet`.
    func writeFamilyBlocks(spreadsheetId: String, tabTitle: String, sheetId: Int, members: [String], accessToken: String) async throws {
        // 1. Ghi tiêu đề H1:J1 (gia đình) + L1:O1 (bảng cân đối).
        try await SheetsHTTP.batchWriteValues(spreadsheetId: spreadsheetId, ranges: SheetsRequests.familyHeaders(tabTitle: tabTitle), accessToken: accessToken)
        // 2. Gợi ý thành viên làm dropdown cho cột "Ai chi".
        try await SheetsHTTP.batchUpdate(spreadsheetId: spreadsheetId, requests: [SheetsRequests.memberValidation(sheetId: sheetId, members: members)], accessToken: accessToken)
        // 3. Xoá bảng cân đối cũ — đơn giản hơn diff xem thành viên nào bị bớt.
        try await SheetsHTTP.clearValues(spreadsheetId: spreadsheetId, tabTitle: tabTitle, range: "L2:O\(SheetsLayout.maxMemberRow)", accessToken: accessToken)
        // 4. Ghi lại bảng cân đối theo danh sách hiện tại.
        let balanceRows = members.enumerated().map { offset, member in Self.balanceRow(for: member, row: offset + 2) }
        try await SheetsHTTP.writeValues(spreadsheetId: spreadsheetId, tabTitle: tabTitle, range: "L2:O\(members.count + 1)", values: balanceRows, accessToken: accessToken)
    }

    /// Đọc 1 cột của "Tổng hợp" theo đúng thứ tự hàng (`nil` = ô trống); chưa có tab thì coi như rỗng.
    private func fetchColumn(spreadsheetId: String, column: String, accessToken: String) async throws -> [String?] {
        do {
            let rows = try await SheetsHTTP.readValues(spreadsheetId: spreadsheetId, tabTitle: SheetsLayout.summaryTabTitle, range: "\(column)2:\(column)\(SheetsLayout.maxMemberRow)", accessToken: accessToken)
            return rows.map(\.first)
        } catch SheetsServiceError.notFound {
            return []
        }
    }

    /// Tiêu đề + giá trị, điền "" tới hết vùng để ghi đè (xoá) phần thừa của danh sách cũ.
    private static func paddedColumn(header: String, values: [String]) -> [[String]] {
        let cells = [header] + values
        let padding = Array(repeating: "", count: max(0, SheetsLayout.maxMemberRow - cells.count))
        return (cells + padding).map { [$0] }
    }

    /// [Người, Đã chi, Phải chi, Chênh lệch] của 1 thành viên trên hàng `row`.
    private static func balanceRow(for member: String, row: Int) -> [String] {
        // Nhân đôi dấu ngoặc kép phòng tên có chứa ".
        let escaped = member.replacingOccurrences(of: "\"", with: "\"\"")
        let lastRow = SheetsLayout.maxDataRow
        return [
            member,
            "=SUMIF(H:H,\"\(escaped)\",D:D)",
            "=SUMPRODUCT(ISNUMBER(SEARCH(\",\"&\"\(escaped)\"&\",\",\",\"&I2:I\(lastRow)&\",\"))*IFERROR(D2:D\(lastRow)/J2:J\(lastRow),0))",
            "=M\(row)-N\(row)"
        ]
    }
}
