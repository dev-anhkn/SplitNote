//
//  AuthViewModel.swift
//  SplitNote
//

import Combine
import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var currentUser: AppUser?
    @Published private(set) var isSigningIn = false
    @Published var signInErrorMessage: String?

    private let authService: AuthServiceProtocol

    init(authService: AuthServiceProtocol = GoogleAuthService()) {
        self.authService = authService
    }

    func restorePreviousSignIn() async {
        currentUser = await authService.restorePreviousSignIn()
    }

    func signIn() async {
        isSigningIn = true
        signInErrorMessage = nil
        defer { isSigningIn = false }

        do {
            currentUser = try await authService.signIn()
        } catch {
            signInErrorMessage = error.localizedDescription
        }
    }

    func signOut() {
        authService.signOut()
        currentUser = nil
    }
}
