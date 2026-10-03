//
//  AppStyle.swift
//  SplitNote
//

import SwiftUI

enum AppStyle {
    static let cardCornerRadius: CGFloat = 14
    static let iconCornerRadius: CGFloat = 8
    static let cardPadding: CGFloat = 16
}

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppStyle.cardPadding)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: AppStyle.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppStyle.cardCornerRadius)
                    .stroke(.quaternary.opacity(0.6), lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

/// SF Symbol trắng trên ô vuông bo góc màu, giống icon trong System Settings.
struct IconBadge: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28))
    }
}

/// Chấm màu + chữ nhỏ trong viên thuốc, dùng cho trạng thái/nhãn phụ.
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.35), in: Capsule())
    }
}

extension ExpenseCategory {
    var icon: String {
        switch self {
        case .food: "fork.knife"
        case .utilities: "bolt.fill"
        case .internetService: "wifi"
        case .shopping: "bag.fill"
        case .health: "cross.case.fill"
        case .entertainment: "gamecontroller.fill"
        case .education: "book.fill"
        case .gifts: "gift.fill"
        case .travel: "airplane"
        case .services: "wrench.and.screwdriver.fill"
        case .transportation: "car.fill"
        case .housing: "house.fill"
        case .other: "ellipsis"
        }
    }

    /// Sheet lưu Loại dạng chữ nên có thể không khớp enum — rơi về `.other`.
    static func from(_ rawValue: String) -> ExpenseCategory {
        ExpenseCategory(rawValue: rawValue) ?? .other
    }
}

extension WorkspaceType {
    var icon: String {
        switch self {
        case .personal: "person.fill"
        case .family: "house.fill"
        }
    }

    var color: Color {
        switch self {
        case .personal: .blue
        case .family: .orange
        }
    }
}

/// Nút tải lại nổi bật: icon màu nhấn trên nền tròn nhạt, mũi tên tự xoay khi đang tải.
struct ReloadButton: View {
    let isLoading: Bool
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: isLoading)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(isHovering ? 0.28 : 0.16), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(isLoading)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
