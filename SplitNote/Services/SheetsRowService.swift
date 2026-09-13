//
//  SheetsRowService.swift
//  SplitNote
//

import Foundation

/// CRUD over one month tab's expense rows (A:E) plus the paired family
/// columns (I:K) for a `.family` workspace.
struct SheetsRowService {
    nonisolated init() {}

    func appendRow(spreadsheetId: String, tabTitle: String, date: String, category: String, content: String, amount: String, rawNote: String, paidBy: String?, sharedWith: String?) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        guard let encodedTitle = SheetsHTTP.percentEncodedTabTitle(tabTitle) else {
            throw SheetsServiceError.invalidResponse
        }
        // Ghi thẳng vào hàng trống tiếp theo thay vì values.append: append tự
        // dò "cuối bảng" và có thể ghi đè lên hàng deleteRow để trống ở giữa,
        // làm lệch thứ tự các khoản chi còn lại.
        let targetRow = try await nextRowIndex(spreadsheetId: spreadsheetId, encodedTitle: encodedTitle, accessToken: accessToken)
        guard let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!A\(targetRow):E\(targetRow)?valueInputOption=USER_ENTERED") else {
            throw SheetsServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "values": [[date, category, content, amount, rawNote]]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try SheetsHTTP.validate(response, data: data)

        if let paidBy, let sharedWith {
            try await writeFamilyRow(spreadsheetId: spreadsheetId, encodedTitle: encodedTitle, row: targetRow, paidBy: paidBy, sharedWith: sharedWith, accessToken: accessToken)
        }
    }

    /// Dùng render option mặc định (`FORMATTED_VALUE`) để cột ngày trả về
    /// đúng như hiển thị, khỏi phải tự quy đổi số serial ngày của Sheets.
    func fetchRows(spreadsheetId: String, tabTitle: String) async throws -> [ExpenseEntry] {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        guard let encodedTitle = SheetsHTTP.percentEncodedTabTitle(tabTitle) else {
            throw SheetsServiceError.invalidResponse
        }
        guard let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!A2:K10000") else {
            throw SheetsServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try SheetsHTTP.validate(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SheetsServiceError.invalidResponse
        }

        // Hàng 2 là hàng dữ liệu đầu tiên; bỏ qua hàng không có số tiền hợp lệ.
        // Đọc rộng tới K để lấy luôn Ai chi (I)/Chi cho ai (J) — F/G/H (spacer,
        // Tổng cộng, spacer) nằm giữa nhưng không được dùng tới.
        let rows = json["values"] as? [[String]] ?? []
        return rows.enumerated().compactMap { offset, row in
            // VNĐ không thập phân — giữ lại số/dấu trừ, đọc được cả
            // "300000" lẫn "300,000"/"300.000".
            guard row.indices.contains(3) else { return nil }
            let amountDigits = row[3].filter { $0.isNumber || $0 == "-" }
            guard let amount = Decimal(string: amountDigits) else { return nil }
            return ExpenseEntry(
                rowIndex: offset + 2,
                date: row[0],
                category: row.indices.contains(1) ? row[1] : "",
                content: row.indices.contains(2) ? row[2] : "",
                amount: amount,
                rawNote: row.indices.contains(4) ? row[4] : "",
                paidBy: row.indices.contains(8) ? row[8] : "",
                sharedWith: row.indices.contains(9) ? row[9] : ""
            )
        }
    }

    /// Ghi thẳng B:D của `rowIndex` bằng `values.update` — không đụng Ngày/Ghi chú gốc.
    func updateRow(spreadsheetId: String, tabTitle: String, rowIndex: Int, category: String, content: String, amount: String, paidBy: String?, sharedWith: String?) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        guard let encodedTitle = SheetsHTTP.percentEncodedTabTitle(tabTitle) else {
            throw SheetsServiceError.invalidResponse
        }
        guard let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!B\(rowIndex):D\(rowIndex)?valueInputOption=USER_ENTERED") else {
            throw SheetsServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "values": [[category, content, amount]]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try SheetsHTTP.validate(response, data: data)

        if let paidBy, let sharedWith {
            try await writeFamilyRow(spreadsheetId: spreadsheetId, encodedTitle: encodedTitle, row: rowIndex, paidBy: paidBy, sharedWith: sharedWith, accessToken: accessToken)
        }
    }

    /// `values.clear` thay vì xoá hẳn hàng: xoá hẳn sẽ dịch chuyển các hàng
    /// dưới, làm lệch `rowIndex` của các khoản chi khác và công thức Tổng cộng
    /// (cột G). Để trống A:E thì `fetchRows` tự bỏ qua hàng đó.
    func deleteRow(spreadsheetId: String, tabTitle: String, rowIndex: Int) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        guard let encodedTitle = SheetsHTTP.percentEncodedTabTitle(tabTitle) else {
            throw SheetsServiceError.invalidResponse
        }
        guard let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!A\(rowIndex):E\(rowIndex):clear") else {
            throw SheetsServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [String: Any]())

        let (data, response) = try await URLSession.shared.data(for: request)
        try SheetsHTTP.validate(response, data: data)

        // Xoá luôn I:K nếu tab này có cột gia đình — vô hại với tab cá nhân
        // (không có gì ở đó để xoá).
        guard let familyURL = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!I\(rowIndex):K\(rowIndex):clear") else {
            throw SheetsServiceError.invalidResponse
        }
        var familyRequest = URLRequest(url: familyURL)
        familyRequest.httpMethod = "POST"
        familyRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        familyRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        familyRequest.httpBody = try JSONSerialization.data(withJSONObject: [String: Any]())
        let (familyData, familyResponse) = try await URLSession.shared.data(for: familyRequest)
        try SheetsHTTP.validate(familyResponse, data: familyData)
    }

    /// Writes I:K (Ai chi/Chi cho ai/Số người chia) for one row — shared by
    /// `appendRow` and `updateRow`. `K` is always rewritten as a formula
    /// referencing `J` on the same row, so it self-corrects if `sharedWith`
    /// changes on an edit.
    private func writeFamilyRow(spreadsheetId: String, encodedTitle: String, row: Int, paidBy: String, sharedWith: String, accessToken: String) async throws {
        guard let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!I\(row):K\(row)?valueInputOption=USER_ENTERED") else {
            throw SheetsServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Đếm số tên trong "Chi cho ai" bằng số dấu phẩy + 1, thay vì lưu số
        // cứng — sửa lại danh sách người chia thì số người chia tự cập nhật.
        let countFormula = "=IF(J\(row)=\"\",0,LEN(J\(row))-LEN(SUBSTITUTE(J\(row),\",\",\"\"))+1)"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "values": [[paidBy, sharedWith, countFormula]]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try SheetsHTTP.validate(response, data: data)
    }

    /// 1-based row right after the last row (from row 2) that still has data
    /// in A:E — `deleteRow` blanks a row in place rather than removing it, so
    /// a gap must be skipped over, not reused.
    private func nextRowIndex(spreadsheetId: String, encodedTitle: String, accessToken: String) async throws -> Int {
        guard let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!A2:E10000") else {
            throw SheetsServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try SheetsHTTP.validate(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SheetsServiceError.invalidResponse
        }
        let rows = json["values"] as? [[String]] ?? []
        let lastUsedRow = rows.lastIndex { !$0.allSatisfy(\.isEmpty) }.map { $0 + 2 } ?? 1
        return lastUsedRow + 1
    }
}
