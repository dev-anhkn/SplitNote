//
//  SheetsService.swift
//  SplitNote
//

import Foundation

enum SheetsServiceError: Error, LocalizedError {
    case invalidResponse
    case requestFailed(String)
    /// The spreadsheet itself is gone (deleted/moved) — HTTP 404. Distinct
    /// from `requestFailed` so callers can react (e.g. drop it from a cached list)
    /// instead of just surfacing raw API error text.
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Google Sheets returned an unexpected response."
        case .requestFailed(let message):
            return message
        case .notFound:
            return "This sheet no longer exists (it may have been deleted)."
        }
    }
}

struct CreatedSpreadsheet {
    let spreadsheetId: String
    let url: URL
}

protocol SheetsServiceProtocol {
    /// `members` non-empty only for `.family` — seeds the family columns/balance table; `[]` for `.personal`.
    func createSpreadsheet(title: String, firstTabTitle: String, members: [String]) async throws -> CreatedSpreadsheet
    /// Idempotent: creates or migrates `tabTitle` and refreshes its family columns from current members. Safe on every app launch.
    func ensureTab(spreadsheetId: String, tabTitle: String) async throws
    /// `paidBy`/`sharedWith` nil for a `.personal` workspace (columns left blank).
    func appendRow(spreadsheetId: String, tabTitle: String, date: String, category: String, content: String, amount: String, paidBy: String?, sharedWith: String?) async throws
    /// Throws `.notFound` if the spreadsheet or the tab itself doesn't exist.
    func fetchRows(spreadsheetId: String, tabTitle: String) async throws -> [ExpenseEntry]
    /// Leaves date and raw note untouched; `paidBy`/`sharedWith` nil for `.personal`.
    func updateRow(spreadsheetId: String, tabTitle: String, rowIndex: Int, category: String, content: String, amount: String, paidBy: String?, sharedWith: String?) async throws
    /// Clears cells instead of deleting the row, so other rows' `rowIndex` stay stable.
    func deleteRow(spreadsheetId: String, tabTitle: String, rowIndex: Int) async throws
    /// One request for every month shown — each cell is already a formula referencing its own tab.
    func fetchMonthlyTotals(spreadsheetId: String) async throws -> [(tabTitle: String, total: Decimal)]
    /// Only categories with a non-zero total are returned.
    func fetchCategoryTotals(spreadsheetId: String, tabTitle: String) async throws -> [(category: String, total: Decimal)]
    /// Source of truth is the sheet itself, not a per-device cache, so every device sees the same list.
    func fetchMembers(spreadsheetId: String) async throws -> [String]
    /// Callers must call `ensureTab` afterwards to refresh the currently open tab's family block.
    func setMembers(spreadsheetId: String, members: [String]) async throws
    /// The Google account (if any) granted Drive access for each member, same row order as `fetchMembers`.
    func fetchMemberEmails(spreadsheetId: String) async throws -> [String]
    func setMemberEmails(spreadsheetId: String, emails: [String]) async throws
}

/// Talks to the Google Sheets API using the access token of the currently
/// signed-in `GIDGoogleUser`. Requires the `sheetsScope` requested in
/// `GoogleAuthService.performSignIn()`. A thin facade — each concern is
/// delegated to its own collaborator: `SheetsSpreadsheetSetupService`,
/// `SheetsRowService`, `SheetsSummaryService`, `SheetsMembersService`.
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
        self.setup = SheetsSpreadsheetSetupService(summaryService: summary, membersService: members)
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

    func updateRow(spreadsheetId: String, tabTitle: String, rowIndex: Int, category: String, content: String, amount: String, paidBy: String?, sharedWith: String?) async throws {
        try await rows.updateRow(spreadsheetId: spreadsheetId, tabTitle: tabTitle, rowIndex: rowIndex, category: category, content: content, amount: amount, paidBy: paidBy, sharedWith: sharedWith)
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

    func setMembers(spreadsheetId: String, members: [String]) async throws {
        try await self.members.setMembers(spreadsheetId: spreadsheetId, members: members)
    }

    func fetchMemberEmails(spreadsheetId: String) async throws -> [String] {
        try await members.fetchMemberEmails(spreadsheetId: spreadsheetId)
    }

    func setMemberEmails(spreadsheetId: String, emails: [String]) async throws {
        try await members.setMemberEmails(spreadsheetId: spreadsheetId, emails: emails)
    }
}
