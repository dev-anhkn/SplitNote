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
    init() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: "238078721564-2f7flmonhe52quqn7c8jvuk0j3soe0p6.apps.googleusercontent.com")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
