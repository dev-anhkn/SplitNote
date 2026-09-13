//
//  ExpenseEntry.swift
//  SplitNote
//

import Foundation

/// One expense row read back from a workspace's monthly tab, below the
/// header. `rowIndex` is the 1-based row number in the sheet (row 1 is the
/// header, so entries start at 2) — not used yet, but keeps identity stable
/// if rows are ever edited/deleted in place instead of only appended to.
struct ExpenseEntry: Identifiable, Equatable {
    let rowIndex: Int
    let date: String
    let category: String
    let content: String
    let amount: Decimal
    /// Empty for a `.personal` workspace, or a row predating the family
    /// feature. Otherwise the name of whoever paid.
    let paidBy: String
    /// Comma-separated member names this expense splits across. Never
    /// stores "Tất cả" — the UI expands that to every current member name
    /// before saving, so this always lists exactly who's included.
    let sharedWith: String

    var id: Int { rowIndex }
}
