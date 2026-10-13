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
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

