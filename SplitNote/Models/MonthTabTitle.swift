//
//  MonthTabTitle.swift
//  SplitNote
//

import Foundation

/// Định dạng tiêu đề tab "Tháng MM-YYYY" dùng chung để tạo tab, chuyển tháng và so sánh luôn khớp nhau.
enum MonthTabTitle {
    /// Dùng "-" thay "/" để nhét thẳng vào A1 range mà không phải encode dấu phân cách đường dẫn.
    static func title(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .year], from: date)
        let month = components.month ?? 1
        let year = components.year ?? 0
        return String(format: "Tháng %02d-%d", month, year)
    }

    /// Nhãn hiển thị "Tháng 9 · 2026" cho thanh chuyển tháng.
    static func displayLabel(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .year], from: date)
        return "Tháng \(components.month ?? 1) · \(String(components.year ?? 0))"
    }

    /// Ngược lại của `title(for:)` — nil nếu tiêu đề không đúng dạng "Tháng MM-YYYY".
    static func dateInterval(for title: String) -> DateInterval? {
        let parts = title.replacingOccurrences(of: "Tháng ", with: "").split(separator: "-")
        guard
            parts.count == 2,
            let month = Int(parts[0]),
            let year = Int(parts[1]),
            let start = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))
        else { return nil }
        return Calendar.current.dateInterval(of: .month, for: start)
    }
}
