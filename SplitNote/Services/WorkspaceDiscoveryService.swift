//
//  WorkspaceDiscoveryService.swift
//  SplitNote
//

import Foundation

/// Reconciles `WorkspaceStore`'s local cache of spreadsheet IDs against what
/// actually exists on Google Drive — drops entries for files deleted
/// elsewhere, and recovers any tagged spreadsheet a fresh install or another
/// device created that the local cache doesn't know about yet.
struct WorkspaceDiscoveryService {
    /// The Drive `appProperties` key tagging a workspace's spreadsheet.
    static let workspaceTypePropertyKey = "splitnote_workspace_type"

    private let driveService: DriveServiceProtocol
    private let store: WorkspaceStore

    init(driveService: DriveServiceProtocol, store: WorkspaceStore) {
        self.driveService = driveService
        self.store = store
    }

    /// Drops any cached slot whose spreadsheet no longer exists on Drive.
    func pruneDeletedWorkspaces() async {
        let cachedSlots = WorkspaceType.allCases.flatMap { type in
            (0..<WorkspaceStore.maxInstancesPerType).compactMap { index -> (WorkspaceType, Int, String)? in
                store.spreadsheetId(for: type, at: index).map { (type, index, $0) }
            }
        }
        guard !cachedSlots.isEmpty else { return }

        // Kiểm tra Drive song song thay vì tuần tự từng slot.
        await withTaskGroup(of: (WorkspaceType, Int, Bool).self) { group in
            for (type, index, id) in cachedSlots {
                group.addTask { [driveService] in
                    let stillExists = (try? await driveService.fileExists(fileId: id)) ?? true
                    return (type, index, stillExists)
                }
            }
            for await (type, index, stillExists) in group where !stillExists {
                store.clearSpreadsheetId(for: type, at: index)
            }
        }
    }

    /// Fills any empty slot whose spreadsheet is found tagged on Drive.
    /// Returns an error message if a Drive lookup failed — surfaced, not
    /// swallowed, so a permission/auth error doesn't look identical to
    /// "nothing found".
    func discoverMissingWorkspaces() async -> String? {
        let missingSlots = WorkspaceType.allCases
            .filter(\.isAvailable)
            .flatMap { type in
                (0..<WorkspaceStore.maxInstancesPerType)
                    .filter { store.spreadsheetId(for: type, at: $0) == nil }
                    .map { (type, $0) }
            }
        guard !missingSlots.isEmpty else { return nil }

        var errorMessage: String?
        // Hỏi Drive song song cho mọi slot còn trống, thay vì tuần tự — mỗi
        // slot là 1 request độc lập nên không cần chờ nhau.
        await withTaskGroup(of: (WorkspaceType, Int, Result<String?, Error>).self) { group in
            for (type, index) in missingSlots {
                group.addTask { [driveService] in
                    do {
                        return (type, index, .success(try await Self.findTaggedFile(driveService: driveService, type: type, index: index)))
                    } catch {
                        return (type, index, .failure(error))
                    }
                }
            }
            for await (type, index, result) in group {
                switch result {
                case .success(let foundId):
                    if let foundId {
                        store.setSpreadsheetId(foundId, for: type, at: index)
                    }
                case .failure(let error):
                    errorMessage = "Không thể tìm sheet trên Google Drive: \(error.localizedDescription)"
                }
            }
        }
        return errorMessage
    }

    static func tagValue(type: WorkspaceType, index: Int) -> String {
        "\(type.rawValue)_\(index)"
    }

    /// Slot 0 may still carry the pre-multi-slot Drive tag (no "_index"
    /// suffix) from before this feature — fall back to it so old workspaces
    /// tagged that way are still found on a fresh device.
    private static func findTaggedFile(driveService: DriveServiceProtocol, type: WorkspaceType, index: Int) async throws -> String? {
        if let id = try await driveService.findFile(key: workspaceTypePropertyKey, value: tagValue(type: type, index: index)) {
            return id
        }
        guard index == 0 else { return nil }
        return try await driveService.findFile(key: workspaceTypePropertyKey, value: type.rawValue)
    }
}
