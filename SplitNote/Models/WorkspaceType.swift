//
//  WorkspaceType.swift
//  SplitNote
//

import Foundation

/// 2 loại sổ chi tiêu; mỗi workspace là 1 spreadsheet, mỗi tháng 1 tab.
enum WorkspaceType: String, CaseIterable {
    case personal
    case family

    var displayName: String {
        switch self {
        case .personal: return "Cá nhân"
        case .family: return "Gia đình"
        }
    }

    /// Gia đình tạm tắt — tập trung hoàn thiện Cá nhân trước.
    var isAvailable: Bool {
        self == .personal
    }
}
