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
        /// Slot trong `type`, đếm từ 0.
        let index: Int
        let spreadsheetId: String
        /// Tên người dùng đặt; chưa đặt thì là tên mặc định theo slot.
        let name: String
        var id: String { "\(type.rawValue)-\(index)" }

        static func defaultName(type: WorkspaceType, index: Int) -> String {
            "\(type.displayName) \(index + 1)"
        }

        /// Tên file trên Drive có tiền tố để dễ nhận ra trong Drive.
        static func driveTitle(for name: String) -> String {
            driveTitlePrefix + name
        }

        /// Ngược lại `driveTitle`; file bị đổi tên trên Drive (mất tiền tố) thì lấy nguyên tên.
        static func name(fromDriveTitle title: String) -> String? {
            let name = title.hasPrefix(driveTitlePrefix) ? String(title.dropFirst(driveTitlePrefix.count)) : title
            return name.trimmed.isEmpty ? nil : name.trimmed
        }

        /// Bỏ khoảng trắng, cắt bớt nếu quá dài; rỗng thì nil để dùng tên mặc định.
        static func sanitizedName(_ rawName: String) -> String? {
            let name = String(rawName.trimmed.prefix(maxNameLength))
            return name.isEmpty ? nil : name
        }

        static let maxNameLength = 40
        private static let driveTitlePrefix = "SplitNote - "
        
        // So sánh/hash theo `id` là đủ cho `List(selection:)`.
        static func == (lhs: Workspace, rhs: Workspace) -> Bool {
            lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
    
    /// Giao cho `ExpenseListView` khi tab tháng hiện tại đã sẵn sàng.
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
    @Published private(set) var openingWorkspaceId: String?
    @Published private(set) var isCreating = false
    @Published private(set) var deletingWorkspaceId: String?
    @Published var errorMessage: String?
    @Published private(set) var activeSession: ActiveSession?
    /// Mục đang chọn ở sidebar — gán giá trị thì mở workspace, gán nil thì đóng session.
    @Published var selectedWorkspace: Workspace? {
        didSet {
            guard selectedWorkspace != oldValue, !isApplyingProgrammaticSelection else { return }
            Task { await applySelection(selectedWorkspace) }
        }
    }
    private var isApplyingProgrammaticSelection = false
    /// Đúng tới khi đối chiếu Drive lần đầu xong — tránh tạo trùng sheet chưa kịp tìm thấy.
    @Published private(set) var isLoadingWorkspaces = true
    /// Đang tải lại thủ công (khác `isLoadingWorkspaces` chỉ cho lần đầu).
    @Published private(set) var isRefreshing = false
    
    private let sheetsService: SheetsServiceProtocol
    private let driveService: DriveServiceProtocol
    private let store: WorkspaceStore
    private let discoveryService: WorkspaceDiscoveryService
    /// Tên người tạo — thành viên đầu tiên của workspace gia đình.
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

    /// Tên gợi ý điền sẵn khi tạo mới — đúng slot sẽ được dùng.
    func suggestedName(for type: WorkspaceType) -> String {
        Workspace.defaultName(type: type, index: store.nextAvailableIndex(for: type) ?? 0)
    }

    /// Tên mới nhất theo `id` — bản đang giữ ở sidebar/selection có thể là tên cũ trước khi đổi.
    func displayName(of workspace: Workspace) -> String {
        workspaces.first { $0.id == workspace.id }?.name ?? workspace.name
    }

    func reloadWorkspaces() {
        workspaces = WorkspaceType.allCases.filter(\.isAvailable).flatMap { type in
            (0..<WorkspaceStore.maxInstancesPerType).compactMap { index in
                store.spreadsheetId(for: type, at: index).map { makeWorkspace(type: type, index: index, spreadsheetId: $0) }
            }
        }
    }

    private func makeWorkspace(type: WorkspaceType, index: Int, spreadsheetId: String) -> Workspace {
        let name = store.name(for: type, at: index) ?? Workspace.defaultName(type: type, index: index)
        return Workspace(type: type, index: index, spreadsheetId: spreadsheetId, name: name)
    }
    
    /// Chạy 1 lần khi mở màn: bỏ workspace đã xoá, tìm bù workspace từ thiết bị khác.
    func reconcileMissingWorkspaces() async {
        defer { isLoadingWorkspaces = false }
        await runDiscoveryReconcile()
    }

    /// Tải lại thủ công — giống `reconcileMissingWorkspaces`.
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
        // 3. Lấy tên từ Drive — đổi tên ở thiết bị khác hoặc trên Drive cũng thấy.
        await syncNamesFromDrive()
    }

    /// Lỗi mạng thì giữ tên đang cache, không báo lỗi.
    private func syncNamesFromDrive() async {
        await withTaskGroup(of: (Workspace, String?).self) { group in
            for workspace in workspaces {
                group.addTask { [driveService] in
                    (workspace, try? await driveService.fileName(fileId: workspace.spreadsheetId))
                }
            }
            // Đổi tiêu đề → tên trên MainActor vì `Workspace` bị cô lập MainActor theo mặc định.
            for await (workspace, title) in group {
                guard let name = title.flatMap({ Workspace.name(fromDriveTitle: $0) }) else { continue }
                store.setName(name, for: workspace.type, at: workspace.index)
            }
        }
        reloadWorkspaces()
    }

    /// Mở workspace vừa chọn; bỏ chọn thì đóng session.
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

    /// Đồng bộ lựa chọn với session đã mở sẵn (vd vừa tạo) mà không chạy lại `openWorkspace`.
    private func setSelection(to workspace: Workspace?) {
        isApplyingProgrammaticSelection = true
        selectedWorkspace = workspace
        isApplyingProgrammaticSelection = false
    }

    /// Mở workspace có sẵn: đảm bảo có tab tháng này rồi chuyển sang danh sách khoản chi.
    private func openWorkspace(_ workspace: Workspace) async {
        openingWorkspaceId = workspace.id
        errorMessage = nil
        // Xoá session cũ ngay để mở lỗi thì màn chi tiết không còn giữ dữ liệu workspace trước.
        activeSession = nil
        defer { openingWorkspaceId = nil }

        await open(workspace, tabTitle: Self.currentMonthTabTitle(), allowSelfHeal: true)
    }

    /// Đảm bảo có tab rồi mở; `allowSelfHeal` cho tìm lại id qua Drive đúng 1 lần trước khi báo đã xoá.
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

    /// Id cache hỏng — tìm lại slot qua tag Drive rồi mở tiếp, không ra mới báo đã xoá.
    private func selfHealAndRetry(_ workspace: Workspace, tabTitle: String) async {
        // 1. Bỏ id cũ, tìm lại qua Drive.
        store.clearSpreadsheetId(for: workspace.type, at: workspace.index)
        guard let rediscoveredId = try? await discoveryService.rediscoverWorkspace(type: workspace.type, index: workspace.index) else {
            markWorkspaceMissing(workspace)
            return
        }
        // 2. Lưu id mới rồi mở lại (không tự sửa thêm lần nữa).
        store.setSpreadsheetId(rediscoveredId, for: workspace.type, at: workspace.index)
        reloadWorkspaces()
        let healedWorkspace = makeWorkspace(type: workspace.type, index: workspace.index, spreadsheetId: rediscoveredId)
        await open(healedWorkspace, tabTitle: tabTitle, allowSelfHeal: false)
    }

    private func markWorkspaceMissing(_ workspace: Workspace) {
        store.clearSpreadsheetId(for: workspace.type, at: workspace.index)
        reloadWorkspaces()
        errorMessage = "\(workspace.name) đã bị xoá trên Drive, đã gỡ khỏi danh sách."
    }
    
    /// Tạo spreadsheet cho slot trống kế tiếp và gắn thẻ Drive để thiết bị khác tìm thấy; tên rỗng thì dùng tên mặc định.
    func createWorkspace(_ type: WorkspaceType, name rawName: String = "") async {
        guard type.isAvailable, let index = store.nextAvailableIndex(for: type) else { return }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        let tabTitle = Self.currentMonthTabTitle()
        let workspaceName = Workspace.sanitizedName(rawName) ?? Workspace.defaultName(type: type, index: index)
        // Gia đình bắt đầu chỉ với người tạo — thêm người khác ở màn thành viên.
        let members = type == .family ? [userDisplayName] : []
        do {
            // 1. Tạo spreadsheet.
            let created = try await sheetsService.createSpreadsheet(title: Workspace.driveTitle(for: workspaceName), firstTabTitle: tabTitle, members: members)
            // 2. Lưu local ngay để dùng được dù gắn thẻ lỗi.
            store.setSpreadsheetId(created.spreadsheetId, for: type, at: index)
            store.setName(workspaceName, for: type, at: index)
            reloadWorkspaces()
            // 3. Gắn thẻ Drive — lỗi chỉ cảnh báo, không chặn.
            await tagWorkspace(created.spreadsheetId, type: type, index: index, name: workspaceName)
            // 4. Mở luôn và đồng bộ sidebar, không chạy lại openWorkspace.
            activeSession = ActiveSession(spreadsheetId: created.spreadsheetId, tabTitle: tabTitle, spreadsheetURL: created.url, workspaceType: type)
            setSelection(to: makeWorkspace(type: type, index: index, spreadsheetId: created.spreadsheetId))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func tagWorkspace(_ spreadsheetId: String, type: WorkspaceType, index: Int, name: String) async {
        do {
            try await driveService.tagFile(fileId: spreadsheetId, key: StorageKeys.driveWorkspaceTag, value: WorkspaceDiscoveryService.tagValue(type: type, index: index))
        } catch {
            errorMessage = "\(name) đã tạo, nhưng gắn thẻ Drive thất bại nên có thể sẽ không tự tìm thấy được trên thiết bị khác: \(error.localizedDescription)"
        }
    }

    /// Đổi tên file trên Drive; hiện tên mới ngay, lỗi thì trả lại tên cũ.
    func renameWorkspace(_ workspace: Workspace, to rawName: String) async {
        let oldName = displayName(of: workspace)
        guard let newName = Workspace.sanitizedName(rawName), newName != oldName else { return }
        errorMessage = nil
        // 1. Cập nhật local trước để sidebar/tiêu đề đổi ngay.
        store.setName(newName, for: workspace.type, at: workspace.index)
        reloadWorkspaces()
        // 2. Đổi tên file trên Drive.
        do {
            try await driveService.renameFile(fileId: workspace.spreadsheetId, to: Workspace.driveTitle(for: newName))
        } catch {
            // 3. Lỗi thì trả lại tên cũ.
            store.setName(oldName, for: workspace.type, at: workspace.index)
            reloadWorkspaces()
            errorMessage = "Không thể đổi tên \(oldName): \(error.localizedDescription)"
        }
    }

    /// Chuyển sheet vào thùng rác rồi gỡ khỏi máy — thiết bị khác tự gỡ ở lần đối chiếu sau.
    func deleteWorkspace(_ workspace: Workspace) async {
        deletingWorkspaceId = workspace.id
        errorMessage = nil
        defer { deletingWorkspaceId = nil }

        do {
            // 1. Chuyển file vào thùng rác trên Drive.
            try await driveService.trashFile(fileId: workspace.spreadsheetId)
            // 2. Gỡ khỏi cache local.
            store.clearSpreadsheetId(for: workspace.type, at: workspace.index)
            reloadWorkspaces()
            // 3. Đang mở thì bỏ chọn — đi qua didSet bình thường để dọn activeSession.
            guard selectedWorkspace == workspace else { return }
            selectedWorkspace = nil
        } catch {
            errorMessage = "Không thể xoá \(workspace.name): \(error.localizedDescription)"
        }
    }
    
    private static func editURL(spreadsheetId: String) -> URL? {
        URL(string: "https://docs.google.com/spreadsheets/d/\(spreadsheetId)/edit")
    }

    static func currentMonthTabTitle(date: Date = AppClock.now) -> String {
        MonthTabTitle.title(for: date)
    }
}
