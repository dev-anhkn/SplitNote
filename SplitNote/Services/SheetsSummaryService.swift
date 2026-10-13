//
//  SheetsSummaryService.swift
//  SplitNote
//

import Foundation

/// Đọc/ghi tab "Tổng hợp" — nơi tổng mỗi tháng và tổng theo loại nằm dưới dạng công thức.
struct SheetsSummaryService {
    nonisolated init() {}

    /// Đọc cột A (tên tab) + B (tổng tháng); ném `.notFound` nếu spreadsheet cũ chưa có tab "Tổng hợp".
    func fetchMonthlyTotals(spreadsheetId: String) async throws -> [(tabTitle: String, total: Decimal)] {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        let rows = try await SheetsHTTP.readValues(spreadsheetId: spreadsheetId, tabTitle: SheetsLayout.summaryTabTitle, range: "A2:B\(SheetsLayout.maxSummaryRow)", accessToken: accessToken)
        return rows.compactMap { row in
            guard let tabTitle = row.first, !tabTitle.isEmpty else { return nil }
            return (tabTitle: tabTitle, total: SheetsHTTP.parseAmount(SheetsHTTP.cell(row, 1)) ?? 0)
        }
    }

    /// Ghép từng cột loại chi của hàng `tabTitle` với kết quả `SUMIF`, chỉ giữ loại có tổng > 0.
    func fetchCategoryTotals(spreadsheetId: String, tabTitle: String) async throws -> [(category: String, total: Decimal)] {
        let accessToken = try await GoogleAPIAuth.currentAccessToken()
        let rows = try await SheetsHTTP.readValues(spreadsheetId: spreadsheetId, tabTitle: SheetsLayout.summaryTabTitle, range: "A2:\(SheetsLayout.lastSummaryColumn)\(SheetsLayout.maxSummaryRow)", accessToken: accessToken)
        guard let row = rows.first(where: { $0.first == tabTitle }) else { return [] }
        // Cột 0 = Tháng, cột 1 = Tổng cộng, từ cột 2 là từng loại chi.
        return SheetsLayout.categoryValues.enumerated().compactMap { offset, category in
            guard let total = SheetsHTTP.parseAmount(SheetsHTTP.cell(row, offset + 2)), total > 0 else { return nil }
            return (category: category, total: total)
        }
        .sorted { $0.total > $1.total }
    }

    /// Thêm tab "Tổng hợp" ghim đầu cho spreadsheet cũ chưa có.
    func createSummaryTab(spreadsheetId: String, accessToken: String) async throws {
        // 1. Tạo tab ở vị trí đầu tiên, cố định hàng tiêu đề.
        let addSheet = SheetsRequests.addSheet(title: SheetsLayout.summaryTabTitle, index: 0)
        try await SheetsHTTP.batchUpdate(spreadsheetId: spreadsheetId, requests: [addSheet], accessToken: accessToken)
        // 2. Ghi hàng tiêu đề.
        try await SheetsHTTP.writeValues(spreadsheetId: spreadsheetId, tabTitle: SheetsLayout.summaryTabTitle, range: "A1:\(SheetsLayout.lastSummaryColumn)1", values: [SheetsLayout.summaryHeaderColumns], accessToken: accessToken)
    }

    /// Thêm hàng công thức cho `tabTitle` nếu chưa có — công thức tự đúng khi khoản chi thay đổi.
    func ensureSummaryRow(spreadsheetId: String, tabTitle: String, accessToken: String) async throws {
        // 1. Đọc danh sách tháng đã có; có rồi thì thôi.
        let titles = try await SheetsHTTP.readValues(spreadsheetId: spreadsheetId, tabTitle: SheetsLayout.summaryTabTitle, range: "A2:A\(SheetsLayout.maxSummaryRow)", accessToken: accessToken)
        guard !titles.contains(where: { $0.first == tabTitle }) else { return }
        // 2. Hàng ngay sau hàng cuối còn dữ liệu.
        let lastUsedRow = titles.lastIndex { !($0.first ?? "").isEmpty }.map { $0 + 2 } ?? 1
        let row = lastUsedRow + 1
        // 3. Ghi hàng công thức.
        try await SheetsHTTP.writeValues(spreadsheetId: spreadsheetId, tabTitle: SheetsLayout.summaryTabTitle, range: "A\(row):\(SheetsLayout.lastSummaryColumn)\(row)", values: [Self.summaryRowValues(tabTitle: tabTitle)], accessToken: accessToken)
    }

    /// [tên tab, tổng tháng, SUMIF từng loại chi] — đều trỏ thẳng vào tab tháng đó.
    private static func summaryRowValues(tabTitle: String) -> [String] {
        let lastRow = SheetsLayout.maxDataRow
        let categoryFormulas = SheetsLayout.categoryValues.map { category in
            "=SUMIF('\(tabTitle)'!B2:B\(lastRow),\"\(category)\",'\(tabTitle)'!D2:D\(lastRow))"
        }
        return [tabTitle, "='\(tabTitle)'!\(SheetsLayout.totalColumn)2"] + categoryFormulas
    }
}
