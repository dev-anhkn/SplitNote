//
//  View+DestructiveRowAction.swift
//  SplitNote
//

import SwiftUI

private struct DestructiveRowAction: ViewModifier {
    let title: String
    let action: () -> Void
    let editTitle: String
    let editAction: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .swipeActions {
                Button(title, role: .destructive, action: action)
            }
        // swipeActions không có trên macOS — dùng contextMenu thay.
            .contextMenu {
                if let editAction {
                    Button(editTitle, systemImage: "pencil", action: editAction)
                }
                Button(title, systemImage: "trash", role: .destructive, action: action)
            }
    }
}

extension View {
    /// Xoá qua vuốt (iOS/iPadOS) hoặc right-click context menu (macOS); `onEdit` thêm mục "Sửa" vào context menu.
    func destructiveRowAction(_ title: String = "Xoá", editTitle: String = "Sửa", onEdit: (() -> Void)? = nil, action: @escaping () -> Void) -> some View {
        modifier(DestructiveRowAction(title: title, action: action, editTitle: editTitle, editAction: onEdit))
    }
}
