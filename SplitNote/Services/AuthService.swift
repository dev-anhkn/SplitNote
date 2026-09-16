//
//  AuthService.swift
//  SplitNote
//

import Foundation
import GoogleSignIn
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

protocol AuthServiceProtocol {
    /// Restores a session from a previous launch, if one exists. Never throws —
    /// "no saved session" and "restore failed" both just mean "signed out".
    func restorePreviousSignIn() async -> AppUser?
    func signIn() async throws -> AppUser
    func signOut()
}

enum AuthServiceError: Error, LocalizedError {
    case noPresentingSurface
    case missingProfile
    
    var errorDescription: String? {
        switch self {
        case .noPresentingSurface:
            return "No window is available to present the Google sign-in screen."
        case .missingProfile:
            return "Google did not return a user profile."
        }
    }
}

/// Wraps the GoogleSignIn SDK (which uses completion handlers, not async/await)
/// behind an async `AuthServiceProtocol`. Presenting the sign-in screen differs
/// by platform: iOS needs a `UIViewController`, macOS needs an `NSWindow`.
struct GoogleAuthService: AuthServiceProtocol {
    
    /// Requested in addition to the default profile scopes so the signed-in
    /// user's token can also call the Sheets API (see `SheetsService`).
    static let sheetsScope = "https://www.googleapis.com/auth/spreadsheets"
    /// Narrow Drive scope — only sees files this app creates or opens itself
    /// — used to tag/find workspace spreadsheets (see `DriveService`).
    static let driveFileScope = "https://www.googleapis.com/auth/drive.file"
    /// Read-only metadata across ALL files the account can access (owned +
    /// shared), unlike `driveFileScope`. Needed so `WorkspaceDiscoveryService`
    /// can find a workspace shared with this account via `appProperties`,
    /// even though this account's own `drive.file` grant never touched it.
    static let driveMetadataReadonlyScope = "https://www.googleapis.com/auth/drive.metadata.readonly"
    
    nonisolated init() {}
    
    func restorePreviousSignIn() async -> AppUser? {
        await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
                continuation.resume(returning: user.flatMap(AppUser.init(googleUser:)))
            }
        }
    }
    
    func signIn() async throws -> AppUser {
        // 1. Mở màn đăng nhập Google, xin đủ quyền Sheets + Drive.
        let googleUser = try await performSignIn()
        // 2. Chuyển sang AppUser dùng trong app.
        guard let appUser = AppUser(googleUser: googleUser) else {
            throw AuthServiceError.missingProfile
        }
        return appUser
    }
    
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }
    
    private func performSignIn() async throws -> GIDGoogleUser {
        // 1. Tìm màn hình/cửa sổ để hiện UI đăng nhập (khác nhau giữa iOS/macOS).
        // 2. Gọi SDK đăng nhập, xin thêm quyền Sheets + Drive.
        try await withCheckedThrowingContinuation { continuation in
#if os(iOS)
            guard let presentingViewController = Self.rootViewController else {
                continuation.resume(throwing: AuthServiceError.noPresentingSurface)
                return
            }
            GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingViewController,
                hint: nil,
                additionalScopes: [Self.sheetsScope, Self.driveFileScope, Self.driveMetadataReadonlyScope]
            ) { result, error in
                Self.resume(continuation, result: result, error: error)
            }
#elseif os(macOS)
            guard let presentingWindow = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else {
                continuation.resume(throwing: AuthServiceError.noPresentingSurface)
                return
            }
            GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingWindow,
                hint: nil,
                additionalScopes: [Self.sheetsScope, Self.driveFileScope, Self.driveMetadataReadonlyScope]
            ) { result, error in
                Self.resume(continuation, result: result, error: error)
            }
#endif
        }
    }
    
    private static func resume(
        _ continuation: CheckedContinuation<GIDGoogleUser, Error>,
        result: GIDSignInResult?,
        error: Error?
    ) {
        if let error {
            continuation.resume(throwing: error)
        } else if let user = result?.user {
            continuation.resume(returning: user)
        } else {
            continuation.resume(throwing: AuthServiceError.missingProfile)
        }
    }
    
#if os(iOS)
    private static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first(where: \.isKeyWindow)?
            .rootViewController
    }
#endif // os(iOS)
}

private extension AppUser {
    nonisolated init?(googleUser: GIDGoogleUser) {
        guard let profile = googleUser.profile else { return nil }
        self.init(
            id: googleUser.userID ?? profile.email,
            displayName: profile.name,
            email: profile.email,
            photoURL: profile.hasImage ? profile.imageURL(withDimension: 96) : nil
        )
    }
}
