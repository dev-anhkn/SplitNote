//
//  SheetsSpreadsheetSetupService.swift
//  SplitNote
//

import Foundation

/// Tạo spreadsheet của workspace và giữ các tab tháng đồng bộ với tab mẫu `_Mẫu`.
struct SheetsSpreadsheetSetupService {
    private let summaryService: SheetsSummaryService
    private let membersService: SheetsMembersService
    private let migrationService: SheetsLegacyMigrationService

    nonisolated init(summaryService: SheetsSummaryService, membersService: SheetsMembersService, migrationService: SheetsLegacyMigrationService) {
        self.summaryService = summaryService
        self.membersService = membersService
        self.migrationService = migrationService
    }

    func createSpreadsheet(title: String, firstTabTitle: String, members: [String]) async throws -> CreatedSpreadsheet {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        // 1. Tạo spreadsheet chỉ với tab mẫu — "base" để nhân bản ra mọi tab tháng.
        let (created, templateSheetId) = try await postNewSpreadsheet(title: title, accessToken: accessToken)
        let spreadsheetId = created.spreadsheetId
        // 2. Dựng tiêu đề + tổng + dropdown (+ khối gia đình) ngay trên tab mẫu.
        try await setUpTemplateTab(spreadsheetId: spreadsheetId, sheetId: templateSheetId, accessToken: accessToken)
        try await writeFamilyBlocksIfNeeded(spreadsheetId: spreadsheetId, tabTitle: SheetsLayout.templateTabTitle, sheetId: templateSheetId, members: members, accessToken: accessToken)
        // 3. Nhân bản tab mẫu thành tab tháng đầu rồi mới ẩn tab mẫu — Google không cho ẩn tab duy nhất.
        try await duplicateTemplateTab(spreadsheetId: spreadsheetId, templateSheetId: templateSheetId, newTitle: firstTabTitle, insertIndex: 1, accessToken: accessToken)
        try await SheetsHTTP.batchUpdate(spreadsheetId: spreadsheetId, requests: [SheetsRequests.setHidden(sheetId: templateSheetId, hidden: true)], accessToken: accessToken)
        // 4. Tab "Tổng hợp" ghim đầu + hàng công thức cho tháng đầu tiên.
        try await summaryService.createSummaryTab(spreadsheetId: spreadsheetId, accessToken: accessToken)
        try await summaryService.ensureSummaryRow(spreadsheetId: spreadsheetId, tabTitle: firstTabTitle, accessToken: accessToken)
        // 5. Ghi danh sách thành viên thẳng vào sheet để mọi thiết bị mở cùng file đều thấy.
        if !members.isEmpty {
            try await membersService.setMemberList(spreadsheetId: spreadsheetId, names: members, emails: [], accessToken: accessToken)
        }
        return created
    }

    func ensureTab(spreadsheetId: String, tabTitle: String) async throws {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        let sheetIds = try await fetchSheetIds(spreadsheetId: spreadsheetId, accessToken: accessToken)
        // 1. Spreadsheet cũ chưa có "Tổng hợp" thì tạo bù để dashboard luôn có chỗ đọc.
        if sheetIds[SheetsLayout.summaryTabTitle] == nil {
            try await summaryService.createSummaryTab(spreadsheetId: spreadsheetId, accessToken: accessToken)
        }
        // 2. Sửa các tab bị lệch cột từ bản cũ (kể cả tab mẫu) trước khi nhân bản.
        let monthAndTemplateTabs = sheetIds.keys.filter { $0 != SheetsLayout.summaryTabTitle }.sorted()
        try await migrationService.migrateShiftedColumnsIfNeeded(spreadsheetId: spreadsheetId, tabTitles: monthAndTemplateTabs, accessToken: accessToken)
        // 3. Đọc lại thành viên mỗi lần để phản ánh thay đổi từ thiết bị khác.
        let members = try await membersService.fetchMembers(spreadsheetId: spreadsheetId, accessToken: accessToken)
        // 4. Chưa có tab tháng này thì nhân bản từ tab mẫu.
        guard let existingSheetId = sheetIds[tabTitle] else {
            try await createMonthTab(spreadsheetId: spreadsheetId, tabTitle: tabTitle, sheetIds: sheetIds, members: members, accessToken: accessToken)
            return
        }
        // 5. Đã có thì migrate + làm mới tab hiện tại.
        try await refreshMonthTab(spreadsheetId: spreadsheetId, tabTitle: tabTitle, sheetId: existingSheetId, members: members, accessToken: accessToken)
    }

    // MARK: - Tab tháng

    /// Nhân bản tab mẫu thành tab tháng mới để tab nào cũng giống hệt nhau.
    private func createMonthTab(spreadsheetId: String, tabTitle: String, sheetIds: [String: Int], members: [String], accessToken: String) async throws {
        // 1. Lấy sheetId tab mẫu (tạo bù nếu spreadsheet cũ chưa có).
        let templateSheetId = try await resolveTemplateSheetId(spreadsheetId: spreadsheetId, sheetIds: sheetIds, accessToken: accessToken)
        // 2. Ghi khối gia đình lên tab mẫu trước để tab mới mang danh sách thành viên mới nhất.
        try await writeFamilyBlocksIfNeeded(spreadsheetId: spreadsheetId, tabTitle: SheetsLayout.templateTabTitle, sheetId: templateSheetId, members: members, accessToken: accessToken)
        // 3. Chèn ở cuối — dư 1 index phòng vừa tạo bù tab mẫu (Sheets tự kẹp về cuối nếu vượt).
        try await duplicateTemplateTab(spreadsheetId: spreadsheetId, templateSheetId: templateSheetId, newTitle: tabTitle, insertIndex: sheetIds.count + 1, accessToken: accessToken)
        // 4. Ghi hàng công thức tương ứng vào "Tổng hợp".
        try await summaryService.ensureSummaryRow(spreadsheetId: spreadsheetId, tabTitle: tabTitle, accessToken: accessToken)
    }

    private func refreshMonthTab(spreadsheetId: String, tabTitle: String, sheetId: Int, members: [String], accessToken: String) async throws {
        // 1. Tab tạo trước khi đổi thứ tự cột thì đổi lại, kèm áp lại dropdown Loại.
        if try await migrationService.migrateSwappedColumnsIfNeeded(spreadsheetId: spreadsheetId, tabTitle: tabTitle, accessToken: accessToken) {
            try await SheetsHTTP.batchUpdate(spreadsheetId: spreadsheetId, requests: [SheetsRequests.categoryValidation(sheetId: sheetId)], accessToken: accessToken)
        }
        // 2. Tab có thể có trước "Tổng hợp" — đảm bảo vẫn có hàng tương ứng.
        try await summaryService.ensureSummaryRow(spreadsheetId: spreadsheetId, tabTitle: tabTitle, accessToken: accessToken)
        // 3. Ghi lại khối gia đình ngay trên tab đang xem.
        try await writeFamilyBlocksIfNeeded(spreadsheetId: spreadsheetId, tabTitle: tabTitle, sheetId: sheetId, members: members, accessToken: accessToken)
    }

    private func writeFamilyBlocksIfNeeded(spreadsheetId: String, tabTitle: String, sheetId: Int, members: [String], accessToken: String) async throws {
        guard !members.isEmpty else { return }
        try await membersService.writeFamilyBlocks(spreadsheetId: spreadsheetId, tabTitle: tabTitle, sheetId: sheetId, members: members, accessToken: accessToken)
    }

    // MARK: - Tab mẫu

    /// Trả về sheetId tab mẫu, tạo bù (rồi ẩn đi) nếu spreadsheet cũ chưa có.
    private func resolveTemplateSheetId(spreadsheetId: String, sheetIds: [String: Int], accessToken: String) async throws -> Int {
        if let existingTemplateId = sheetIds[SheetsLayout.templateTabTitle] {
            return existingTemplateId
        }
        let replies = try await SheetsHTTP.batchUpdate(spreadsheetId: spreadsheetId, requests: [SheetsRequests.addSheet(title: SheetsLayout.templateTabTitle)], accessToken: accessToken)
        guard let templateSheetId = Self.sheetId(in: replies.first?["addSheet"] as? [String: Any]) else {
            throw SheetsServiceError.invalidResponse
        }
        try await setUpTemplateTab(spreadsheetId: spreadsheetId, sheetId: templateSheetId, accessToken: accessToken)
        try await SheetsHTTP.batchUpdate(spreadsheetId: spreadsheetId, requests: [SheetsRequests.setHidden(sheetId: templateSheetId, hidden: true)], accessToken: accessToken)
        return templateSheetId
    }

    /// Tiêu đề + "Tổng cộng" + dropdown Loại cho tab mẫu.
    private func setUpTemplateTab(spreadsheetId: String, sheetId: Int, accessToken: String) async throws {
        try await SheetsHTTP.batchWriteValues(spreadsheetId: spreadsheetId, ranges: SheetsRequests.headerAndTotal(tabTitle: SheetsLayout.templateTabTitle), accessToken: accessToken)
        try await SheetsHTTP.batchUpdate(spreadsheetId: spreadsheetId, requests: [SheetsRequests.categoryValidation(sheetId: sheetId)], accessToken: accessToken)
    }

    // MARK: - Sheets API

    /// Gửi request tạo spreadsheet, trả về kết quả + sheetId của tab mẫu.
    private func postNewSpreadsheet(title: String, accessToken: String) async throws -> (CreatedSpreadsheet, templateSheetId: Int) {
        let body: [String: Any] = [
            // Ép en_US — locale tiếng Việt dùng ";" ngăn tham số làm mọi công thức SUMIF/SUM báo lỗi.
            "properties": ["title": title, "locale": "en_US"],
            "sheets": [
                ["properties": ["title": SheetsLayout.templateTabTitle, "gridProperties": ["frozenRowCount": 1]]]
            ]
        ]
        let url = try SheetsHTTP.spreadsheetURL()
        let json = try await SheetsHTTP.send(url, method: "POST", body: body, accessToken: accessToken)
        guard
            let spreadsheetId = json["spreadsheetId"] as? String,
            let editURL = (json["spreadsheetUrl"] as? String).flatMap(URL.init(string:)),
            let sheets = json["sheets"] as? [[String: Any]],
            let templateSheetId = Self.sheetId(in: sheets.first)
        else {
            throw SheetsServiceError.invalidResponse
        }
        return (CreatedSpreadsheet(spreadsheetId: spreadsheetId, url: editURL), templateSheetId)
    }

    /// Map tên tab → sheetId do Google cấp.
    private func fetchSheetIds(spreadsheetId: String, accessToken: String) async throws -> [String: Int] {
        let url = try SheetsHTTP.spreadsheetURL(spreadsheetId, path: "?fields=sheets.properties(title,sheetId)")
        let json = try await SheetsHTTP.send(url, accessToken: accessToken)
        guard let sheets = json["sheets"] as? [[String: Any]] else {
            throw SheetsServiceError.invalidResponse
        }
        let pairs = sheets.compactMap { sheet -> (String, Int)? in
            guard
                let title = (sheet["properties"] as? [String: Any])?["title"] as? String,
                let sheetId = Self.sheetId(in: sheet)
            else { return nil }
            return (title, sheetId)
        }
        return Dictionary(pairs, uniquingKeysWith: { _, last in last })
    }

    /// `insertIndex` phải truyền tường minh — không thì Sheets có thể chèn lệch trước "Tổng hợp".
    private func duplicateTemplateTab(spreadsheetId: String, templateSheetId: Int, newTitle: String, insertIndex: Int, accessToken: String) async throws {
        // 1. Nhân bản tab mẫu — copy luôn tiêu đề, công thức tổng và dropdown.
        let duplicate = SheetsRequests.duplicateSheet(sourceSheetId: templateSheetId, newTitle: newTitle, insertIndex: insertIndex)
        let replies = try await SheetsHTTP.batchUpdate(spreadsheetId: spreadsheetId, requests: [duplicate], accessToken: accessToken)
        guard let newSheetId = Self.sheetId(in: replies.first?["duplicateSheet"] as? [String: Any]) else {
            throw SheetsServiceError.invalidResponse
        }
        // 2. Bản sao có thể thừa kế trạng thái ẩn của tab mẫu — tab tháng phải luôn hiện.
        try await SheetsHTTP.batchUpdate(spreadsheetId: spreadsheetId, requests: [SheetsRequests.setHidden(sheetId: newSheetId, hidden: false)], accessToken: accessToken)
    }

    /// Lấy `properties.sheetId` từ 1 object sheet/reply của Sheets API.
    private static func sheetId(in object: [String: Any]?) -> Int? {
        (object?["properties"] as? [String: Any])?["sheetId"] as? Int
    }
}
