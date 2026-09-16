//
//  SheetsLayout.swift
//  SplitNote
//

import Foundation

/// Column/tab layout shared by every Sheets collaborator — keeping it in one
/// place is what lets `SheetsSpreadsheetSetupService`, `SheetsRowService`,
/// `SheetsSummaryService` and `SheetsMembersService` agree on where things live.
enum SheetsLayout {
    /// The template every SplitNote tab starts with: the fields a parsed
    /// note maps onto, plus a running total two columns after the last one
    /// so there's a blank spacer column in between.
    static let headerColumns = ["Ngày", "Loại", "Nội dung", "Số tiền"]
    static let totalLabel = "Tổng cộng"
    static let totalFormula = "=SUM(D2:D10000)"
    /// Where `totalFormula` itself lives — two columns after `headerColumns`
    /// (one blank spacer column in between).
    static let totalColumn = SheetsHTTP.columnLetter(headerColumns.count + 2)
    static let categoryValues = ExpenseCategory.allCases.map(\.rawValue)

    /// Pinned as the first tab of every workspace spreadsheet. Holds one row
    /// per month tab (`Tháng`, `Tổng cộng`, then one column per category),
    /// all as formulas referencing that month's own tab directly — so it
    /// never drifts and never needs to be rewritten when entries change.
    static let summaryTabTitle = "Tổng hợp"
    static let summaryHeaderColumns = ["Tháng", "Tổng cộng"] + categoryValues

    /// Extra columns for a `.family` workspace, right after the spacer/
    /// "Tổng cộng" pair (E/F) so they never disturb the personal-workspace
    /// columns A-D. Written only when `members` is non-empty.
    static let familyHeaderColumns = ["Ai chi", "Chi cho ai", "Số người chia"]
    /// Per-person settle-up table, further right (L-O) than the family
    /// input columns so the two blocks stay visually separate.
    static let balanceHeaderColumns = ["Người", "Đã chi (ứng trước)", "Phải chi (chia đều)", "Chênh lệch"]
    /// Where the family member list itself lives — a single column in
    /// "Tổng hợp" (not any per-tab or per-device state), two columns past the
    /// category totals so it never collides with `summaryHeaderColumns`.
    static let membersColumn = SheetsHTTP.columnLetter(summaryHeaderColumns.count + 2)
    static let membersHeaderLabel = "Thành viên"
    /// The Google account (if any) granted Drive access for each member —
    /// same row order as `membersColumn`, right next to it. Separate from the
    /// member's display name so renaming them never touches who has access.
    static let memberEmailsColumn = SheetsHTTP.columnLetter(summaryHeaderColumns.count + 3)
    static let memberEmailsHeaderLabel = "Email"

    /// Hidden tab kept purely as the source for `duplicateSheet` — every
    /// month tab (including the very first one) is a copy of this, so
    /// header/"Tổng cộng" formula/category dropdown can never drift between
    /// one month tab and the next. Never shown, never written to directly.
    static let templateTabTitle = "_Mẫu"
}
