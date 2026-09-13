//
//  DriveService.swift
//  SplitNote
//

import Foundation

enum DriveServiceError: Error, LocalizedError {
    case invalidResponse
    case requestFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Google Drive returned an unexpected response."
        case .requestFailed(let message):
            return message
        }
    }
}

protocol DriveServiceProtocol {
    /// Tags a file with a private, queryable "app property" — used to re-find a
    /// workspace's spreadsheet if the cached ID (`WorkspaceStore`) is lost.
    func tagFile(fileId: String, key: String, value: String) async throws
    /// Finds the first non-trashed file tagged with `key == value`, if any.
    func findFile(key: String, value: String) async throws -> String?
    /// Whether `fileId` still exists and hasn't been trashed.
    func fileExists(fileId: String) async throws -> Bool
    /// Moves a file to Drive's Trash (recoverable, unlike a permanent delete).
    func trashFile(fileId: String) async throws
    /// Grants `email` a Drive permission on `fileId` — used when a `.family`
    /// member is added by email, so their own Google account can actually
    /// open (and edit) the workspace spreadsheet, not just appear as a name
    /// in "Ai chi"/"Chi cho ai".
    func shareFile(fileId: String, email: String, role: String) async throws
    /// Revokes `email`'s Drive permission on `fileId`, if any — the
    /// counterpart to `shareFile`, called when that member is removed.
    /// No-op if `email` was never actually shared (e.g. a plain display name).
    func revokeAccess(fileId: String, email: String) async throws
}

struct DriveService: DriveServiceProtocol {
    
    nonisolated init() {}
    
    func tagFile(fileId: String, key: String, value: String) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        guard let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?fields=id") else {
            throw DriveServiceError.invalidResponse
        }
        // Gắn appProperties (key/value) lên file.
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "appProperties": [key: value]
        ])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)
    }
    
    func findFile(key: String, value: String) async throws -> String? {
        // Query file có appProperties khớp key/value, chưa bị xoá.
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        let query = "appProperties has { key='\(key)' and value='\(value)' } and trashed = false"
        guard
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "https://www.googleapis.com/drive/v3/files?q=\(encodedQuery)&fields=files(id)&pageSize=1")
        else {
            throw DriveServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let files = json["files"] as? [[String: Any]]
        else {
            throw DriveServiceError.invalidResponse
        }
        return files.first?["id"] as? String
    }
    
    func fileExists(fileId: String) async throws -> Bool {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        guard let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?fields=id,trashed") else {
            throw DriveServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DriveServiceError.invalidResponse
        }
        // 404 = file không còn tồn tại.
        if httpResponse.statusCode == 404 {
            return false
        }
        try Self.validate(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DriveServiceError.invalidResponse
        }
        // Còn file nhưng đã vào thùng rác cũng coi như không tồn tại.
        return (json["trashed"] as? Bool ?? false) == false
    }
    
    func trashFile(fileId: String) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        guard let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?fields=id") else {
            throw DriveServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["trashed": true])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)
    }

    func shareFile(fileId: String, email: String, role: String) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        guard let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)/permissions?fields=id") else {
            throw DriveServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "user",
            "role": role,
            "emailAddress": email
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)
    }

    func revokeAccess(fileId: String, email: String) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        // 1. Drive chỉ xoá permission theo id, không xoá thẳng bằng email —
        // phải check account đó có permission nào trên file này trước.
        guard let permissionId = try await findPermissionId(fileId: fileId, email: email, accessToken: accessToken) else {
            return
        }
        // 2. Có id rồi mới xoá đúng permission đó.
        guard let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)/permissions/\(permissionId)") else {
            throw DriveServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)
    }

    /// Looks up `email`'s permission id on `fileId` — nil if that account
    /// was never granted access (case-insensitive: Drive lower-cases some
    /// addresses on input but not always on output).
    private func findPermissionId(fileId: String, email: String, accessToken: String) async throws -> String? {
        guard let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)/permissions?fields=permissions(id,emailAddress)") else {
            throw DriveServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let permissions = json["permissions"] as? [[String: Any]]
        else {
            throw DriveServiceError.invalidResponse
        }
        return permissions.first { ($0["emailAddress"] as? String)?.caseInsensitiveCompare(email) == .orderedSame }?["id"] as? String
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DriveServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw DriveServiceError.requestFailed(message)
        }
    }
}
