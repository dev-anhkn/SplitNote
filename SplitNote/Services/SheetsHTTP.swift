//
//  SheetsHTTP.swift
//  SplitNote
//

import Foundation

/// Shared request/response plumbing for every Sheets API call — validating
/// responses and encoding tab titles/column letters the same way everywhere.
enum SheetsHTTP {
    static func validate(_ response: URLResponse, data: Data) throws {
        // 1. Không phải HTTP response hợp lệ thì báo lỗi chung.
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SheetsServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            print("[SplitNote][SheetsHTTP] \(httpResponse.url?.absoluteString ?? "?") -> HTTP \(httpResponse.statusCode): \(body)")
            // 404 = cả spreadsheet đã bị xoá.
            if httpResponse.statusCode == 404 {
                throw SheetsServiceError.notFound
            }
            // Tab không tồn tại trả về 400 INVALID_ARGUMENT "Unable to parse
            // range" — Sheets không có mã lỗi riêng cho trường hợp này — coi
            // như `.notFound` để nơi gọi đề nghị tạo lại tab.
            if httpResponse.statusCode == 400 && isMissingRangeError(data) {
                throw SheetsServiceError.notFound
            }
            throw SheetsServiceError.requestFailed(body)
        }
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

    /// Tab titles never contain "/" (month titles use "-"), so `.urlPathAllowed`
    /// is safe to percent-encode them with for use inside an A1 range.
    static func percentEncodedTabTitle(_ tabTitle: String) -> String? {
        tabTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }

    /// 1-based column index → spreadsheet column letter(s) (1 → "A", 15 → "O").
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
}
