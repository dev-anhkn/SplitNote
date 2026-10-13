//
//  AppStyle.swift
//  SplitNote
//

import SwiftUI

enum AppStyle {
    static let cardCornerRadius: CGFloat = 14
    static let iconCornerRadius: CGFloat = 8
    static let cardPadding: CGFloat = 16
    static let sidebarMinWidth: CGFloat = 240
    static let sidebarMaxWidth: CGFloat = 320
    /// Màu thương hiệu riêng — `.accentColor` trên macOS bị màu nhấn hệ thống của người dùng ghi đè.
    static let gold = Color("GoldenSand")
    /// Màu phụ tím chàm của wallpaper macOS 27 Golden Gate, đi cùng màu nhấn vàng cát.
    static let indigo = Color("GoldenIndigo")
    /// Chữ/icon nâu đậm đặt trên nền vàng cát, đủ tương phản ở cả light/dark.
    static let onGold = Color(red: 0.17, green: 0.13, blue: 0.07)
}

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppStyle.cardPadding)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: AppStyle.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppStyle.cardCornerRadius, style: .continuous)
                    .stroke(.quaternary.opacity(0.6), lineWidth: 1)
            )
    }
}

/// Nền chung toàn app: gradient vàng nhạt từ đỉnh như màn chào (Figma).
struct AppBackground: View {
    var body: some View {
        LinearGradient(colors: [AppStyle.gold.opacity(0.14), .clear], startPoint: .top, endPoint: .center)
            .ignoresSafeArea()
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }

    /// Ẩn nền mặc định của List/Form để lộ gradient chung phía sau.
    func appBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(AppBackground())
    }
}

/// Icon nét màu trên ô vuông cùng màu nhạt — phong cách chung theo Figma.
struct IconBadge: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 32
    @Environment(\.colorScheme) private var colorScheme

    /// Light mode: tối màu icon đi để vàng/mint/cyan không chìm vào nền nhạt.
    private var glyphColor: Color {
        colorScheme == .dark ? color : color.mix(with: .black, by: 0.25)
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(glyphColor)
            .frame(width: size, height: size)
            .background(color.opacity(colorScheme == .dark ? 0.2 : 0.16), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Nút chính theo Figma: nền vàng cát, chữ nâu đậm — thay `.borderedProminent` vốn chữ trắng khó đọc trên vàng sáng.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    private var isLarge: Bool { controlSize == .large || controlSize == .extraLarge }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isLarge ? .body.weight(.semibold) : .subheadline.weight(.semibold))
            .foregroundStyle(AppStyle.onGold)
            .tint(AppStyle.onGold)
            .padding(.horizontal, isLarge ? 20 : 14)
            .padding(.vertical, isLarge ? 12 : 6)
            .background(AppStyle.gold, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// Chip bật/tắt dùng chung (chọn ngày, chọn người chia): bật thì tô màu thương hiệu nhạt.
struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    var showsCheckmark = false
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// Light mode: chữ vàng cát tối hơn cho đủ tương phản trên nền nhạt.
    private var selectedColor: Color {
        colorScheme == .dark ? AppStyle.gold : AppStyle.gold.mix(with: .black, by: 0.2)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if showsCheckmark && isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                }
                Text(title)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? selectedColor : .secondary)
            .background(isSelected ? AppStyle.gold.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(isSelected ? AppStyle.gold.opacity(0.45) : .clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isSelected)
    }
}

/// Dòng báo lỗi đỏ có icon cảnh báo, dùng chung cho mọi màn.
struct ErrorLabel: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
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
        case .personal: "wallet.bifold.fill"
        case .family: "person.2.fill"
        }
    }

    var color: Color {
        switch self {
        case .personal: AppStyle.gold
        case .family: AppStyle.indigo
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
                .foregroundStyle(AppStyle.gold)
                .frame(width: 30, height: 30)
                .background(AppStyle.gold.opacity(isHovering ? 0.28 : 0.16), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(isLoading)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// Nút tải lại trung tính cho bên trong thẻ — khác `ReloadButton` (màu nhấn) ở sidebar để không trông như bị lặp.
struct SubtleReloadButton: View {
    let isLoading: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.caption.weight(.semibold))
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: isLoading)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.quaternary.opacity(0.5), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(isLoading)
    }
}
