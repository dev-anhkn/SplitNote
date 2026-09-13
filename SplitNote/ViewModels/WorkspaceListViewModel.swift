//
//  WorkspaceListViewModel.swift
//  SplitNote
//

import Combine
import Foundation

@MainActor
final class WorkspaceListViewModel: ObservableObject {
    struct Workspace: Identifiable, Hashable {
        let type: WorkspaceType
        /// 0-based slot within `type` (up to `WorkspaceStore.maxInstancesPerType`).
        let index: Int
        let spreadsheetId: String
        var id: String { "\(type.rawValue)-\(index)" }
        var displayName: String { "\(type.displayName) \(index + 1)" }
        
        // Bằng `id` là đủ để so sánh/hash — không cần `WorkspaceType` phải
        // Hashable, tránh phải sửa thêm file Model chỉ vì màn sidebar cần
        // `selection:` là Hashable.
        static func == (lhs: Workspace, rhs: Workspace) -> Bool {
            lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
    
    /// Handed to `ExpenseListView` once a workspace's current-month tab is
    /// confirmed ready (created or already existing).
    struct ActiveSession: Identifiable, Hashable {
        let spreadsheetId: String
        let tabTitle: String
        let spreadsheetURL: URL?
        let workspaceType: WorkspaceType
        var id: String { spreadsheetId + tabTitle }

        static func == (lhs: ActiveSession, rhs: ActiveSession) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
    
    @Published private(set) var workspaces: [Workspace] = []
    @Published var isShowingCreatePicker = false
    @Published private(set) var openingWorkspaceId: String?
    @Published private(set) var isCreating = false
    @Published private(set) var deletingWorkspaceId: String?
    @Published var errorMessage: String?
    @Published private(set) var activeSession: ActiveSession?
    /// Single source of truth for sidebar selection — bound directly to
    /// `List(selection:)`. Setting it opens that workspace; setting it to nil
    /// clears `activeSession`. Kept in the view model (not view @State) so
    /// programmatic selection (e.g. right after `createWorkspace`) can't
    /// desync from what the sidebar highlights.
    @Published var selectedWorkspace: Workspace? {
        didSet {
            guard selectedWorkspace != oldValue, !isApplyingProgrammaticSelection else { return }
            Task { await applySelection(selectedWorkspace) }
        }
    }
    private var isApplyingProgrammaticSelection = false
    /// True until the initial Drive reconcile finishes — the "+" button only
    /// appears after that, so it can never race a not-yet-discovered sheet
    /// into creating a duplicate.
    @Published private(set) var isLoadingWorkspaces = true
    /// Manual refresh (separate from `isLoadingWorkspaces`, which is only
    /// for the very first load) — re-checks that cached sheets still exist
    /// and looks for anything newly available.
    @Published private(set) var isRefreshing = false
    
    private let sheetsService: SheetsServiceProtocol
    private let driveService: DriveServiceProtocol
    private let store: WorkspaceStore
    private let discoveryService: WorkspaceDiscoveryService
    /// Seeds the member list of a `.family` workspace with its creator's name
    /// (there's no cross-account invite yet — see `WorkspaceStore.members`).
    private let userDisplayName: String

    init(
        userDisplayName: String,
        sheetsService: SheetsServiceProtocol = SheetsService(),
        driveService: DriveServiceProtocol = DriveService(),
        store: WorkspaceStore = WorkspaceStore()
    ) {
        self.userDisplayName = userDisplayName
        self.sheetsService = sheetsService
        self.driveService = driveService
        self.store = store
        self.discoveryService = WorkspaceDiscoveryService(driveService: driveService, store: store)
        reloadWorkspaces()
    }
    
    var isBusy: Bool {
        isCreating || isRefreshing || openingWorkspaceId != nil || deletingWorkspaceId != nil
    }
    
    var availableTypesToCreate: [WorkspaceType] {
        WorkspaceType.allCases.filter { $0.isAvailable && store.nextAvailableIndex(for: $0) != nil }
    }
    
    func reloadWorkspaces() {
        var result: [Workspace] = []
        for type in WorkspaceType.allCases {
            for index in 0..<WorkspaceStore.maxInstancesPerType {
                if let id = store.spreadsheetId(for: type, at: index) {
                    result.append(Workspace(type: type, index: index, spreadsheetId: id))
                }
            }
        }
        workspaces = result
    }
    
    /// Runs once on first appearance: drops workspaces deleted on Drive, then
    /// recovers any tagged spreadsheet from another device the cache missed.
    func reconcileMissingWorkspaces() async {
        defer { isLoadingWorkspaces = false }
        await runDiscoveryReconcile()
    }

    /// Manual refresh — same as `reconcileMissingWorkspaces`, for a pull/tap.
    func refreshWorkspaces() async {
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        await runDiscoveryReconcile()
    }

    private func runDiscoveryReconcile() async {
        // 1. Bỏ workspace đã bị xoá trên Drive.
        await discoveryService.pruneDeletedWorkspaces()
        // 2. Tìm bù workspace được tag trên Drive mà cache local chưa biết.
        if let discoveryError = await discoveryService.discoverMissingWorkspaces() {
            errorMessage = discoveryError
        }
        reloadWorkspaces()
    }

    /// Reacts to `selectedWorkspace` changing: opens the newly selected
    /// workspace, or clears the active session when selection is cleared.
    private func applySelection(_ workspace: Workspace?) async {
        guard let workspace else {
            activeSession = nil
            return
        }
        await openWorkspace(workspace)
        if activeSession == nil {
            selectedWorkspace = nil
        }
    }

    /// Sets `selectedWorkspace` to reflect a session already opened elsewhere
    /// (e.g. right after `createWorkspace`) without re-running `openWorkspace`.
    private func setSelection(to workspace: Workspace?) {
        isApplyingProgrammaticSelection = true
        selectedWorkspace = workspace
        isApplyingProgrammaticSelection = false
    }

    /// Opens an already-created workspace: makes sure this month's tab
    /// exists, then hands off to its expense list.
    private func openWorkspace(_ workspace: Workspace) async {
        openingWorkspaceId = workspace.id
        errorMessage = nil
        // Xoá session cũ ngay: nếu mở thất bại, detail pane không được phép
        // giữ dữ liệu của workspace trước trong khi sidebar đã chọn mục mới.
        activeSession = nil
        defer { openingWorkspaceId = nil }

        await open(workspace, tabTitle: Self.currentMonthTabTitle(), allowSelfHeal: true)
    }

    /// Ensures `tabTitle` exists on `workspace` and opens it. Cache có thể
    /// đang giữ 1 id cũ (sheet đã bị xoá/tạo lại ngoài app) — `allowSelfHeal`
    /// cho phép tự tìm lại đúng 1 lần qua Drive trước khi báo đã xoá.
    private func open(_ workspace: Workspace, tabTitle: String, allowSelfHeal: Bool) async {
        do {
            try await sheetsService.ensureTab(spreadsheetId: workspace.spreadsheetId, tabTitle: tabTitle)
            activeSession = ActiveSession(
                spreadsheetId: workspace.spreadsheetId,
                tabTitle: tabTitle,
                spreadsheetURL: Self.editURL(spreadsheetId: workspace.spreadsheetId),
                workspaceType: workspace.type
            )
        } catch SheetsServiceError.notFound where allowSelfHeal {
            await selfHealAndRetry(workspace, tabTitle: tabTitle)
        } catch SheetsServiceError.notFound {
            markWorkspaceMissing(workspace)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Id cached không mở được — tìm lại đúng slot này qua tag Drive (thay vì
    /// bắt người dùng đăng xuất/đăng nhập lại để trigger reconcile) rồi mở
    /// tiếp; chỉ báo "đã xoá" nếu tìm lại cũng không ra.
    private func selfHealAndRetry(_ workspace: Workspace, tabTitle: String) async {
        store.clearSpreadsheetId(for: workspace.type, at: workspace.index)
        guard let rediscoveredId = try? await discoveryService.rediscoverWorkspace(type: workspace.type, index: workspace.index) else {
            markWorkspaceMissing(workspace)
            return
        }
        store.setSpreadsheetId(rediscoveredId, for: workspace.type, at: workspace.index)
        reloadWorkspaces()
        let healedWorkspace = Workspace(type: workspace.type, index: workspace.index, spreadsheetId: rediscoveredId)
        await open(healedWorkspace, tabTitle: tabTitle, allowSelfHeal: false)
    }

    private func markWorkspaceMissing(_ workspace: Workspace) {
        store.clearSpreadsheetId(for: workspace.type, at: workspace.index)
        reloadWorkspaces()
        errorMessage = "\(workspace.displayName) đã bị xoá trên Drive, đã gỡ khỏi danh sách."
    }
    
    /// Creates the next spreadsheet slot for `type` and tags it on Drive so
    /// other devices can find it later. A tagging failure doesn't block the
    /// flow — the sheet is already usable here — but is surfaced as a warning.
    func createWorkspace(_ type: WorkspaceType) async {
        guard type.isAvailable, let index = store.nextAvailableIndex(for: type) else {
            print("[SplitNote][createWorkspace] bỏ qua — type=\(type) isAvailable=\(type.isAvailable) index=\(String(describing: store.nextAvailableIndex(for: type)))")
            return
        }
        print("[SplitNote][createWorkspace] bấm + tạo — type=\(type) index=\(index)")
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        let tabTitle = Self.currentMonthTabTitle()
        let displayName = "\(type.displayName) \(index + 1)"
        // Gia đình bắt đầu với đúng người tạo — thêm người khác qua màn quản
        // lý thành viên sau (chưa có invite qua tài khoản Google thật).
        let members = type == .family ? [userDisplayName] : []
        do {
            let created = try await sheetsService.createSpreadsheet(title: "SplitNote - \(displayName)", firstTabTitle: tabTitle, members: members)
            print("[SplitNote][createWorkspace] createSpreadsheet thành công — id=\(created.spreadsheetId)")
            // Lưu local ngay để dùng được dù bước gắn thẻ bên dưới có lỗi.
            store.setSpreadsheetId(created.spreadsheetId, for: type, at: index)
            reloadWorkspaces()
            do {
                try await driveService.tagFile(fileId: created.spreadsheetId, key: WorkspaceDiscoveryService.workspaceTypePropertyKey, value: WorkspaceDiscoveryService.tagValue(type: type, index: index))
            } catch {
                print("[SplitNote][createWorkspace] tagFile lỗi: \(error)")
                errorMessage = "\(displayName) đã tạo, nhưng gắn thẻ Drive thất bại nên có thể sẽ không tự tìm thấy được trên thiết bị khác: \(error.localizedDescription)"
            }
            activeSession = ActiveSession(spreadsheetId: created.spreadsheetId, tabTitle: tabTitle, spreadsheetURL: created.url, workspaceType: type)
            // Đồng bộ sidebar với session vừa mở, không chạy lại openWorkspace.
            setSelection(to: Workspace(type: type, index: index, spreadsheetId: created.spreadsheetId))
        } catch {
            print("[SplitNote][createWorkspace] LỖI: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    /// Trashes the spreadsheet on Drive, then drops it locally (propagates to
    /// other devices on their next prune, since a trashed file reads as deleted).
    func deleteWorkspace(_ workspace: Workspace) async {
        deletingWorkspaceId = workspace.id
        errorMessage = nil
        defer { deletingWorkspaceId = nil }

        do {
            try await driveService.trashFile(fileId: workspace.spreadsheetId)
            store.clearSpreadsheetId(for: workspace.type, at: workspace.index)
            reloadWorkspaces()
            // Selection nil chỉ xoá activeSession, không gọi lại network — đi
            // qua đường bình thường (không suppress) để activeSession được dọn.
            if selectedWorkspace == workspace {
                selectedWorkspace = nil
            }
        } catch {
            errorMessage = "Không thể xoá \(workspace.displayName): \(error.localizedDescription)"
        }
    }
    
    private static func editURL(spreadsheetId: String) -> URL? {
        URL(string: "https://docs.google.com/spreadsheets/d/\(spreadsheetId)/edit")
    }
    
    static func currentMonthTabTitle(date: Date = AppClock.now) -> String {
        MonthTabTitle.title(for: date)
    }
}
