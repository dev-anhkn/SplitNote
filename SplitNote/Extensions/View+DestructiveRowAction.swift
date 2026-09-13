//
//  View+DestructiveRowAction.swift
//  SplitNote
//

import SwiftUI

private struct DestructiveRowAction: ViewModifier {
    let title: String
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .swipeActions {
                Button(title, role: .destructive, action: action)
            }
        // swipeActions không có trên macOS — dùng contextMenu thay.
            .contextMenu {
                Button(title, role: .destructive, action: action)
            }
    }
}

extension View {
    /// Xoá qua vuốt (iOS/iPadOS) hoặc right-click context menu (macOS).
    func destructiveRowAction(_ title: String = "Xoá", action: @escaping () -> Void) -> some View {
        modifier(DestructiveRowAction(title: title, action: action))
    }
}
