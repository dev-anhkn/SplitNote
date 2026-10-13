//
//  SheetsHTTP.swift
//  SplitNote
//

import Foundation
import OSLog

/// Hạ tầng request/response dùng chung cho mọi lệnh gọi Sheets API.
enum SheetsHTTP {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SplitNote", category: "SheetsHTTP")
    private static let baseURL = "https://sheets.googleapis.com/v4/spreadsheets"

    // MARK: - Request

    /// Gửi request kèm token, kiểm tra status rồi trả JSON response (rỗng nếu body rỗng).
    @discardableResult
    static func send(_ url: URL, method: String = "GET", body: Any? = nil, accessToken: String) async throws -> [String: Any] {
        let request = try URLRequest.googleAPI(url, method: method, accessToken: accessToken, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        guard !data.isEmpty else { return [:] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SheetsServiceError.invalidResponse
        }
        return json
    }

    /// Đọc 1 vùng ô của tab; hàng/ô trống ở cuối bị Sheets lược bỏ.
    static func readValues(spreadsheetId: String, tabTitle: String, range: String, accessToken: String) async throws -> [[String]] {
        let url = try valuesURL(spreadsheetId: spreadsheetId, tabTitle: tabTitle, range: range)
        let json = try await send(url, accessToken: accessToken)
        return json["values"] as? [[String]] ?? []
    }

    /// `USER_ENTERED` (không phải `RAW`) để công thức được tính.
    static func writeValues(spreadsheetId: String, tabTitle: String, range: String, values: [[String]], accessToken: String) async throws {
        let url = try valuesURL(spreadsheetId: spreadsheetId, tabTitle: tabTitle, range: range, suffix: "?valueInputOption=USER_ENTERED")
        try await send(url, method: "PUT", body: ["values": values], accessToken: accessToken)
    }

    static func clearValues(spreadsheetId: String, tabTitle: String, range: String, accessToken: String) async throws {
        let url = try valuesURL(spreadsheetId: spreadsheetId, tabTitle: tabTitle, range: range, suffix: ":clear")
        try await send(url, method: "POST", body: [String: Any](), accessToken: accessToken)
    }

    /// Ghi nhiều vùng ô trong 1 request; `ranges` là A1 range đầy đủ (dùng `bodyRange`).
    static func batchWriteValues(spreadsheetId: String, ranges: [(range: String, values: [[String]])], accessToken: String) async throws {
        let url = try spreadsheetURL(spreadsheetId, path: "/values:batchUpdate")
        let data = ranges.map { ["range": $0.range, "values": $0.values] }
        try await send(url, method: "POST", body: ["valueInputOption": "USER_ENTERED", "data": data], accessToken: accessToken)
    }

    /// Đọc nhiều vùng ô (A1 range đầy đủ, dùng `bodyRange`) trong 1 request, trả về theo đúng thứ tự `ranges`.
    static func batchReadValues(spreadsheetId: String, ranges: [String], accessToken: String) async throws -> [[[String]]] {
        let query = try ranges.map { "ranges=\(try queryEncoded($0))" }.joined(separator: "&")
        let url = try spreadsheetURL(spreadsheetId, path: "/values:batchGet?\(query)")
        let json = try await send(url, accessToken: accessToken)
        let valueRanges = json["valueRanges"] as? [[String: Any]] ?? []
        return valueRanges.map { $0["values"] as? [[String]] ?? [] }
    }

    /// Xoá trắng nhiều vùng ô (A1 range đầy đủ) trong 1 request.
    static func batchClearValues(spreadsheetId: String, ranges: [String], accessToken: String) async throws {
        let url = try spreadsheetURL(spreadsheetId, path: "/values:batchClear")
        try await send(url, method: "POST", body: ["ranges": ranges], accessToken: accessToken)
    }

    /// Gọi `spreadsheets.batchUpdate`, trả về mảng `replies` theo đúng thứ tự `requests`.
    @discardableResult
    static func batchUpdate(spreadsheetId: String, requests: [[String: Any]], accessToken: String) async throws -> [[String: Any]] {
        let url = try spreadsheetURL(spreadsheetId, path: ":batchUpdate")
        let json = try await send(url, method: "POST", body: ["requests": requests], accessToken: accessToken)
        return json["replies"] as? [[String: Any]] ?? []
    }

    // MARK: - URL

    static func spreadsheetURL(_ spreadsheetId: String = "", path: String = "") throws -> URL {
        let separator = spreadsheetId.isEmpty ? "" : "/"
        guard let url = URL(string: "\(baseURL)\(separator)\(spreadsheetId)\(path)") else {
            throw SheetsServiceError.invalidResponse
        }
        return url
    }

    /// `suffix` là phần nối sau range, vd ":clear" hoặc "?valueInputOption=...".
    static func valuesURL(spreadsheetId: String, tabTitle: String, range: String, suffix: String = "") throws -> URL {
        guard let encodedTitle = percentEncodedTabTitle(tabTitle) else {
            throw SheetsServiceError.invalidResponse
        }
        return try spreadsheetURL(spreadsheetId, path: "/values/'\(encodedTitle)'!\(range)\(suffix)")
    }

    /// Tiêu đề tab không bao giờ chứa "/" (tháng dùng "-") nên `.urlPathAllowed` là đủ an toàn.
    static func percentEncodedTabTitle(_ tabTitle: String) -> String? {
        tabTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }

    /// Encode chặt cho giá trị query (range có dấu nháy, "!", ":", khoảng trắng).
    private static func queryEncoded(_ value: String) throws -> String {
        // Chỉ ASCII — `.alphanumerics` gồm cả chữ có dấu, sẽ không được encode.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw SheetsServiceError.invalidResponse
        }
        return encoded
    }

    /// A1 range dùng trong JSON body — không percent-encode (Google không decode body), chỉ escape dấu nháy đơn.
    static func bodyRange(tabTitle: String, cells: String) -> String {
        let escapedTitle = tabTitle.replacingOccurrences(of: "'", with: "''")
        return "'\(escapedTitle)'!\(cells)"
    }

    /// Chỉ số cột (bắt đầu từ 1) → chữ cái cột (1 → "A", 15 → "O").
    static func columnLetter(_ index: Int) -> String {
        var index = index
        var letters = ""
        while index > 0 {
            let remainder = (index - 1) % 26
            letters = String(UnicodeScalar(65 + remainder)!) + letters
            index = (index - 1) / 26
        }
        return letters
    }

    // MARK: - Parse

    /// VNĐ không có phần thập phân — chỉ giữ số và dấu trừ, đọc được cả "300.000" lẫn "300,000".
    static func parseAmount(_ text: String) -> Decimal? {
        Decimal(string: text.filter { $0.isNumber || $0 == "-" })
    }

    /// Ô ở `index` của hàng, rỗng nếu Sheets đã lược bỏ ô trống cuối hàng.
    static func cell(_ row: [String], _ index: Int) -> String {
        row.indices.contains(index) ? row[index] : ""
    }

    // MARK: - Validate

    static func validate(_ response: URLResponse, data: Data) throws {
        // 1. Không phải HTTP response hợp lệ thì báo lỗi chung.
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SheetsServiceError.invalidResponse
        }
        // 2. Status 2xx là thành công.
        guard !(200..<300).contains(httpResponse.statusCode) else { return }
        logFailure(httpResponse, data: data)
        // 3. Quy lỗi về `.notFound` để nơi gọi đề nghị tạo lại, còn lại trả nguyên văn.
        guard !isNotFound(httpResponse.statusCode, data: data) else {
            throw SheetsServiceError.notFound
        }
        let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
        throw SheetsServiceError.requestFailed(message)
    }

    /// 404 = mất cả spreadsheet; 400 "Unable to parse range" = mất tab (Sheets không có mã lỗi riêng).
    private static func isNotFound(_ statusCode: Int, data: Data) -> Bool {
        statusCode == 404 || (statusCode == 400 && isMissingRangeError(data))
    }

    /// In nguyên văn lỗi Google trả về — lỗi hiển thị trên UI đã bị gộp (vd 400 "Unable to parse range" → `.notFound`).
    private static func logFailure(_ response: HTTPURLResponse, data: Data) {
        let url = response.url?.absoluteString.removingPercentEncoding ?? "?"
        let body = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
        logger.error("HTTP \(response.statusCode, privacy: .public) \(url, privacy: .public)\n\(body, privacy: .public)")
    }

    private static func isMissingRangeError(_ data: Data) -> Bool {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any],
            error["status"] as? String == "INVALID_ARGUMENT",
            let message = error["message"] as? String
        else { return false }
        return message.contains("Unable to parse range")
    }
}
