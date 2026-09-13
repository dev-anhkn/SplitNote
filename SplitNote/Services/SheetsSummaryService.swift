//
//  SheetsSummaryService.swift
//  SplitNote
//

import Foundation

/// Reads/writes the "Tổng hợp" tab — the one place every month's total and
/// per-category breakdown live as formulas referencing that month's own tab.
struct SheetsSummaryService {
    nonisolated init() {}

    /// Reads column A (tab title) and B (that month's total formula result)
    /// of every row in "Tổng hợp" — one request for however many months are
    /// being displayed. Throws `.notFound` if the tab doesn't exist yet
    /// (spreadsheet predates it and hasn't been reopened since).
    func fetchMonthlyTotals(spreadsheetId: String) async throws -> [(tabTitle: String, total: Decimal)] {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        guard let encodedTitle = SheetsHTTP.percentEncodedTabTitle(SheetsLayout.summaryTabTitle) else {
            throw SheetsServiceError.invalidResponse
        }
        guard let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!A2:B1000") else {
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
        return rows.compactMap { row in
            guard let tabTitle = row.first, !tabTitle.isEmpty else { return nil }
            let amountText = row.indices.contains(1) ? row[1] : ""
            let amountDigits = amountText.filter { $0.isNumber || $0 == "-" }
            return (tabTitle: tabTitle, total: Decimal(string: amountDigits) ?? 0)
        }
    }

    /// Reads the row for `tabTitle` from "Tổng hợp" and pairs each category
    /// column with its `SUMIF` result, keeping only categories with a
    /// non-zero total. Throws `.notFound` if the tab doesn't exist yet.
    func fetchCategoryTotals(spreadsheetId: String, tabTitle: String) async throws -> [(category: String, total: Decimal)] {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        guard let encodedTitle = SheetsHTTP.percentEncodedTabTitle(SheetsLayout.summaryTabTitle) else {
            throw SheetsServiceError.invalidResponse
        }
        let lastColumn = SheetsHTTP.columnLetter(SheetsLayout.summaryHeaderColumns.count)
        guard let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!A2:\(lastColumn)1000") else {
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
        guard let row = rows.first(where: { $0.first == tabTitle }) else { return [] }
        // Cột 0 = Tháng, cột 1 = Tổng cộng, cột 2 trở đi = từng category.
        return SheetsLayout.categoryValues.enumerated().compactMap { offset, category in
            let columnIndex = offset + 2
            guard row.indices.contains(columnIndex) else { return nil }
            let amountDigits = row[columnIndex].filter { $0.isNumber || $0 == "-" }
            guard let total = Decimal(string: amountDigits), total > 0 else { return nil }
            return (category: category, total: total)
        }
        .sorted { $0.total > $1.total }
    }

    /// Adds the "Tổng hợp" tab to an existing spreadsheet, pinned as the
    /// first tab, with just its header row — used when migrating a
    /// spreadsheet that predates this tab.
    func createSummaryTab(spreadsheetId: String, accessToken: String) async throws {
        var request = URLRequest(url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId):batchUpdate")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "requests": [
                [
                    "addSheet": [
                        "properties": [
                            "title": SheetsLayout.summaryTabTitle,
                            "index": 0,
                            "gridProperties": ["frozenRowCount": 1]
                        ]
                    ]
                ]
            ]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try SheetsHTTP.validate(response, data: data)

        guard let encodedTitle = SheetsHTTP.percentEncodedTabTitle(SheetsLayout.summaryTabTitle) else {
            throw SheetsServiceError.invalidResponse
        }
        let lastColumn = SheetsHTTP.columnLetter(SheetsLayout.summaryHeaderColumns.count)
        guard let headerURL = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!A1:\(lastColumn)1?valueInputOption=USER_ENTERED") else {
            throw SheetsServiceError.invalidResponse
        }
        var headerRequest = URLRequest(url: headerURL)
        headerRequest.httpMethod = "PUT"
        headerRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        headerRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headerRequest.httpBody = try JSONSerialization.data(withJSONObject: ["values": [SheetsLayout.summaryHeaderColumns]])
        let (headerData, headerResponse) = try await URLSession.shared.data(for: headerRequest)
        try SheetsHTTP.validate(headerResponse, data: headerData)
    }

    /// Appends a formula row into "Tổng hợp" for `tabTitle` if it doesn't
    /// already have one. Every cell is a formula referencing that month's
    /// own tab directly (`SUM`/`SUMIF`), so it stays correct on its own as
    /// entries in that month are added/edited/deleted — nothing here ever
    /// needs to be rewritten afterwards.
    func ensureSummaryRow(spreadsheetId: String, tabTitle: String, accessToken: String) async throws {
        guard let encodedSummaryTitle = SheetsHTTP.percentEncodedTabTitle(SheetsLayout.summaryTabTitle) else {
            throw SheetsServiceError.invalidResponse
        }
        guard let readURL = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedSummaryTitle)'!A2:A1000") else {
            throw SheetsServiceError.invalidResponse
        }
        var readRequest = URLRequest(url: readURL)
        readRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (readData, readResponse) = try await URLSession.shared.data(for: readRequest)
        try SheetsHTTP.validate(readResponse, data: readData)
        guard let json = try JSONSerialization.jsonObject(with: readData) as? [String: Any] else {
            throw SheetsServiceError.invalidResponse
        }
        let rows = json["values"] as? [[String]] ?? []
        guard !rows.contains(where: { $0.first == tabTitle }) else { return }

        let lastUsedRow = rows.lastIndex { !($0.first ?? "").isEmpty }.map { $0 + 2 } ?? 1
        let nextRow = lastUsedRow + 1
        let categoryFormulas: [String] = SheetsLayout.categoryValues.map { category in
            "=SUMIF('\(tabTitle)'!B2:B10000,\"\(category)\",'\(tabTitle)'!D2:D10000)"
        }
        let rowValues: [String] = [tabTitle, "='\(tabTitle)'!\(SheetsLayout.totalColumn)2"] + categoryFormulas
        let lastColumn = SheetsHTTP.columnLetter(SheetsLayout.summaryHeaderColumns.count)
        guard let writeURL = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedSummaryTitle)'!A\(nextRow):\(lastColumn)\(nextRow)?valueInputOption=USER_ENTERED") else {
            throw SheetsServiceError.invalidResponse
        }
        var writeRequest = URLRequest(url: writeURL)
        writeRequest.httpMethod = "PUT"
        writeRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        writeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        writeRequest.httpBody = try JSONSerialization.data(withJSONObject: ["values": [rowValues]])
        let (writeData, writeResponse) = try await URLSession.shared.data(for: writeRequest)
        try SheetsHTTP.validate(writeResponse, data: writeData)
    }
}
