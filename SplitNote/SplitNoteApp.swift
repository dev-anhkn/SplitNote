//
//  SplitNoteApp.swift
//  SplitNote
//
//  Created by Kim Ngọc Anh on 11/9/26.
//

import SwiftUI
import GoogleSignIn

@main
struct SplitNoteApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Nút/control hệ thống theo màu thương hiệu, không theo màu nhấn hệ thống.
                .tint(AppStyle.gold)
                #if os(macOS)
                // Chặn thu nhỏ cửa sổ tới mức sidebar + chi tiết bị bóp méo.
                .frame(minWidth: 720, minHeight: 540)
                #endif
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            SplitNoteCommands()
        }
        #endif
    }
}

#if os(macOS)
/// Thay "New Window" bằng lệnh ⌘N mở màn thêm khoản chi của workspace đang xem.
private struct SplitNoteCommands: Commands {
    @FocusedValue(\.quickAddAction) private var quickAddAction

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Thêm khoản chi") { quickAddAction?() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(quickAddAction == nil)
        }
    }
}
#endif

/// Hành động "thêm khoản chi" mà màn đang hiển thị công bố cho menu ⌘N gọi.
struct QuickAddActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var quickAddAction: (() -> Void)? {
        get { self[QuickAddActionKey.self] }
        set { self[QuickAddActionKey.self] = newValue }
    }
}
