//
//  GoogleAPIAuth.swift
//  SplitNote
//

import Foundation
import GoogleSignIn

enum GoogleAPIAuthError: Error, LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        "You need to sign in with Google first."
    }
}

/// Shared access-token retrieval for any Google REST API call (Sheets, Drive, ...).
/// Refreshes first — the Sheets/Drive APIs reject an expired access token, and
/// refreshing is a no-op if the current token still has time left.
enum GoogleAPIAuth {
    static func currentAccessToken() async throws -> String {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleAPIAuthError.notSignedIn
        }
        let user = try await refreshedUser(currentUser)
        return user.accessToken.tokenString
    }

    private static func refreshedUser(_ user: GIDGoogleUser) async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { refreshedUser, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let refreshedUser {
                    continuation.resume(returning: refreshedUser)
                } else {
                    continuation.resume(throwing: GoogleAPIAuthError.notSignedIn)
                }
            }
        }
    }
}
