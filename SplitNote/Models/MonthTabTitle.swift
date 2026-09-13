//
//  MonthTabTitle.swift
//  SplitNote
//

import Foundation

/// Shared "Tháng MM-YYYY" formatting for a workspace's monthly tab titles —
/// used both when ensuring/creating a tab and when navigating between months
/// or comparing several of them, so all three always agree on the exact title.
enum MonthTabTitle {
    /// "-" instead of "/" so this can drop straight into an A1 range
    /// (`'Tháng 09-2026'!A1:D1`) without URL-encoding a path separator.
    static func title(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .year], from: date)
        let month = components.month ?? 1
        let year = components.year ?? 0
        return String(format: "Tháng %02d-%d", month, year)
    }
}
