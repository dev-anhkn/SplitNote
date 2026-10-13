//
//  View+KeyboardStepper.swift
//  SplitNote
//

import SwiftUI

#if os(macOS)
/// Cho 1 hàng không phải ô chữ vào vòng Tab và điều khiển bằng phím: ↑/↓ đổi giá trị, gõ chữ để nhảy, Return để lưu.
private struct KeyboardStepper: ViewModifier {
    let onUp: () -> Void
    let onDown: () -> Void
    let onCharacter: ((Character) -> Void)?
    let onSubmit: (() -> Void)?
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            // `.edit` để luôn nằm trong vòng Tab, kể cả khi tắt "Keyboard navigation" của macOS.
            .focusable(interactions: .edit)
            .focused($isFocused)
            .focusEffectDisabled()
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(-4)
                    .opacity(isFocused ? 1 : 0)
            }
            .onKeyPress(.upArrow) {
                runAfterUpdate(onUp)
                return .handled
            }
            .onKeyPress(.downArrow) {
                runAfterUpdate(onDown)
                return .handled
            }
            .onKeyPress(.return) {
                guard let onSubmit else { return .ignored }
                onSubmit()
                return .handled
            }
            .onKeyPress(characters: .alphanumerics) { press in
                guard let onCharacter, let character = press.characters.first else { return .ignored }
                runAfterUpdate { onCharacter(character) }
                return .handled
            }
    }

    /// onKeyPress chạy giữa lúc SwiftUI cập nhật view; đổi @Published ngay tại đó sẽ bị cảnh báo "Publishing changes from within view updates".
    private func runAfterUpdate(_ action: @escaping () -> Void) {
        DispatchQueue.main.async(execute: action)
    }
}

extension View {
    func keyboardStepper(onUp: @escaping () -> Void, onDown: @escaping () -> Void, onCharacter: ((Character) -> Void)? = nil, onSubmit: (() -> Void)? = nil) -> some View {
        modifier(KeyboardStepper(onUp: onUp, onDown: onDown, onCharacter: onCharacter, onSubmit: onSubmit))
    }
}
#endif
