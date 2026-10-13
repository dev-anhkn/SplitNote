//
//  WorkspaceDiscoveryService.swift
//  SplitNote
//

import Foundation

/// Đối chiếu cache id spreadsheet với Drive: bỏ file đã xoá, tìm bù file được tag từ thiết bị khác.
struct WorkspaceDiscoveryService {
    private let driveService: DriveServiceProtocol
    private let store: WorkspaceStore

    init(driveService: DriveServiceProtocol, store: WorkspaceStore) {
        self.driveService = driveService
        self.store = store
    }

    /// Bỏ các slot cache mà spreadsheet không còn trên Drive.
    func pruneDeletedWorkspaces() async {
        // 1. Gom các slot đang có id.
        let cachedSlots = WorkspaceType.allCases.flatMap { type in
            (0..<WorkspaceStore.maxInstancesPerType).compactMap { index -> (WorkspaceType, Int, String)? in
                store.spreadsheetId(for: type, at: index).map { (type, index, $0) }
            }
        }
        guard !cachedSlots.isEmpty else { return }

        // 2. Hỏi Drive song song; lỗi mạng thì coi như vẫn còn để không xoá nhầm.
        await withTaskGroup(of: (WorkspaceType, Int, Bool).self) { group in
            for (type, index, id) in cachedSlots {
                group.addTask { [driveService] in
                    let stillExists = (try? await driveService.fileExists(fileId: id)) ?? true
                    return (type, index, stillExists)
                }
            }
            // 3. Xoá cache các slot không còn.
            for await (type, index, stillExists) in group where !stillExists {
                store.clearSpreadsheetId(for: type, at: index)
            }
        }
    }

    /// Điền slot trống bằng spreadsheet tìm thấy trên Drive; trả về lỗi để không lẫn với "không tìm thấy".
    func discoverMissingWorkspaces() async -> String? {
        // 1. Gom các slot còn trống.
        let missingSlots = WorkspaceType.allCases
            .filter(\.isAvailable)
            .flatMap { type in
                (0..<WorkspaceStore.maxInstancesPerType)
                    .filter { store.spreadsheetId(for: type, at: $0) == nil }
                    .map { (type, $0) }
            }
        guard !missingSlots.isEmpty else { return nil }

        var errorMessage: String?
        // 2. Hỏi Drive song song cho từng slot — mỗi slot là 1 request độc lập.
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
            // 3. Lưu id tìm được, ghi nhận lỗi nếu có.
            for await (type, index, result) in group {
                switch result {
                case .success(let foundId?):
                    store.setSpreadsheetId(foundId, for: type, at: index)
                case .success(nil):
                    break
                case .failure(let error):
                    errorMessage = "Không thể tìm sheet trên Google Drive: \(error.localizedDescription)"
                }
            }
        }
        return errorMessage
    }

    /// Tìm lại spreadsheet của 1 slot khi id cache mở lỗi — tự sửa thay vì bắt đăng xuất.
    func rediscoverWorkspace(type: WorkspaceType, index: Int) async throws -> String? {
        try await Self.findTaggedFile(driveService: driveService, type: type, index: index)
    }

    static func tagValue(type: WorkspaceType, index: Int) -> String {
        "\(type.rawValue)_\(index)"
    }

    /// Slot 0 có thể còn tag kiểu cũ (không có "_index") — thử thêm tag đó để vẫn tìm thấy.
    private static func findTaggedFile(driveService: DriveServiceProtocol, type: WorkspaceType, index: Int) async throws -> String? {
        if let id = try await driveService.findFile(key: StorageKeys.driveWorkspaceTag, value: tagValue(type: type, index: index)) {
            return id
        }
        guard index == 0 else { return nil }
        return try await driveService.findFile(key: StorageKeys.driveWorkspaceTag, value: type.rawValue)
    }
}
