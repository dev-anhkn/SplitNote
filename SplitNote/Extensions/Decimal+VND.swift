//
//  Decimal+VND.swift
//  SplitNote
//

import Foundation

extension NumberFormatter {
    /// Quy ước VNĐ dùng chung: không thập phân, "." phân cách hàng nghìn.
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

    /// VNĐ không có phần lẻ — làm tròn về số nguyên.
    var roundedToWhole: Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, 0, .plain)
        return result
    }
}
