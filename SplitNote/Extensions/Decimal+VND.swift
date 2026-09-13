//
//  Decimal+VND.swift
//  SplitNote
//

import Foundation

extension NumberFormatter {
    /// Shared VNĐ grouping convention: no decimals, "." as the thousands
    /// separator. Reused by `formattedVND` and the quick-add amount field so
    /// the two don't drift apart.
    static let vndGrouping: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

extension Decimal {
    /// VNĐ không có phần thập phân — số nguyên nhóm dấu "." + "đ".
    var formattedVND: String {
        let digits = NumberFormatter.vndGrouping.string(from: NSDecimalNumber(decimal: self)) ?? "\(self)"
        return "\(digits) đ"
    }
}
