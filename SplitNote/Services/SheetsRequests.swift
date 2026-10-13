//
//  SheetsRequests.swift
//  SplitNote
//

import Foundation

/// Dựng sẵn các request `batchUpdate` và vùng ghi tiêu đề dùng chung giữa các service Sheets.
enum SheetsRequests {
    typealias ValueRange = (range: String, values: [[String]])

    // MARK: - batchUpdate

    /// Thêm tab, cố định hàng tiêu đề; `index` nil thì Sheets tự chèn cuối.
    static func addSheet(title: String, index: Int? = nil) -> [String: Any] {
        var properties: [String: Any] = ["title": title, "gridProperties": ["frozenRowCount": 1]]
        properties["index"] = index
        return ["addSheet": ["properties": properties]]
    }

    static func duplicateSheet(sourceSheetId: Int, newTitle: String, insertIndex: Int) -> [String: Any] {
        ["duplicateSheet": ["sourceSheetId": sourceSheetId, "insertSheetIndex": insertIndex, "newSheetName": newTitle]]
    }

    static func setHidden(sheetId: Int, hidden: Bool) -> [String: Any] {
        ["updateSheetProperties": ["properties": ["sheetId": sheetId, "hidden": hidden], "fields": "hidden"]]
    }

    /// Ép cột B (Loại) chỉ nhận `categoryValues`.
    static func categoryValidation(sheetId: Int) -> [String: Any] {
        dropdown(sheetId: sheetId, column: 1, values: SheetsLayout.categoryValues, strict: true)
    }

    /// Chỉ gợi ý chứ không ép — Sheets không có dropdown chọn nhiều nên "Chi cho ai" vẫn là chữ tự do.
    static func memberValidation(sheetId: Int, members: [String]) -> [String: Any] {
        dropdown(sheetId: sheetId, column: 7, values: members, strict: false)
    }

    /// Dropdown cho 1 cột (đếm từ 0), áp từ hàng 2 trở xuống.
    private static func dropdown(sheetId: Int, column: Int, values: [String], strict: Bool) -> [String: Any] {
        [
            "setDataValidation": [
                "range": ["sheetId": sheetId, "startRowIndex": 1, "startColumnIndex": column, "endColumnIndex": column + 1],
                "rule": [
                    "condition": ["type": "ONE_OF_LIST", "values": values.map { ["userEnteredValue": $0] }],
                    "strict": strict,
                    "showCustomUi": true
                ]
            ]
        ]
    }

    // MARK: - Vùng ghi tiêu đề

    /// Tiêu đề A1:D1 + nhãn và công thức "Tổng cộng" ở `totalColumn`.
    static func headerAndTotal(tabTitle: String) -> [ValueRange] {
        let totalColumn = SheetsLayout.totalColumn
        return [
            (SheetsHTTP.bodyRange(tabTitle: tabTitle, cells: "A1:D1"), [SheetsLayout.headerColumns]),
            (SheetsHTTP.bodyRange(tabTitle: tabTitle, cells: "\(totalColumn)1:\(totalColumn)2"), [[SheetsLayout.totalLabel], [SheetsLayout.totalFormula]])
        ]
    }

    /// Tiêu đề H1:J1 (gia đình) + L1:O1 (bảng cân đối).
    static func familyHeaders(tabTitle: String) -> [ValueRange] {
        [
            (SheetsHTTP.bodyRange(tabTitle: tabTitle, cells: "H1:J1"), [SheetsLayout.familyHeaderColumns]),
            (SheetsHTTP.bodyRange(tabTitle: tabTitle, cells: "L1:O1"), [SheetsLayout.balanceHeaderColumns])
        ]
    }
}
