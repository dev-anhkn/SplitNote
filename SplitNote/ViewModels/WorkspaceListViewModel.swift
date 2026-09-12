//
//  WorkspaceListViewModel.swift
//  SplitNote
//

import Combine
import Foundation

@MainActor
final class WorkspaceListViewModel: ObservableObject {
    struct Workspace: Identifiable {
        let type: WorkspaceType
        let spreadsheetId: String
        var id: WorkspaceType { type }
    }

    /// Handed to `SheetSessionView` once a workspace's current-month tab is
    /// confirmed ready (created or already existing).
    struct ActiveSession: Identifiable, Hashable {
        let spreadsheetId: String
        let tabTitle: String
        let spreadsheetURL: URL?
        var id: String { spreadsheetId + tabTitle }
    }

    /// The Drive `appProperties` key tagging a workspace's spreadsheet — lets
    /// the app find it again via `DriveService` if the local cache
    /// (`WorkspaceStore`) is ever lost (reinstall, new device).
    private static let workspaceTypePropertyKey = "splitnote_workspace_type"

    @Published private(set) var workspaces: [Workspace] = []
    @Published var isShowingCreatePicker = false
    @Published private(set) var preparingType: WorkspaceType?
    @Published var errorMessage: String?
    @Published var activeSession: ActiveSession?
    /// True until the initial Drive reconcile finishes — the "+" button only
    /// appears after that, so it can never race a not-yet-discovered sheet
    /// into creating a duplicate.
    @Published private(set) var isLoadingWorkspaces = true

    private let sheetsService: SheetsServiceProtocol
    private let driveService: DriveServiceProtocol
    private let store: WorkspaceStore

    init(
        sheetsService: SheetsServiceProtocol = SheetsService(),
        driveService: DriveServiceProtocol = DriveService(),
        store: WorkspaceStore = WorkspaceStore()
    ) {
        self.sheetsService = sheetsService
        self.driveService = driveService
        self.store = store
        reloadWorkspaces()
    }

    var availableTypesToCreate: [WorkspaceType] {
        WorkspaceType.allCases.filter { $0.isAvailable && store.spreadsheetId(for: $0) == nil }
    }

    func reloadWorkspaces() {
        workspaces = WorkspaceType.allCases.compactMap { type in
            store.spreadsheetId(for: type).map { Workspace(type: type, spreadsheetId: $0) }
        }
    }

    /// For any available workspace type missing from the local cache, asks
    /// Drive whether a previously-created (and tagged) spreadsheet already
    /// exists for it — recovering from a lost cache instead of letting the
    /// user create a duplicate. Safe to call every time the list appears.
    func reconcileMissingWorkspaces() async {
        defer { isLoadingWorkspaces = false }

        let missingTypes = WorkspaceType.allCases.filter { $0.isAvailable && store.spreadsheetId(for: $0) == nil }
        guard !missingTypes.isEmpty else { return }

        for type in missingTypes {
            guard let foundId = try? await driveService.findFile(key: Self.workspaceTypePropertyKey, value: type.rawValue) else {
                continue
            }
            store.setSpreadsheetId(foundId, for: type)
        }
        reloadWorkspaces()
    }

    /// Opens an already-created workspace: makes sure this month's tab
    /// exists, then hands off to the session view.
    func openWorkspace(_ workspace: Workspace) async {
        preparingType = workspace.type
        errorMessage = nil
        defer { preparingType = nil }

        let tabTitle = Self.currentMonthTabTitle()
        do {
            try await sheetsService.ensureTab(spreadsheetId: workspace.spreadsheetId, tabTitle: tabTitle)
            activeSession = ActiveSession(
                spreadsheetId: workspace.spreadsheetId,
                tabTitle: tabTitle,
                spreadsheetURL: Self.editURL(spreadsheetId: workspace.spreadsheetId)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Creates the one spreadsheet for a not-yet-created workspace type, and
    /// tags it on Drive so it can be found again later even if the local
    /// cache is lost. Tagging failure doesn't block the flow — the sheet is
    /// already usable, only future auto-recovery would be affected.
    func createWorkspace(_ type: WorkspaceType) async {
        guard type.isAvailable, store.spreadsheetId(for: type) == nil else { return }
        preparingType = type
        errorMessage = nil
        defer { preparingType = nil }

        let tabTitle = Self.currentMonthTabTitle()
        do {
            let title = "SplitNote - \(type.displayName)"
            let created = try await sheetsService.createSpreadsheet(title: title, firstTabTitle: tabTitle)
            store.setSpreadsheetId(created.spreadsheetId, for: type)
            reloadWorkspaces()
            try? await driveService.tagFile(fileId: created.spreadsheetId, key: Self.workspaceTypePropertyKey, value: type.rawValue)
            activeSession = ActiveSession(spreadsheetId: created.spreadsheetId, tabTitle: tabTitle, spreadsheetURL: created.url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func editURL(spreadsheetId: String) -> URL? {
        URL(string: "https://docs.google.com/spreadsheets/d/\(spreadsheetId)/edit")
    }

    /// "-" instead of "/" so this can drop straight into an A1 range
    /// (`'Tháng 09-2026'!A1:D1`) without URL-encoding a path separator.
    static func currentMonthTabTitle(date: Date = Date()) -> String {
        let components = Calendar.current.dateComponents([.month, .year], from: date)
        let month = components.month ?? 1
        let year = components.year ?? 0
        return String(format: "Tháng %02d-%d", month, year)
    }
}
