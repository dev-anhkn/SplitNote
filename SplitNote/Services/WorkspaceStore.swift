//
//  WorkspaceStore.swift
//  SplitNote
//

import Foundation

/// Lưu id spreadsheet của từng slot workspace để mở lại app không tạo sheet mới.
nonisolated struct WorkspaceStore {
    /// Số workspace tối đa mỗi loại (vd "Cá nhân 1" tới "Cá nhân 3").
    static let maxInstancesPerType = 3

    private let defaults: UserDefaults

    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func spreadsheetId(for type: WorkspaceType, at index: Int) -> String? {
        if let value = defaults.string(forKey: StorageKeys.spreadsheetId(type: type, index: index)) {
            return value
        }
        // Bản cũ lưu key không có index — chỉ slot 0 có thể còn, chuyển sang key mới.
        guard index == 0, let legacyValue = defaults.string(forKey: StorageKeys.legacySpreadsheetId(type: type)) else {
            return nil
        }
        setSpreadsheetId(legacyValue, for: type, at: index)
        defaults.removeObject(forKey: StorageKeys.legacySpreadsheetId(type: type))
        return legacyValue
    }

    func setSpreadsheetId(_ id: String, for type: WorkspaceType, at index: Int) {
        defaults.set(id, forKey: StorageKeys.spreadsheetId(type: type, index: index))
    }

    func clearSpreadsheetId(for type: WorkspaceType, at index: Int) {
        defaults.removeObject(forKey: StorageKeys.spreadsheetId(type: type, index: index))
        defaults.removeObject(forKey: StorageKeys.workspaceName(type: type, index: index))
    }

    func name(for type: WorkspaceType, at index: Int) -> String? {
        defaults.string(forKey: StorageKeys.workspaceName(type: type, index: index))
    }

    func setName(_ name: String, for type: WorkspaceType, at index: Int) {
        defaults.set(name, forKey: StorageKeys.workspaceName(type: type, index: index))
    }

    /// Slot trống đầu tiên của `type`, nil khi đã đầy.
    func nextAvailableIndex(for type: WorkspaceType) -> Int? {
        (0..<Self.maxInstancesPerType).first { spreadsheetId(for: type, at: $0) == nil }
    }
}
