//
//  ExpenseEntry.swift
//  SplitNote
//

import Foundation

/// 1 khoản chi đọc từ tab tháng; `rowIndex` là số hàng trên sheet (từ 2), dùng để sửa/xoá đúng hàng.
struct ExpenseEntry: Identifiable, Equatable {
    let rowIndex: Int
    let date: String
    let category: String
    let content: String
    let amount: Decimal
    /// Người chi; rỗng với workspace cá nhân hoặc hàng cũ trước khi có tính năng gia đình.
    let paidBy: String
    /// Tên người được chia, ngăn bởi dấu phẩy — "Tất cả" đã được bung thành tên cụ thể trước khi lưu.
    let sharedWith: String

    var id: Int { rowIndex }
}
