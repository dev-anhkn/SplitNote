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
    /// Khôi phục phiên trước nếu có; không ném lỗi — thất bại cũng coi như chưa đăng nhập.
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
            return "Không có cửa sổ nào để hiện màn đăng nhập Google."
        case .missingProfile:
            return "Google không trả về thông tin tài khoản."
        }
    }
}

/// Bọc GoogleSignIn SDK (completion handler) thành async; iOS cần `UIViewController`, macOS cần `NSWindow`.
struct GoogleAuthService: AuthServiceProtocol {
    /// Sheets đọc/ghi, Drive file do app tạo, metadata mọi file (để tìm workspace được chia sẻ).
    private static let additionalScopes = [
        "https://www.googleapis.com/auth/spreadsheets",
        "https://www.googleapis.com/auth/drive.file",
        "https://www.googleapis.com/auth/drive.metadata.readonly"
    ]


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
        try await withCheckedThrowingContinuation { continuation in
            // 1. Tìm màn hình/cửa sổ để hiện UI đăng nhập.
            guard let presenter = Self.presenter else {
                continuation.resume(throwing: AuthServiceError.noPresentingSurface)
                return
            }
            // 2. Gọi SDK đăng nhập, xin thêm quyền Sheets + Drive.
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: Self.additionalScopes) { result, error in
                Self.resume(continuation, result: result, error: error)
            }
        }
    }

    private static func resume(
        _ continuation: CheckedContinuation<GIDGoogleUser, Error>,
        result: GIDSignInResult?,
        error: Error?
    ) {
        guard let user = result?.user, error == nil else {
            continuation.resume(throwing: error ?? AuthServiceError.missingProfile)
            return
        }
        continuation.resume(returning: user)
    }

#if os(iOS)
    /// View controller gốc của cửa sổ đang active.
    private static var presenter: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first(where: \.isKeyWindow)?
            .rootViewController
    }
#elseif os(macOS)
    private static var presenter: NSWindow? {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first
    }
#endif
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
