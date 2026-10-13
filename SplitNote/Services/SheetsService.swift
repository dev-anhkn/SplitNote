//
//  SheetsService.swift
//  SplitNote
//

import Foundation

enum SheetsServiceError: Error, LocalizedError {
    case invalidResponse
    case requestFailed(String)
    /// Mất spreadsheet hoặc tab — tách riêng để nơi gọi xử lý (gỡ khỏi cache, đề nghị tạo lại).
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Google Sheets trả về phản hồi không hợp lệ."
        case .requestFailed(let message):
            return message
        case .notFound:
            return "Sheet này không còn tồn tại (có thể đã bị xoá)."
        }
    }
}

struct CreatedSpreadsheet {
    let spreadsheetId: String
    let url: URL
}

protocol SheetsServiceProtocol {
    /// `members` chỉ khác rỗng với `.family` — dùng để dựng sẵn cột gia đình/bảng cân đối.
    func createSpreadsheet(title: String, firstTabTitle: String, members: [String]) async throws -> CreatedSpreadsheet
    /// Idempotent: tạo hoặc migrate tab rồi làm mới cột gia đình — gọi mỗi lần mở app vẫn an toàn.
    func ensureTab(spreadsheetId: String, tabTitle: String) async throws
    /// `paidBy`/`sharedWith` nil với workspace `.personal` (để trống cột gia đình).
    func appendRow(spreadsheetId: String, tabTitle: String, date: String, category: String, content: String, amount: String, paidBy: String?, sharedWith: String?) async throws
    /// Ném `.notFound` nếu không còn spreadsheet hoặc tab.
    func fetchRows(spreadsheetId: String, tabTitle: String) async throws -> [ExpenseEntry]
    /// `date` nil giữ nguyên ô Ngày; `paidBy`/`sharedWith` nil với `.personal`.
    func updateRow(spreadsheetId: String, tabTitle: String, rowIndex: Int, date: String?, category: String, content: String, amount: String, paidBy: String?, sharedWith: String?) async throws
    /// Xoá trắng ô thay vì xoá hàng để `rowIndex` của hàng khác không bị lệch.
    func deleteRow(spreadsheetId: String, tabTitle: String, rowIndex: Int) async throws
    /// 1 request cho mọi tháng — mỗi ô đã là công thức trỏ vào tab tháng tương ứng.
    func fetchMonthlyTotals(spreadsheetId: String) async throws -> [(tabTitle: String, total: Decimal)]
    /// Chỉ trả về loại chi có tổng khác 0.
    func fetchCategoryTotals(spreadsheetId: String, tabTitle: String) async throws -> [(category: String, total: Decimal)]
    /// Đọc từ chính sheet (không cache theo thiết bị) để mọi thiết bị thấy cùng danh sách.
    func fetchMembers(spreadsheetId: String) async throws -> [String]
    /// Email được cấp quyền Drive của từng thành viên, cùng thứ tự với `fetchMembers`.
    func fetchMemberEmails(spreadsheetId: String) async throws -> [String]
    /// Ghi tên + email trong 1 request; nơi gọi phải gọi `ensureTab` sau đó để làm mới khối gia đình.
    func setMemberList(spreadsheetId: String, names: [String], emails: [String]) async throws
}

/// Facade mỏng cho Google Sheets API — mỗi nhóm việc giao cho 1 service con riêng.
struct SheetsService: SheetsServiceProtocol {
    private let setup: SheetsSpreadsheetSetupService
    private let rows: SheetsRowService
    private let summary: SheetsSummaryService
    private let members: SheetsMembersService

    nonisolated init() {
        let summary = SheetsSummaryService()
        let members = SheetsMembersService()
        self.summary = summary
        self.members = members
        self.setup = SheetsSpreadsheetSetupService(summaryService: summary, membersService: members, migrationService: SheetsLegacyMigrationService())
        self.rows = SheetsRowService()
    }

    func createSpreadsheet(title: String, firstTabTitle: String, members: [String]) async throws -> CreatedSpreadsheet {
        try await setup.createSpreadsheet(title: title, firstTabTitle: firstTabTitle, members: members)
    }

    func ensureTab(spreadsheetId: String, tabTitle: String) async throws {
        try await setup.ensureTab(spreadsheetId: spreadsheetId, tabTitle: tabTitle)
    }

    func appendRow(spreadsheetId: String, tabTitle: String, date: String, category: String, content: String, amount: String, paidBy: String?, sharedWith: String?) async throws {
        try await rows.appendRow(spreadsheetId: spreadsheetId, tabTitle: tabTitle, date: date, category: category, content: content, amount: amount, paidBy: paidBy, sharedWith: sharedWith)
    }

    func fetchRows(spreadsheetId: String, tabTitle: String) async throws -> [ExpenseEntry] {
        try await rows.fetchRows(spreadsheetId: spreadsheetId, tabTitle: tabTitle)
    }

    func updateRow(spreadsheetId: String, tabTitle: String, rowIndex: Int, date: String?, category: String, content: String, amount: String, paidBy: String?, sharedWith: String?) async throws {
        try await rows.updateRow(spreadsheetId: spreadsheetId, tabTitle: tabTitle, rowIndex: rowIndex, date: date, category: category, content: content, amount: amount, paidBy: paidBy, sharedWith: sharedWith)
    }

    func deleteRow(spreadsheetId: String, tabTitle: String, rowIndex: Int) async throws {
        try await rows.deleteRow(spreadsheetId: spreadsheetId, tabTitle: tabTitle, rowIndex: rowIndex)
    }

    func fetchMonthlyTotals(spreadsheetId: String) async throws -> [(tabTitle: String, total: Decimal)] {
        try await summary.fetchMonthlyTotals(spreadsheetId: spreadsheetId)
    }

    func fetchCategoryTotals(spreadsheetId: String, tabTitle: String) async throws -> [(category: String, total: Decimal)] {
        try await summary.fetchCategoryTotals(spreadsheetId: spreadsheetId, tabTitle: tabTitle)
    }

    func fetchMembers(spreadsheetId: String) async throws -> [String] {
        try await members.fetchMembers(spreadsheetId: spreadsheetId)
    }

    func fetchMemberEmails(spreadsheetId: String) async throws -> [String] {
        try await members.fetchMemberEmails(spreadsheetId: spreadsheetId)
    }

    func setMemberList(spreadsheetId: String, names: [String], emails: [String]) async throws {
        try await members.setMemberList(spreadsheetId: spreadsheetId, names: names, emails: emails)
    }
}
