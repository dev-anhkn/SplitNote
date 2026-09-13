//
//  WorkspaceStore.swift
//  SplitNote
//

import Foundation

/// Persists the spreadsheet IDs created for each workspace type, up to
/// `maxInstancesPerType` slots each (e.g. "Cá nhân 1", "Cá nhân 2", ...), so
/// re-launching the app reuses the same Google Sheets instead of creating
/// new ones every time.
nonisolated struct WorkspaceStore {
    static let maxInstancesPerType = 3
    
    private let defaults: UserDefaults
    
    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    func spreadsheetId(for type: WorkspaceType, at index: Int) -> String? {
        if let value = defaults.string(forKey: key(for: type, index: index)) {
            return value
        }
        // Trước khi hỗ trợ nhiều slot/type, key không có index — chỉ slot 0
        // có thể còn dữ liệu ở key cũ. Di chuyển sang key mới rồi trả về.
        guard index == 0, let legacyValue = defaults.string(forKey: legacyKey(for: type)) else {
            return nil
        }
        setSpreadsheetId(legacyValue, for: type, at: index)
        defaults.removeObject(forKey: legacyKey(for: type))
        return legacyValue
    }
    
    func setSpreadsheetId(_ id: String, for type: WorkspaceType, at index: Int) {
        defaults.set(id, forKey: key(for: type, index: index))
    }
    
    func clearSpreadsheetId(for type: WorkspaceType, at index: Int) {
        defaults.removeObject(forKey: key(for: type, index: index))
    }
    
    /// The first empty slot for `type`, or nil once all
    /// `maxInstancesPerType` slots are filled.
    func nextAvailableIndex(for type: WorkspaceType) -> Int? {
        for index in 0..<Self.maxInstancesPerType where spreadsheetId(for: type, at: index) == nil {
            return index
        }
        return nil
    }
    
    private func key(for type: WorkspaceType, index: Int) -> String {
        "SplitNote.spreadsheetId.\(type.rawValue).\(index)"
    }

    private func legacyKey(for type: WorkspaceType) -> String {
        "SplitNote.spreadsheetId.\(type.rawValue)"
    }
}
