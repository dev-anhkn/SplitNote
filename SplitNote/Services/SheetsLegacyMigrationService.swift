//
//  SheetsLegacyMigrationService.swift
//  SplitNote
//

import Foundation

/// Sửa các tab tạo từ bản cũ cho khớp bố cục hiện tại trong `SheetsLayout`.
struct SheetsLegacyMigrationService {
    nonisolated init() {}

    /// Bản cũ đặt "Tổng cộng" ở G và tiêu đề gia đình ở I1:K1/M1:P1 — dời về F, H1:J1, L1:O1 cho mọi tab (≤ 3 request).
    func migrateShiftedColumnsIfNeeded(spreadsheetId: String, tabTitles: [String], accessToken: String) async throws {
        guard !tabTitles.isEmpty else { return }
        // 1. Đọc G1:I1 của mọi tab trong 1 request để nhận diện tab lệch.
        let probeRanges = tabTitles.map { SheetsHTTP.bodyRange(tabTitle: $0, cells: SheetsLayout.legacyProbeCells) }
        let probes = try await SheetsHTTP.batchReadValues(spreadsheetId: spreadsheetId, ranges: probeRanges, accessToken: accessToken)
        let shiftedTabs = zip(tabTitles, probes).compactMap { title, values in Self.shiftedLayout(tabTitle: title, probe: values.first ?? []) }
        guard !shiftedTabs.isEmpty else { return }
        // 2. Xoá các ô cũ.
        let staleRanges = shiftedTabs.flatMap(\.staleRanges)
        try await SheetsHTTP.batchClearValues(spreadsheetId: spreadsheetId, ranges: staleRanges, accessToken: accessToken)
        // 3. Ghi lại tiêu đề/tổng đúng chỗ — công thức "Tổng hợp" vốn trỏ vào F2 nên tự đúng lại.
        let rewrites = shiftedTabs.flatMap(\.rewrites)
        try await SheetsHTTP.batchWriteValues(spreadsheetId: spreadsheetId, ranges: rewrites, accessToken: accessToken)
    }

    /// Tab cũ có B = Nội dung, C = Loại (ngược hiện tại) — hoán đổi để không lẫn 2 schema; trả về true nếu đã đổi.
    func migrateSwappedColumnsIfNeeded(spreadsheetId: String, tabTitle: String, accessToken: String) async throws -> Bool {
        // 1. Nhận diện qua tiêu đề cột B.
        let header = try await SheetsHTTP.readValues(spreadsheetId: spreadsheetId, tabTitle: tabTitle, range: "B1:B1", accessToken: accessToken)
        guard header.first?.first == SheetsLayout.legacySwappedHeaderB else { return false }
        // 2. Hoán đổi B/C của mọi hàng dữ liệu (nếu có).
        let range = "B2:C\(SheetsLayout.maxDataRow)"
        let rows = try await SheetsHTTP.readValues(spreadsheetId: spreadsheetId, tabTitle: tabTitle, range: range, accessToken: accessToken)
        if !rows.isEmpty {
            let swapped = rows.map { [SheetsHTTP.cell($0, 1), SheetsHTTP.cell($0, 0)] }
            try await SheetsHTTP.writeValues(spreadsheetId: spreadsheetId, tabTitle: tabTitle, range: range, values: swapped, accessToken: accessToken)
        }
        // 3. Ghi tiêu đề theo thứ tự cột mới.
        try await SheetsHTTP.batchWriteValues(spreadsheetId: spreadsheetId, ranges: SheetsRequests.headerAndTotal(tabTitle: tabTitle), accessToken: accessToken)
        return true
    }

    /// Ô cần xoá + vùng cần ghi lại của 1 tab lệch; nil nếu tab đã đúng bố cục.
    private static func shiftedLayout(tabTitle: String, probe: [String]) -> (staleRanges: [String], rewrites: [SheetsRequests.ValueRange])? {
        let hasShiftedTotal = SheetsHTTP.cell(probe, 0) == SheetsLayout.totalLabel
        let hasShiftedFamily = SheetsHTTP.cell(probe, 2) == SheetsLayout.familyHeaderColumns[0]
        guard hasShiftedTotal || hasShiftedFamily else { return nil }

        var staleCells: [String] = []
        var rewrites: [SheetsRequests.ValueRange] = []
        if hasShiftedTotal {
            staleCells.append(SheetsLayout.legacyTotalCells)
            rewrites += SheetsRequests.headerAndTotal(tabTitle: tabTitle)
        }
        if hasShiftedFamily {
            staleCells += SheetsLayout.legacyFamilyHeaderCells
            rewrites += SheetsRequests.familyHeaders(tabTitle: tabTitle)
        }
        let staleRanges = staleCells.map { SheetsHTTP.bodyRange(tabTitle: tabTitle, cells: $0) }
        return (staleRanges, rewrites)
    }
}
