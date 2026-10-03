//
//  SheetsSpreadsheetSetupService.swift
//  SplitNote
//

import Foundation

/// Creates a workspace's spreadsheet and keeps its month tabs in sync with
/// the hidden template tab (`_Mẫu`) — the header/"Tổng cộng" formula/category
/// dropdown, migrating older tabs, and refreshing family columns via
/// `SheetsMembersService`.
struct SheetsSpreadsheetSetupService {
    private let summaryService: SheetsSummaryService
    private let membersService: SheetsMembersService

    nonisolated init(summaryService: SheetsSummaryService, membersService: SheetsMembersService) {
        self.summaryService = summaryService
        self.membersService = membersService
    }

    func createSpreadsheet(title: String, firstTabTitle: String, members: [String]) async throws -> CreatedSpreadsheet {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()

        // 1. Tạo spreadsheet chỉ với tab mẫu — chính là "base" sẽ nhân bản ra
        // tab tháng đầu tiên (và mọi tab tháng sau này).
        var request = URLRequest(url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "properties": ["title": title],
            "sheets": [
                ["properties": ["title": SheetsLayout.templateTabTitle, "gridProperties": ["frozenRowCount": 1]]]
            ]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try SheetsHTTP.validate(response, data: data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let spreadsheetId = json["spreadsheetId"] as? String,
            let urlString = json["spreadsheetUrl"] as? String,
            let url = URL(string: urlString),
            let sheets = json["sheets"] as? [[String: Any]],
            let templateProperties = sheets.first?["properties"] as? [String: Any],
            let templateSheetId = templateProperties["sheetId"] as? Int
        else {
            throw SheetsServiceError.invalidResponse
        }

        // 2. Header + tổng + dropdown ngay trên tab mẫu.
        try await writeHeaderAndTotal(spreadsheetId: spreadsheetId, tabTitle: SheetsLayout.templateTabTitle, accessToken: accessToken)
        try await applyCategoryValidation(spreadsheetId: spreadsheetId, sheetId: templateSheetId, accessToken: accessToken)
        if !members.isEmpty {
            try await membersService.writeFamilyBlocks(spreadsheetId: spreadsheetId, tabTitle: SheetsLayout.templateTabTitle, sheetId: templateSheetId, members: members, accessToken: accessToken)
        }

        // 3. Nhân bản tab mẫu thành tab tháng đầu tiên, rồi mới ẩn tab mẫu — Google không cho ẩn tab duy nhất.
        try await duplicateTemplateTab(spreadsheetId: spreadsheetId, templateSheetId: templateSheetId, newTitle: firstTabTitle, accessToken: accessToken)
        try await setSheetHidden(spreadsheetId: spreadsheetId, sheetId: templateSheetId, hidden: true, accessToken: accessToken)

        // 4. Tab "Tổng hợp" ghim đầu + hàng công thức cho tháng đầu tiên.
        try await summaryService.createSummaryTab(spreadsheetId: spreadsheetId, accessToken: accessToken)
        try await summaryService.ensureSummaryRow(spreadsheetId: spreadsheetId, tabTitle: firstTabTitle, accessToken: accessToken)

        // 5. Danh sách thành viên ghi thẳng vào sheet (không phải local) —
        // để bất kỳ ai mở đúng spreadsheet này (kể cả từ thiết bị khác, một
        // khi mời qua tài khoản Google thật xong) đều thấy cùng một danh sách.
        if !members.isEmpty {
            try await membersService.setMembers(spreadsheetId: spreadsheetId, members: members, accessToken: accessToken)
        }

        return CreatedSpreadsheet(spreadsheetId: spreadsheetId, url: url)
    }

    func ensureTab(spreadsheetId: String, tabTitle: String) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        let sheetIds = try await fetchSheetIds(spreadsheetId: spreadsheetId, accessToken: accessToken)

        // 1. Spreadsheet tạo trước khi có tab "Tổng hợp" chưa có tab này —
        // tạo bù để dashboard luôn có chỗ đọc.
        if sheetIds[SheetsLayout.summaryTabTitle] == nil {
            try await summaryService.createSummaryTab(spreadsheetId: spreadsheetId, accessToken: accessToken)
        }
        // 2. Nguồn thật của danh sách thành viên là chính sheet này — đọc
        // lại mỗi lần để phản ánh đúng thay đổi từ bất kỳ thiết bị nào.
        let members = try await membersService.fetchMembers(spreadsheetId: spreadsheetId, accessToken: accessToken)

        // 3. Chưa có tab tháng này thì nhân bản từ tab mẫu; đã có thì
        // migrate/refresh tab hiện tại.
        guard let existingSheetId = sheetIds[tabTitle] else {
            try await createMonthTab(spreadsheetId: spreadsheetId, tabTitle: tabTitle, sheetIds: sheetIds, members: members, accessToken: accessToken)
            return
        }
        try await migrateLegacyColumnOrderIfNeeded(spreadsheetId: spreadsheetId, tabTitle: tabTitle, sheetId: existingSheetId, accessToken: accessToken)
        // Tab tháng có thể được tạo trước khi "Tổng hợp" tồn tại — đảm bảo
        // vẫn có hàng tương ứng dù không rơi vào nhánh "tạo mới" ở trên.
        try await summaryService.ensureSummaryRow(spreadsheetId: spreadsheetId, tabTitle: tabTitle, accessToken: accessToken)
        // Ghi lại trực tiếp trên tab đang xem, khỏi phải chờ tạo tab mới mới thấy cập nhật.
        if !members.isEmpty {
            try await membersService.writeFamilyBlocks(spreadsheetId: spreadsheetId, tabTitle: tabTitle, sheetId: existingSheetId, members: members, accessToken: accessToken)
        }
    }

    /// Nhân bản tab mẫu (_Mẫu) thành tab tháng mới — đảm bảo tab tháng nào
    /// cũng giống hệt nhau thay vì tự dựng lại header/tổng/dropdown.
    private func createMonthTab(spreadsheetId: String, tabTitle: String, sheetIds: [String: Int], members: [String], accessToken: String) async throws {
        // 1. Lấy sheetId tab mẫu, tạo bù nếu spreadsheet cũ chưa có tab này.
        let templateSheetId = try await resolveTemplateSheetId(spreadsheetId: spreadsheetId, sheetIds: sheetIds, accessToken: accessToken)
        // 2. Ghi khối gia đình lên tab mẫu trước khi nhân bản, để tab tháng
        // mới luôn mang danh sách thành viên mới nhất.
        if !members.isEmpty {
            try await membersService.writeFamilyBlocks(spreadsheetId: spreadsheetId, tabTitle: SheetsLayout.templateTabTitle, sheetId: templateSheetId, members: members, accessToken: accessToken)
        }
        // 3. Nhân bản tab mẫu thành tab tháng mới.
        try await duplicateTemplateTab(spreadsheetId: spreadsheetId, templateSheetId: templateSheetId, newTitle: tabTitle, accessToken: accessToken)
        // 4. Ghi hàng công thức tương ứng vào "Tổng hợp".
        try await summaryService.ensureSummaryRow(spreadsheetId: spreadsheetId, tabTitle: tabTitle, accessToken: accessToken)
    }

    /// Trả về sheetId tab mẫu, tạo bù (header/tổng/dropdown, rồi ẩn đi) nếu
    /// spreadsheet cũ chưa có tab mẫu.
    private func resolveTemplateSheetId(spreadsheetId: String, sheetIds: [String: Int], accessToken: String) async throws -> Int {
        guard let existingTemplateId = sheetIds[SheetsLayout.templateTabTitle] else {
            let templateSheetId = try await addTab(spreadsheetId: spreadsheetId, tabTitle: SheetsLayout.templateTabTitle, accessToken: accessToken)
            try await writeHeaderAndTotal(spreadsheetId: spreadsheetId, tabTitle: SheetsLayout.templateTabTitle, accessToken: accessToken)
            try await applyCategoryValidation(spreadsheetId: spreadsheetId, sheetId: templateSheetId, accessToken: accessToken)
            try await setSheetHidden(spreadsheetId: spreadsheetId, sheetId: templateSheetId, hidden: true, accessToken: accessToken)
            return templateSheetId
        }
        return existingTemplateId
    }

    /// Tab tạo trước khi đổi thứ tự cột (B=Nội dung, C=Loại) vẫn giữ dữ liệu
    /// ở vị trí cũ — hoán đổi lại rồi ghi header mới, tránh lẫn 2 schema trong 1 tab.
    private func migrateLegacyColumnOrderIfNeeded(spreadsheetId: String, tabTitle: String, sheetId: Int, accessToken: String) async throws {
        guard try await hasLegacyColumnOrder(spreadsheetId: spreadsheetId, tabTitle: tabTitle, accessToken: accessToken) else { return }
        try await migrateLegacyColumnOrder(spreadsheetId: spreadsheetId, tabTitle: tabTitle, accessToken: accessToken)
        try await applyCategoryValidation(spreadsheetId: spreadsheetId, sheetId: sheetId, accessToken: accessToken)
    }

    /// Maps every existing tab's title to its Google-assigned sheetId.
    private func fetchSheetIds(spreadsheetId: String, accessToken: String) async throws -> [String: Int] {
        var request = URLRequest(url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)?fields=sheets.properties(title,sheetId)")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try SheetsHTTP.validate(response, data: data)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sheets = json["sheets"] as? [[String: Any]]
        else {
            throw SheetsServiceError.invalidResponse
        }
        var result: [String: Int] = [:]
        for sheet in sheets {
            guard
                let properties = sheet["properties"] as? [String: Any],
                let title = properties["title"] as? String,
                let sheetId = properties["sheetId"] as? Int
            else { continue }
            result[title] = sheetId
        }
        return result
    }

    /// Old schema had column B = Nội dung, C = Loại (swapped vs. the current header).
    private func hasLegacyColumnOrder(spreadsheetId: String, tabTitle: String, accessToken: String) async throws -> Bool {
        guard
            let encodedTitle = SheetsHTTP.percentEncodedTabTitle(tabTitle),
            let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!B1:B1")
        else {
            throw SheetsServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try SheetsHTTP.validate(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SheetsServiceError.invalidResponse
        }
        let headerB = (json["values"] as? [[String]])?.first?.first
        return headerB == "Nội dung"
    }

    /// Swaps columns B/C for every existing data row, then rewrites the
    /// header to the current column order.
    private func migrateLegacyColumnOrder(spreadsheetId: String, tabTitle: String, accessToken: String) async throws {
        guard
            let encodedTitle = SheetsHTTP.percentEncodedTabTitle(tabTitle),
            let readURL = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!B2:C10000")
        else {
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

        if !rows.isEmpty {
            let swapped = rows.map { row -> [String] in
                let content = row.first ?? ""
                let category = row.count > 1 ? row[1] : ""
                return [category, content]
            }
            guard let writeURL = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/'\(encodedTitle)'!B2:C10000?valueInputOption=USER_ENTERED") else {
                throw SheetsServiceError.invalidResponse
            }
            var writeRequest = URLRequest(url: writeURL)
            writeRequest.httpMethod = "PUT"
            writeRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            writeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            writeRequest.httpBody = try JSONSerialization.data(withJSONObject: ["values": swapped])
            let (writeData, writeResponse) = try await URLSession.shared.data(for: writeRequest)
            try SheetsHTTP.validate(writeResponse, data: writeData)
        }

        try await writeHeaderAndTotal(spreadsheetId: spreadsheetId, tabTitle: tabTitle, accessToken: accessToken)
    }

    /// Returns the new tab's Google-assigned sheetId, needed to scope the
    /// category dropdown to it afterwards.
    private func addTab(spreadsheetId: String, tabTitle: String, accessToken: String) async throws -> Int {
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
        try SheetsHTTP.validate(response, data: data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let replies = json["replies"] as? [[String: Any]],
            let addSheet = replies.first?["addSheet"] as? [String: Any],
            let properties = addSheet["properties"] as? [String: Any],
            let sheetId = properties["sheetId"] as? Int
        else {
            throw SheetsServiceError.invalidResponse
        }
        return sheetId
    }

    /// Duplicates the (hidden) template tab into a new, visible tab named
    /// `newTitle` — copies its header row, "Tổng cộng" formula and category
    /// dropdown validation in one call, so the new tab can never drift from
    /// the template.
    private func duplicateTemplateTab(spreadsheetId: String, templateSheetId: Int, newTitle: String, accessToken: String) async throws {
        var request = URLRequest(url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId):batchUpdate")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "requests": [
                [
                    "duplicateSheet": [
                        "sourceSheetId": templateSheetId,
                        // Thiếu index thì Google chèn lên đầu, đẩy "Tổng hợp" (ghim ở 0) xuống.
                        "insertSheetIndex": 1,
                        "newSheetName": newTitle
                    ]
                ]
            ]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try SheetsHTTP.validate(response, data: data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let replies = json["replies"] as? [[String: Any]],
            let duplicateSheet = replies.first?["duplicateSheet"] as? [String: Any],
            let properties = duplicateSheet["properties"] as? [String: Any],
            let newSheetId = properties["sheetId"] as? Int
        else {
            throw SheetsServiceError.invalidResponse
        }
        // Phòng trường hợp bản sao thừa kế luôn trạng thái ẩn của tab mẫu —
        // tab tháng thật phải luôn hiện.
        try await setSheetHidden(spreadsheetId: spreadsheetId, sheetId: newSheetId, hidden: false, accessToken: accessToken)
    }

    private func setSheetHidden(spreadsheetId: String, sheetId: Int, hidden: Bool, accessToken: String) async throws {
        var request = URLRequest(url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId):batchUpdate")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "requests": [
                [
                    "updateSheetProperties": [
                        "properties": ["sheetId": sheetId, "hidden": hidden],
                        "fields": "hidden"
                    ]
                ]
            ]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try SheetsHTTP.validate(response, data: data)
    }

    /// Restricts column B (Loại) to `categoryValues` via a dropdown rule.
    private func applyCategoryValidation(spreadsheetId: String, sheetId: Int, accessToken: String) async throws {
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
                            "startColumnIndex": 1,
                            "endColumnIndex": 2
                        ],
                        "rule": [
                            "condition": [
                                "type": "ONE_OF_LIST",
                                "values": SheetsLayout.categoryValues.map { ["userEnteredValue": $0] }
                            ],
                            "strict": true,
                            "showCustomUi": true
                        ]
                    ]
                ]
            ]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try SheetsHTTP.validate(response, data: data)
    }

    /// Writes the A1:E1 header and G1/G2 "Tổng cộng" label + `SUM` formula.
    /// `USER_ENTERED` (not `RAW`) so the formula actually evaluates.
    private func writeHeaderAndTotal(spreadsheetId: String, tabTitle: String, accessToken: String) async throws {
        var request = URLRequest(url: URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values:batchUpdate")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "valueInputOption": "USER_ENTERED",
            "data": [
                ["range": SheetsHTTP.bodyRange(tabTitle: tabTitle, cells: "A1:E1"), "values": [SheetsLayout.headerColumns]],
                ["range": SheetsHTTP.bodyRange(tabTitle: tabTitle, cells: "G1:G2"), "values": [[SheetsLayout.totalLabel], [SheetsLayout.totalFormula]]]
            ]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try SheetsHTTP.validate(response, data: data)
    }
}
