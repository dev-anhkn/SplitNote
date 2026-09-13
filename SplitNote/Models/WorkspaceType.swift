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

    var isAvailable: Bool {
        true
    }
}
