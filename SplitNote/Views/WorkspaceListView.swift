//
//  WorkspaceListView.swift
//  SplitNote
//

import SwiftUI

/// Màn đầu sau đăng nhập: danh sách workspace (sidebar trên Mac/iPad, push trên iPhone).
struct WorkspaceListView: View {
    @StateObject private var viewModel: WorkspaceListViewModel
    @State private var workspacePendingDeletion: WorkspaceListViewModel.Workspace?
    @State private var isShowingCreatePicker = false
    /// Loại đang chờ đặt tên trước khi tạo.
    @State private var namingType: WorkspaceType?
    @State private var newWorkspaceName = ""
    @State private var renamingWorkspace: WorkspaceListViewModel.Workspace?
    @State private var renameText = ""
    /// Bản sao cho `List(selection:)` — ghi thẳng vào `@Published` trong lúc vẽ sẽ bị cảnh báo.
    @State private var sidebarSelection: WorkspaceListViewModel.Workspace?
    let userDisplayName: String
    let userEmail: String
    let onSignOut: () -> Void

    init(userDisplayName: String, userEmail: String, onSignOut: @escaping () -> Void) {
        self.userDisplayName = userDisplayName
        self.userEmail = userEmail
        self.onSignOut = onSignOut
        _viewModel = StateObject(wrappedValue: WorkspaceListViewModel(userDisplayName: userDisplayName))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                // Chặn dưới: hẹp hơn thì nút tài khoản bị dồn vào menu "»" và cắt chữ; vẫn cho kéo rộng như sidebar macOS.
                .navigationSplitViewColumnWidth(min: AppStyle.sidebarMinWidth, ideal: AppStyle.sidebarMinWidth, max: AppStyle.sidebarMaxWidth)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppBackground())
        }
        .task {
            await viewModel.reconcileMissingWorkspaces()
        }
        // Đồng bộ 2 chiều sau khi cập nhật xong: người dùng bấm → view model; view model tự chọn (vd vừa tạo) → sidebar.
        .onChange(of: sidebarSelection) { _, newValue in
            guard viewModel.selectedWorkspace != newValue else { return }
            viewModel.selectedWorkspace = newValue
        }
        .onChange(of: viewModel.selectedWorkspace, initial: true) { _, newValue in
            guard sidebarSelection != newValue else { return }
            sidebarSelection = newValue
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        Group {
            if viewModel.isLoadingWorkspaces {
                ProgressView()
            } else {
                List(selection: $sidebarSelection) {
                    ForEach(viewModel.workspaces) { workspace in
                        WorkspaceRow(workspace: workspace, title: workspace.name, isOpening: viewModel.openingWorkspaceId == workspace.id)
                        .tag(workspace)
                        .disabled(viewModel.isBusy)
                        .destructiveRowAction(editTitle: "Đổi tên", onEdit: { beginRename(workspace) }) {
                            workspacePendingDeletion = workspace
                        }
                    }

                    if let message = viewModel.errorMessage {
                        ErrorLabel(message: message)
                    }
                }
                .overlay {
                    if viewModel.workspaces.isEmpty {
                        ContentUnavailableView(
                            "Chưa có workspace",
                            systemImage: "tray",
                            description: Text("Bấm \"Workspace mới\" để tạo sổ chi tiêu đầu tiên.")
                        )
                    }
                }
                // Tách khỏi toolbar để không bị gộp vào menu ">>" khi sidebar hẹp.
                .safeAreaInset(edge: .bottom) {
                    createWorkspaceBar
                }
                #if os(macOS)
                // Toolbar trên macOS dùng chung với màn chi tiết nên nút bị đẩy vào ">>" — đặt riêng trong sidebar.
                .safeAreaInset(edge: .top) {
                    sidebarHeader
                }
                #endif
            }
        }
        .navigationTitle("Workspaces")
        .toolbar {
            #if os(iOS)
            if !viewModel.isLoadingWorkspaces {
                ToolbarItem(placement: .primaryAction) {
                    refreshButton
                }
            }
            #endif
            ToolbarItem(placement: .cancellationAction) {
                Menu {
                    Text(userDisplayName)
                    Button("Sign Out", role: .destructive, action: onSignOut)
                } label: {
                    Image(systemName: "person.crop.circle.fill")
                }
            }
        }
        .confirmationDialog("Tạo workspace mới", isPresented: $isShowingCreatePicker, titleVisibility: .visible) {
            ForEach(viewModel.availableTypesToCreate, id: \.self) { type in
                Button(type.displayName) {
                    beginNaming(type)
                }
            }
        }
        .alert("Workspace mới", isPresented: Binding(isPresent: $namingType), presenting: namingType) { type in
            TextField(viewModel.suggestedName(for: type), text: $newWorkspaceName)
            Button("Tạo") {
                Task { await viewModel.createWorkspace(type, name: newWorkspaceName) }
            }
            Button("Huỷ", role: .cancel) {}
        } message: { _ in
            Text("Đặt tên để dễ phân biệt, vd \"Chi tiêu tháng\", \"Du lịch\". Đổi lại được sau.")
        }
        .alert("Đổi tên workspace", isPresented: Binding(isPresent: $renamingWorkspace), presenting: renamingWorkspace) { workspace in
            TextField("Tên workspace", text: $renameText)
            Button("Lưu") {
                Task { await viewModel.renameWorkspace(workspace, to: renameText) }
            }
            Button("Huỷ", role: .cancel) {}
        } message: { _ in
            Text("Tên file trên Google Drive cũng được đổi theo.")
        }
        .confirmationDialog(
            "Xoá \(workspacePendingDeletion.map(viewModel.displayName(of:)) ?? "")?",
            isPresented: Binding(isPresent: $workspacePendingDeletion),
            titleVisibility: .visible
        ) {
            Button("Xoá", role: .destructive, action: confirmDeletion)
            Button("Huỷ", role: .cancel) {
                workspacePendingDeletion = nil
            }
        } message: {
            Text("Sheet trên Google Drive sẽ được chuyển vào Thùng rác, không xoá vĩnh viễn ngay.")
        }
    }

    private var refreshButton: some View {
        ReloadButton(isLoading: viewModel.isRefreshing, help: "Tải lại danh sách workspace") {
            Task { await viewModel.refreshWorkspaces() }
        }
        .disabled(viewModel.isBusy)
    }

    private var sidebarHeader: some View {
        HStack {
            Text("Workspaces")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            refreshButton
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var createWorkspaceBar: some View {
        HStack {
            Button(action: beginCreate) {
                HStack(spacing: 6) {
                    if viewModel.isCreating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    Text("Workspace mới")
                        .fontWeight(.medium)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(isCreateLimitReached || viewModel.isBusy)

            Spacer()

            if isCreateLimitReached {
                Text("Tối đa \(WorkspaceStore.maxInstancesPerType)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Xoá bớt 1 workspace để tạo mới")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var isCreateLimitReached: Bool {
        viewModel.availableTypesToCreate.isEmpty
    }

    /// Chỉ có 1 loại tạo được thì vào thẳng bước đặt tên, khỏi hỏi chọn loại.
    private func beginCreate() {
        let types = viewModel.availableTypesToCreate
        guard types.count > 1 else {
            types.first.map(beginNaming)
            return
        }
        isShowingCreatePicker = true
    }

    /// Điền sẵn tên gợi ý — bấm Tạo luôn cũng được.
    private func beginNaming(_ type: WorkspaceType) {
        newWorkspaceName = viewModel.suggestedName(for: type)
        namingType = type
    }

    private func beginRename(_ workspace: WorkspaceListViewModel.Workspace) {
        renameText = viewModel.displayName(of: workspace)
        renamingWorkspace = workspace
    }

    private func confirmDeletion() {
        defer { workspacePendingDeletion = nil }
        guard let workspace = workspacePendingDeletion else { return }
        Task { await viewModel.deleteWorkspace(workspace) }
    }

    @ViewBuilder
    private var detail: some View {
        if let session = viewModel.activeSession {
            // .id() bắt buộc — không có thì @StateObject bên trong giữ dữ liệu workspace cũ.
            ExpenseListView(
                spreadsheetId: session.spreadsheetId,
                spreadsheetURL: session.spreadsheetURL,
                workspaceType: session.workspaceType,
                workspaceTitle: viewModel.selectedWorkspace.map(viewModel.displayName(of:)) ?? session.workspaceType.displayName,
                userDisplayName: userDisplayName,
                userEmail: userEmail
            )
            .id(session.id)
        } else if viewModel.selectedWorkspace != nil {
            // Đã chọn workspace, openWorkspace vẫn đang chạy.
            ProgressView()
        } else {
            ContentUnavailableView(
                "Chọn một workspace",
                systemImage: "sidebar.left",
                description: Text("Chọn sổ chi tiêu ở danh sách bên trái để xem các khoản chi.")
            )
        }
    }
}

private struct WorkspaceRow: View {
    let workspace: WorkspaceListViewModel.Workspace
    /// Tách riêng vì `Workspace` so sánh theo id — đổi tên mà không tách thì hàng có thể không vẽ lại.
    let title: String
    let isOpening: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: workspace.type.icon, color: workspace.type.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(workspace.type == .family ? "Chia tiền nhóm" : "Chi tiêu riêng")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isOpening {
                ProgressView()
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    WorkspaceListView(userDisplayName: "Preview User", userEmail: "preview@example.com", onSignOut: {})
}
