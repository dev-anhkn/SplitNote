//
//  FakeSheetsService.swift
//  SplitNoteTests
//

import Foundation
@testable import SplitNote

/// `SheetsServiceProtocol` giả: trả dữ liệu dựng sẵn, ghi lại lời gọi, có thể ép lỗi.
final class FakeSheetsService: SheetsServiceProtocol {
    var rows: [ExpenseEntry] = []
    var fetchRowsError: Error?
    var setMemberListError: Error?
    private(set) var savedMemberLists: [(names: [String], emails: [String])] = []

    func createSpreadsheet(title: String, firstTabTitle: String, members: [String]) async throws -> CreatedSpreadsheet {
        CreatedSpreadsheet(spreadsheetId: "fake", url: URL(string: "https://example.com")!)
    }

    func ensureTab(spreadsheetId: String, tabTitle: String) async throws {}

    func appendRow(spreadsheetId: String, tabTitle: String, date: String, category: String, content: String, amount: String, paidBy: String?, sharedWith: String?) async throws {}

    func fetchRows(spreadsheetId: String, tabTitle: String) async throws -> [ExpenseEntry] {
        if let fetchRowsError { throw fetchRowsError }
        return rows
    }

    func updateRow(spreadsheetId: String, tabTitle: String, rowIndex: Int, date: String?, category: String, content: String, amount: String, paidBy: String?, sharedWith: String?) async throws {}

    func deleteRow(spreadsheetId: String, tabTitle: String, rowIndex: Int) async throws {}

    func fetchMonthlyTotals(spreadsheetId: String) async throws -> [(tabTitle: String, total: Decimal)] { [] }

    func fetchCategoryTotals(spreadsheetId: String, tabTitle: String) async throws -> [(category: String, total: Decimal)] { [] }

    func fetchMembers(spreadsheetId: String) async throws -> [String] { [] }

    func fetchMemberEmails(spreadsheetId: String) async throws -> [String] { [] }

    func setMemberList(spreadsheetId: String, names: [String], emails: [String]) async throws {
        if let setMemberListError { throw setMemberListError }
        savedMemberLists.append((names, emails))
    }
}

/// `DriveServiceProtocol` giả: ghi lại email được cấp/thu hồi quyền.
final class FakeDriveService: DriveServiceProtocol {
    private(set) var sharedEmails: [String] = []
    private(set) var revokedEmails: [String] = []

    func tagFile(fileId: String, key: String, value: String) async throws {}
    func findFile(key: String, value: String) async throws -> String? { nil }
    func fileExists(fileId: String) async throws -> Bool { true }
    func trashFile(fileId: String) async throws {}
    func fileName(fileId: String) async throws -> String { "" }
    func renameFile(fileId: String, to name: String) async throws {}

    func shareFile(fileId: String, email: String, role: String) async throws {
        sharedEmails.append(email)
    }

    func revokeAccess(fileId: String, email: String) async throws {
        revokedEmails.append(email)
    }
}

struct FakeError: Error {}

extension ExpenseEntry {
    /// Tạo nhanh khoản chi cho test.
    static func fake(row: Int, date: String, category: ExpenseCategory = .food, amount: Decimal, paidBy: String = "", sharedWith: String = "") -> ExpenseEntry {
        ExpenseEntry(rowIndex: row, date: date, category: category.rawValue, content: "Nội dung \(row)", amount: amount, paidBy: paidBy, sharedWith: sharedWith)
    }
}
