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
    /// Tags a Drive file with a private "app property" — invisible to the
    /// user, unaffected by renaming the file, and only ever queryable by
    /// this app. Used to re-find a workspace's spreadsheet if the locally
    /// cached ID (`WorkspaceStore`) is ever lost.
    func tagFile(fileId: String, key: String, value: String) async throws
    /// Finds the first non-trashed file tagged with `key == value`, if any.
    func findFile(key: String, value: String) async throws -> String?
}

struct DriveService: DriveServiceProtocol {

    nonisolated init() {}

    func tagFile(fileId: String, key: String, value: String) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        guard let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?fields=id") else {
            throw DriveServiceError.invalidResponse
        }
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
