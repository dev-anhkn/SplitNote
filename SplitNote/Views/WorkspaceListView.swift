//
//  WorkspaceListView.swift
//  SplitNote
//

import SwiftUI

/// Screen 1 after sign-in: list of workspaces already created (up to
/// `WorkspaceStore.maxInstancesPerType` per type). `NavigationSplitView`
/// adapts on its own: sidebar+detail on Mac/iPad, list-then-push on iPhone.
struct WorkspaceListView: View {
    @StateObject private var viewModel: WorkspaceListViewModel
    @State private var workspacePendingDeletion: WorkspaceListViewModel.Workspace?
    @State private var isShowingCreatePicker = false
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
        } detail: {
            detail
        }
        .task {
            await viewModel.reconcileMissingWorkspaces()
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        Group {
            if viewModel.isLoadingWorkspaces {
                ProgressView()
            } else {
                List(selection: $viewModel.selectedWorkspace) {
                    ForEach(viewModel.workspaces) { workspace in
                        WorkspaceRow(workspace: workspace, isOpening: viewModel.openingWorkspaceId == workspace.id)
                        .tag(workspace)
                        .disabled(viewModel.isBusy)
                        .destructiveRowAction {
                            workspacePendingDeletion = workspace
                        }
                    }

                    if let message = viewModel.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .overlay {
                    if viewModel.workspaces.isEmpty {
                        ContentUnavailableView(
                            "Chưa có workspace",
                            systemImage: "tray",
                            description: Text("Bấm \"Workspace mới\" để tạo sổ chi tiêu cá nhân hoặc gia đình.")
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
                    Task { await viewModel.createWorkspace(type) }
                }
            }
        }
        .confirmationDialog(
            "Xoá \(workspacePendingDeletion?.displayName ?? "")?",
            isPresented: Binding(
                get: { workspacePendingDeletion != nil },
                set: { isPresented in if !isPresented { workspacePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Xoá", role: .destructive) {
                if let workspace = workspacePendingDeletion {
                    Task { await viewModel.deleteWorkspace(workspace) }
                }
                workspacePendingDeletion = nil
            }
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
            Button {
                isShowingCreatePicker = true
            } label: {
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
            .disabled(viewModel.availableTypesToCreate.isEmpty || viewModel.isBusy)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let session = viewModel.activeSession {
            // .id() bắt buộc — không có thì @StateObject bên trong
            // ExpenseListView giữ nguyên theo identity view cũ khi đổi
            // workspace, vẫn hiện danh sách của spreadsheetId trước đó.
            ExpenseListView(
                spreadsheetId: session.spreadsheetId,
                spreadsheetURL: session.spreadsheetURL,
                workspaceType: session.workspaceType,
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
    let isOpening: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: workspace.type.icon, color: workspace.type.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.displayName)
                    .font(.body.weight(.medium))
                Text(workspace.type == .family ? "Chia tiền nhiều người" : "Chi tiêu của riêng bạn")
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
