//
//  SheetsService.swift
//  SplitNote
//

import Foundation

enum SheetsServiceError: Error, LocalizedError {
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Google Sheets returned an unexpected response."
        case .requestFailed(let message):
            return message
        }
    }
}

struct CreatedSpreadsheet {
    let spreadsheetId: String
    let url: URL
}

protocol SheetsServiceProtocol {
    /// Creates the one spreadsheet a workspace lives in, seeded with a first
    /// tab (e.g. the current month).
    func createSpreadsheet(title: String, firstTabTitle: String) async throws -> CreatedSpreadsheet
    /// Adds `tabTitle` as a new sheet inside an existing spreadsheet if it
    /// isn't already there. No-op when the tab already exists — safe to call
    /// on every app launch.
    func ensureTab(spreadsheetId: String, tabTitle: String) async throws
    /// Appends one expense row under the header of `tabTitle`.
    func appendRow(spreadsheetId: String, tabTitle: String, date: String, content: String, category: String, amount: String) async throws
}

/// Talks to the Google Sheets API using the access token of the currently
/// signed-in `GIDGoogleUser`. Requires the `sheetsScope` requested in
/// `GoogleAuthService.performSignIn()`.
struct SheetsService: SheetsServiceProtocol {

    nonisolated init() {}

    /// The template every SplitNote tab starts with: the fields a parsed
    /// note maps onto, plus a running total in column F.
    private static let headerColumns = ["Ngày", "Nội dung", "Loại", "Số tiền"]
    private static let totalLabel = "Tổng cộng"
    private static let totalFormula = "=SUM(D2:D10000)"

    func createSpreadsheet(title: String, firstTabTitle: String) async throws -> CreatedSpreadsheet {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()

        var request = URLRequest(url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.createBody(title: title, tabTitle: firstTabTitle))

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let spreadsheetId = json["spreadsheetId"] as? String,
            let urlString = json["spreadsheetUrl"] as? String,
            let url = URL(string: urlString)
        else {
            throw SheetsServiceError.invalidResponse
        }
        return CreatedSpreadsheet(spreadsheetId: spreadsheetId, url: url)
    }

    func ensureTab(spreadsheetId: String, tabTitle: String) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()

        let existingTitles = try await Self.fetchTabTitles(spreadsheetId: spreadsheetId, accessToken: accessToken)
        guard !existingTitles.contains(tabTitle) else { return }

        try await Self.addTab(spreadsheetId: spreadsheetId, tabTitle: tabTitle, accessToken: accessToken)
        try await Self.writeHeaderAndTotal(spreadsheetId: spreadsheetId, tabTitle: tabTitle, accessToken: accessToken)
    }

    func appendRow(spreadsheetId: String, tabTitle: String, date: String, content: String, category: String, amount: String) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        guard let encodedTitle = Self.percentEncodedTabTitle(tabTitle) else {
            throw SheetsServiceError.invalidResponse
        }
        guard let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!A1:D1:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS") else {
            throw SheetsServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "values": [[date, content, category, amount]]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response, data: data)
    }

    // MARK: - Requests

    private static func fetchTabTitles(spreadsheetId: String, accessToken: String) async throws -> Set<String> {
        var request = URLRequest(url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)?fields=sheets.properties.title")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sheets = json["sheets"] as? [[String: Any]]
        else {
            throw SheetsServiceError.invalidResponse
        }
        let titles = sheets.compactMap { ($0["properties"] as? [String: Any])?["title"] as? String }
        return Set(titles)
    }

    private static func addTab(spreadsheetId: String, tabTitle: String, accessToken: String) async throws {
        var request = URLRequest(url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId):batchUpdate")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "requests": [
                [
                    "addSheet": [
                        "properties": [
                            "title": tabTitle,
                            "gridProperties": ["frozenRowCount": 1]
                        ]
                    ]
                ]
            ]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
    }

    /// Writes the A1:D1 header and the F1/F2 "Tổng cộng" label + `SUM`
    /// formula in one call via the values `batchUpdate` endpoint.
    /// `USER_ENTERED` is required (not `RAW`) so the formula actually
    /// evaluates instead of being stored as literal text.
    private static func writeHeaderAndTotal(spreadsheetId: String, tabTitle: String, accessToken: String) async throws {
        guard let encodedTitle = percentEncodedTabTitle(tabTitle) else {
            throw SheetsServiceError.invalidResponse
        }
        var request = URLRequest(url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values:batchUpdate")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "valueInputOption": "USER_ENTERED",
            "data": [
                ["range": "'\(encodedTitle)'!A1:D1", "values": [headerColumns]],
                ["range": "'\(encodedTitle)'!F1:F2", "values": [[totalLabel], [totalFormula]]]
            ]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
    }

    /// Builds a `spreadsheets.create` body that seeds the first tab with a
    /// bold, frozen header row plus the "Tổng cộng" total cell, in one request.
    private static func createBody(title: String, tabTitle: String) -> [String: Any] {
        let headerValues = headerColumns.map { column in
            [
                "userEnteredValue": ["stringValue": column],
                "userEnteredFormat": ["textFormat": ["bold": true]]
            ] as [String: Any]
        }
        let totalValues: [[String: Any]] = [
            ["values": [["userEnteredValue": ["stringValue": totalLabel], "userEnteredFormat": ["textFormat": ["bold": true]]]]],
            ["values": [["userEnteredValue": ["formulaValue": totalFormula]]]]
        ]

        return [
            "properties": ["title": title],
            "sheets": [
                [
                    "properties": [
                        "title": tabTitle,
                        "gridProperties": ["frozenRowCount": 1]
                    ],
                    "data": [
                        [
                            "startRow": 0,
                            "startColumn": 0,
                            "rowData": [
                                ["values": headerValues]
                            ]
                        ],
                        [
                            "startRow": 0,
                            "startColumn": 5, // column F
                            "rowData": totalValues
                        ]
                    ]
                ]
            ]
        ]
    }

    /// Tab titles never contain "/" (month titles use "-"), so `.urlPathAllowed`
    /// is safe to percent-encode them with for use inside an A1 range.
    private static func percentEncodedTabTitle(_ tabTitle: String) -> String? {
        tabTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SheetsServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw SheetsServiceError.requestFailed(message)
        }
    }

}
