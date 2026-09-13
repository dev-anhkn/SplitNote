//
//  ExpenseCategory.swift
//  SplitNote
//

import SwiftUI

/// The fixed set of spending categories. Enforced as a dropdown in the
/// underlying Google Sheet (column B, via data validation) so category
/// names stay consistent enough to pivot/sum on later.
enum ExpenseCategory: String, CaseIterable, Identifiable {
    case food = "Ăn uống"
    case utilities = "Điện nước"
    case internetService = "Internet"
    case shopping = "Mua sắm"
    case health = "Sức khỏe"
    case entertainment = "Giải trí"
    case education = "Học tập"
    case gifts = "Quà tặng"
    case travel = "Du lịch"
    case services = "Dịch vụ"
    case transportation = "Di chuyển"
    case housing = "Nhà ở"
    case other = "Khác"

    var id: String { rawValue }

    /// Fixed per category (not assigned by position in whatever subset is
    /// shown) so the same category always reads as the same color across
    /// months in the "Theo loại tháng này" chart.
    var color: Color {
        switch self {
        case .food: .orange
        case .utilities: .blue
        case .internetService: .indigo
        case .shopping: .pink
        case .health: .red
        case .entertainment: .purple
        case .education: .teal
        case .gifts: .mint
        case .travel: .cyan
        case .services: .brown
        case .transportation: .green
        case .housing: .yellow
        case .other: .gray
        }
    }
}
