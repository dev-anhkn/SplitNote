//
//  WorkspaceType.swift
//  SplitNote
//

import Foundation

/// The two kinds of expense sheet a user can keep. Each maps to exactly one
/// spreadsheet file (see `WorkspaceStore`), with a new tab added per month.
enum WorkspaceType: String, CaseIterable {
    case personal
    case family

    var displayName: String {
        switch self {
        case .personal: return "Cá nhân"
        case .family: return "Gia đình"
        }
    }

    /// Only `.personal` is wired up end-to-end for now.
    var isAvailable: Bool {
        switch self {
        case .personal: return true
        case .family: return false
        }
    }
}
