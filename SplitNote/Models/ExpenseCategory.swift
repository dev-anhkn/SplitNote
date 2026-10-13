//
//  ExpenseCategory.swift
//  SplitNote
//

import SwiftUI

/// Danh sách loại chi cố định — ép thành dropdown cột B trên Sheet để tên loại luôn khớp khi cộng tổng.
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

    /// Màu cố định theo loại để biểu đồ các tháng luôn cùng màu; tông đất trầm hợp theme vàng cát.
    var color: Color {
        switch self {
        case .food: Self.rgb(0xD4, 0x79, 0x4E)            // đất nung
        case .utilities: Self.rgb(0xD9, 0xA2, 0x3F)       // hổ phách
        case .internetService: Self.rgb(0x85, 0x80, 0xD0) // tím chàm
        case .shopping: Self.rgb(0xB5, 0x80, 0x9A)        // tím hồng trầm
        case .health: Self.rgb(0x5F, 0xA8, 0x9C)          // xanh ngọc trầm
        case .entertainment: Self.rgb(0xA4, 0x7C, 0xC2)   // tím oải hương
        case .education: Self.rgb(0x5E, 0x9C, 0xB5)       // xanh đá
        case .gifts: Self.rgb(0x86, 0xAE, 0x7C)           // xanh xô thơm
        case .travel: Self.rgb(0x6E, 0x8F, 0xC9)          // xanh bụi
        case .services: Self.rgb(0x9C, 0x7A, 0x5B)        // nâu gỗ
        case .transportation: Self.rgb(0xA3, 0xA5, 0x4E)  // ô liu
        case .housing: Self.rgb(0xC2, 0xA8, 0x78)         // cát
        case .other: Self.rgb(0x9A, 0x93, 0x8A)           // xám ấm
        }
    }

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}
