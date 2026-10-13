//
//  StorageKeys.swift
//  SplitNote
//

import Foundation

/// Key lưu trữ cục bộ (UserDefaults) và key gắn thẻ file trên Drive.
nonisolated enum StorageKeys {
    /// Key `appProperties` trên Drive để tag spreadsheet của workspace.
    static let driveWorkspaceTag = "splitnote_workspace_type"

    /// Id spreadsheet của 1 slot workspace.
    static func spreadsheetId(type: WorkspaceType, index: Int) -> String {
        "SplitNote.spreadsheetId.\(type.rawValue).\(index)"
    }

    /// Tên workspace của 1 slot — cache tên file trên Drive để hiện ngay khi mở app.
    static func workspaceName(type: WorkspaceType, index: Int) -> String {
        "SplitNote.workspaceName.\(type.rawValue).\(index)"
    }

    /// Key bản cũ (chưa có slot) — chỉ còn dùng để migrate sang key mới.
    static func legacySpreadsheetId(type: WorkspaceType) -> String {
        "SplitNote.spreadsheetId.\(type.rawValue)"
    }
}
