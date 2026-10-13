//
//  GoogleAPIAuth.swift
//  SplitNote
//

import Foundation
import GoogleSignIn

enum GoogleAPIAuthError: Error, LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        "Bạn cần đăng nhập Google trước."
    }
}

/// Lấy access token cho mọi API Google (Sheets, Drive...), luôn refresh trước vì token hết hạn sẽ bị từ chối.
enum GoogleAPIAuth {
    static func currentAccessToken() async throws -> String {
        // 1. Chưa đăng nhập thì báo lỗi luôn.
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleAPIAuthError.notSignedIn
        }
        // 2. Làm mới token nếu cần rồi trả về token hiện tại.
        let user = try await refreshedUser(currentUser)
        return user.accessToken.tokenString
    }

    /// Bọc completion-handler của GoogleSignIn SDK thành async/await.
    private static func refreshedUser(_ user: GIDGoogleUser) async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { refreshedUser, error in
                guard let refreshedUser, error == nil else {
                    continuation.resume(throwing: error ?? GoogleAPIAuthError.notSignedIn)
                    return
                }
                continuation.resume(returning: refreshedUser)
            }
        }
    }
}

extension URLRequest {
    /// Request gắn sẵn Bearer token; có `body` thì gửi kèm dạng JSON.
    static func googleAPI(_ url: URL, method: String = "GET", accessToken: String, body: Any? = nil) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let body else { return request }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
