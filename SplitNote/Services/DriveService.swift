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
            return "Google Drive trả về phản hồi không hợp lệ."
        case .requestFailed(let message):
            return message
        }
    }
}

protocol DriveServiceProtocol {
    /// Gắn "app property" riêng lên file để tìm lại spreadsheet khi mất id cache.
    func tagFile(fileId: String, key: String, value: String) async throws
    /// File đầu tiên chưa vào thùng rác có `key == value`, nếu có.
    func findFile(key: String, value: String) async throws -> String?
    /// File còn tồn tại và chưa vào thùng rác.
    func fileExists(fileId: String) async throws -> Bool
    /// Chuyển vào thùng rác (khôi phục được, không xoá vĩnh viễn).
    func trashFile(fileId: String) async throws
    /// Tên file hiện tại trên Drive.
    func fileName(fileId: String) async throws -> String
    /// Đổi tên file trên Drive.
    func renameFile(fileId: String, to name: String) async throws
    /// Cấp quyền cho `email` để tài khoản Google đó tự mở được workspace.
    func shareFile(fileId: String, email: String, role: String) async throws
    /// Thu hồi quyền của `email` — không làm gì nếu email đó chưa từng được cấp.
    func revokeAccess(fileId: String, email: String) async throws
}

struct DriveService: DriveServiceProtocol {
    /// Vai trò khi cấp quyền sửa cho thành viên.
    static let writerRole = "writer"
    private static let baseURL = "https://www.googleapis.com/drive/v3/files"

    nonisolated init() {}

    func tagFile(fileId: String, key: String, value: String) async throws {
        let url = try Self.url("/\(fileId)?fields=id")
        try await send(url, method: "PATCH", body: ["appProperties": [key: value]])
    }

    func findFile(key: String, value: String) async throws -> String? {
        let query = "appProperties has { key='\(key)' and value='\(value)' } and trashed = false"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw DriveServiceError.invalidResponse
        }
        let url = try Self.url("?q=\(encodedQuery)&fields=files(id)&pageSize=1")
        guard let files = try await sendJSON(url)["files"] as? [[String: Any]] else {
            throw DriveServiceError.invalidResponse
        }
        return files.first?["id"] as? String
    }

    func fileExists(fileId: String) async throws -> Bool {
        // 1. Tự gửi request vì 404 ở đây là kết quả hợp lệ, không phải lỗi.
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        let request = try URLRequest.googleAPI(try Self.url("/\(fileId)?fields=id,trashed"), accessToken: accessToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        // 2. 404 = file không còn.
        guard (response as? HTTPURLResponse)?.statusCode != 404 else { return false }
        try Self.validate(response, data: data)
        // 3. Đã vào thùng rác cũng coi như không còn.
        let json = try Self.json(from: data)
        return (json["trashed"] as? Bool ?? false) == false
    }

    func trashFile(fileId: String) async throws {
        let url = try Self.url("/\(fileId)?fields=id")
        try await send(url, method: "PATCH", body: ["trashed": true])
    }

    func fileName(fileId: String) async throws -> String {
        let url = try Self.url("/\(fileId)?fields=name")
        guard let name = try await sendJSON(url)["name"] as? String else {
            throw DriveServiceError.invalidResponse
        }
        return name
    }

    func renameFile(fileId: String, to name: String) async throws {
        let url = try Self.url("/\(fileId)?fields=id")
        try await send(url, method: "PATCH", body: ["name": name])
    }

    func shareFile(fileId: String, email: String, role: String) async throws {
        let url = try Self.url("/\(fileId)/permissions?fields=id")
        try await send(url, method: "POST", body: ["type": "user", "role": role, "emailAddress": email])
    }

    func revokeAccess(fileId: String, email: String) async throws {
        // 1. Drive chỉ xoá permission theo id — phải tìm id của email trước.
        guard let permissionId = try await findPermissionId(fileId: fileId, email: email) else { return }
        // 2. Xoá đúng permission đó.
        let url = try Self.url("/\(fileId)/permissions/\(permissionId)")
        try await send(url, method: "DELETE")
    }

    /// So không phân biệt hoa/thường vì Drive không luôn trả email đúng dạng đã nhập.
    private func findPermissionId(fileId: String, email: String) async throws -> String? {
        let url = try Self.url("/\(fileId)/permissions?fields=permissions(id,emailAddress)")
        guard let permissions = try await sendJSON(url)["permissions"] as? [[String: Any]] else {
            throw DriveServiceError.invalidResponse
        }
        let matched = permissions.first { ($0["emailAddress"] as? String)?.caseInsensitiveCompare(email) == .orderedSame }
        return matched?["id"] as? String
    }

    // MARK: - HTTP

    /// Gửi request kèm token, kiểm tra status rồi trả body thô.
    @discardableResult
    private func send(_ url: URL, method: String = "GET", body: Any? = nil) async throws -> Data {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        let request = try URLRequest.googleAPI(url, method: method, accessToken: accessToken, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)
        return data
    }

    private func sendJSON(_ url: URL) async throws -> [String: Any] {
        try Self.json(from: try await send(url))
    }

    private static func url(_ path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else {
            throw DriveServiceError.invalidResponse
        }
        return url
    }

    private static func json(from data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DriveServiceError.invalidResponse
        }
        return json
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
