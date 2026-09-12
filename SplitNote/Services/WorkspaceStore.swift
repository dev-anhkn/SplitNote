//
//  WorkspaceStore.swift
//  SplitNote
//

import Foundation

/// Persists the one spreadsheet ID created for each workspace type, so
/// re-launching the app reuses the same Google Sheet instead of creating a
/// new one every time.
nonisolated struct WorkspaceStore {
    private let defaults: UserDefaults

    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func spreadsheetId(for type: WorkspaceType) -> String? {
        defaults.string(forKey: spreadsheetIdKey(for: type))
    }

    func setSpreadsheetId(_ id: String, for type: WorkspaceType) {
        defaults.set(id, forKey: spreadsheetIdKey(for: type))
    }

    private func spreadsheetIdKey(for type: WorkspaceType) -> String {
        "SplitNote.spreadsheetId.\(type.rawValue)"
    }
}
