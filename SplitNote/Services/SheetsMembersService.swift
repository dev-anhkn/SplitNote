//
//  SheetsMembersService.swift
//  SplitNote
//

import Foundation

/// Owns the `.family` member list stored in "Tổng hợp", and the per-tab
/// family columns/balance table derived from it.
struct SheetsMembersService {
    nonisolated init() {}

    /// Source of truth is the sheet itself, not a per-device cache, so every device sees the same list.
    func fetchMembers(spreadsheetId: String) async throws -> [String] {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        return try await fetchMembers(spreadsheetId: spreadsheetId, accessToken: accessToken)
    }

    /// Callers must call `ensureTab` afterwards to refresh the currently open tab's family block.
    func setMembers(spreadsheetId: String, members: [String]) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        try await setMembers(spreadsheetId: spreadsheetId, members: members, accessToken: accessToken)
    }

    /// Reads the member list from its column in "Tổng hợp". `.notFound` means
    /// that tab doesn't exist yet on this spreadsheet (predates the feature)
    /// — same as "no members" rather than an error.
    func fetchMembers(spreadsheetId: String, accessToken: String) async throws -> [String] {
        guard
            let encodedTitle = SheetsHTTP.percentEncodedTabTitle(SheetsLayout.summaryTabTitle),
            let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!\(SheetsLayout.membersColumn)2:\(SheetsLayout.membersColumn)200")
        else {
            throw SheetsServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        do {
            try SheetsHTTP.validate(response, data: data)
        } catch SheetsServiceError.notFound {
            return []
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SheetsServiceError.invalidResponse
        }
        let rows = json["values"] as? [[String]] ?? []
        return rows.compactMap(\.first).filter { !$0.isEmpty }
    }

    /// Rewrites the member list wholesale — simpler than diffing who was
    /// added/removed.
    func setMembers(spreadsheetId: String, members: [String], accessToken: String) async throws {
        guard let encodedTitle = SheetsHTTP.percentEncodedTabTitle(SheetsLayout.summaryTabTitle) else {
            throw SheetsServiceError.invalidResponse
        }
        guard let clearURL = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!\(SheetsLayout.membersColumn)1:\(SheetsLayout.membersColumn)200:clear") else {
            throw SheetsServiceError.invalidResponse
        }
        var clearRequest = URLRequest(url: clearURL)
        clearRequest.httpMethod = "POST"
        clearRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        clearRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        clearRequest.httpBody = try JSONSerialization.data(withJSONObject: [String: Any]())
        let (clearData, clearResponse) = try await URLSession.shared.data(for: clearRequest)
        try SheetsHTTP.validate(clearResponse, data: clearData)

        guard !members.isEmpty else { return }
        guard let writeURL = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!\(SheetsLayout.membersColumn)1:\(SheetsLayout.membersColumn)\(members.count + 1)?valueInputOption=USER_ENTERED") else {
            throw SheetsServiceError.invalidResponse
        }
        var writeRequest = URLRequest(url: writeURL)
        writeRequest.httpMethod = "PUT"
        writeRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        writeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        writeRequest.httpBody = try JSONSerialization.data(withJSONObject: ["values": ([SheetsLayout.membersHeaderLabel] + members).map { [$0] }])
        let (writeData, writeResponse) = try await URLSession.shared.data(for: writeRequest)
        try SheetsHTTP.validate(writeResponse, data: writeData)
    }

    /// Rewrites the family header/balance table wholesale — simpler than
    /// diffing added/removed members. Formulas have no sheet-name prefix, so
    /// they keep pointing at their own tab even after `duplicateSheet`.
    func writeFamilyBlocks(spreadsheetId: String, tabTitle: String, sheetId: Int, members: [String], accessToken: String) async throws {
        guard let encodedTitle = SheetsHTTP.percentEncodedTabTitle(tabTitle) else {
            throw SheetsServiceError.invalidResponse
        }

        // 1. Ghi header I1:K1 (gia đình) + M1:P1 (bảng cân đối).
        var headerRequest = URLRequest(url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values:batchUpdate")!)
        headerRequest.httpMethod = "POST"
        headerRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        headerRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headerRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "valueInputOption": "USER_ENTERED",
            "data": [
                ["range": "'\(encodedTitle)'!I1:K1", "values": [SheetsLayout.familyHeaderColumns]],
                ["range": "'\(encodedTitle)'!M1:P1", "values": [SheetsLayout.balanceHeaderColumns]]
            ]
        ])
        let (headerData, headerResponse) = try await URLSession.shared.data(for: headerRequest)
        try SheetsHTTP.validate(headerResponse, data: headerData)

        // 2. Gợi ý members làm dropdown cho cột "Ai chi".
        try await applyMemberValidation(spreadsheetId: spreadsheetId, sheetId: sheetId, members: members, accessToken: accessToken)

        // 3. Xoá bảng cân đối cũ trước — đơn giản hơn diff xem thành viên nào
        // bị bớt — rồi ghi lại đúng số dòng theo danh sách hiện tại.
        guard let clearURL = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!M2:P200:clear") else {
            throw SheetsServiceError.invalidResponse
        }
        var clearRequest = URLRequest(url: clearURL)
        clearRequest.httpMethod = "POST"
        clearRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        clearRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        clearRequest.httpBody = try JSONSerialization.data(withJSONObject: [String: Any]())
        let (clearData, clearResponse) = try await URLSession.shared.data(for: clearRequest)
        try SheetsHTTP.validate(clearResponse, data: clearData)

        // 4. Tính lại từng dòng cân đối rồi ghi đè.
        let balanceRows: [[String]] = members.enumerated().map { offset, member in
            let row = offset + 2
            // "" escaped thành "" gấp đôi — phòng trường hợp tên có dấu ngoặc kép.
            let escapedMember = member.replacingOccurrences(of: "\"", with: "\"\"")
            return [
                member,
                "=SUMIF(I:I,\"\(escapedMember)\",D:D)",
                "=SUMPRODUCT(ISNUMBER(SEARCH(\",\"&\"\(escapedMember)\"&\",\",\",\"&J2:J10000&\",\"))*IFERROR(D2:D10000/K2:K10000,0))",
                "=N\(row)-O\(row)"
            ]
        }
        guard let writeURL = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!M2:P\(members.count + 1)?valueInputOption=USER_ENTERED") else {
            throw SheetsServiceError.invalidResponse
        }
        var writeRequest = URLRequest(url: writeURL)
        writeRequest.httpMethod = "PUT"
        writeRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        writeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        writeRequest.httpBody = try JSONSerialization.data(withJSONObject: ["values": balanceRows])
        let (writeData, writeResponse) = try await URLSession.shared.data(for: writeRequest)
        try SheetsHTTP.validate(writeResponse, data: writeData)
    }

    /// Suggests (but doesn't strictly enforce — Sheets has no multi-select
    /// dropdown, so "Chi cho ai" has to stay free text anyway) `members` as
    /// the dropdown for column I (Ai chi).
    private func applyMemberValidation(spreadsheetId: String, sheetId: Int, members: [String], accessToken: String) async throws {
        var request = URLRequest(url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId):batchUpdate")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "requests": [
                [
                    "setDataValidation": [
                        "range": [
                            "sheetId": sheetId,
                            "startRowIndex": 1,
                            "startColumnIndex": 8,
                            "endColumnIndex": 9
                        ],
                        "rule": [
                            "condition": [
                                "type": "ONE_OF_LIST",
                                "values": members.map { ["userEnteredValue": $0] }
                            ],
                            "strict": false,
                            "showCustomUi": true
                        ]
                    ]
                ]
            ]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try SheetsHTTP.validate(response, data: data)
    }
}
