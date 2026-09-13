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
    let userDisplayName: String
    let onSignOut: () -> Void

    init(userDisplayName: String, onSignOut: @escaping () -> Void) {
        self.userDisplayName = userDisplayName
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
                        HStack {
                            Text(workspace.displayName)
                            Spacer()
                            if viewModel.openingWorkspaceId == workspace.id {
                                ProgressView()
                            }
                        }
                        .tag(workspace)
                        .disabled(viewModel.isBusy)
                        .destructiveRowAction {
                            workspacePendingDeletion = workspace
                        }
                    }

                    if viewModel.workspaces.isEmpty {
                        Text("Chưa có workspace nào — bấm + để tạo")
                            .foregroundStyle(.secondary)
                    }

                    if let message = viewModel.errorMessage {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        // Neo riêng cạnh danh sách workspace thay vì bỏ vào toolbar hệ thống
        // — trên macOS, toolbar hay tự gộp các nút lại thành 1 nút overflow
        // khi cửa sổ hẹp, khiến nút + bị lẫn chung với menu Sign Out.
        .safeAreaInset(edge: .top) {
            if !viewModel.isLoadingWorkspaces {
                sidebarActions
            }
        }
        .navigationTitle("Workspaces")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Menu {
                    Text(userDisplayName)
                    Button("Sign Out", role: .destructive, action: onSignOut)
                } label: {
                    Image(systemName: "person.circle")
                }
            }
        }
        .confirmationDialog("Tạo workspace mới", isPresented: $viewModel.isShowingCreatePicker, titleVisibility: .visible) {
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

    /// Thanh nút riêng cho khu vực workspace (reload + tạo mới), tách biệt
    /// khỏi menu tài khoản/Sign Out ở toolbar hệ thống.
    private var sidebarActions: some View {
        HStack(spacing: 16) {
            Spacer()
            Button {
                Task { await viewModel.refreshWorkspaces() }
            } label: {
                if viewModel.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(viewModel.isBusy)
            .help("Tải lại danh sách workspace")

            Button {
                viewModel.isShowingCreatePicker = true
            } label: {
                if viewModel.isCreating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "plus")
                }
            }
            .disabled(viewModel.availableTypesToCreate.isEmpty || viewModel.isBusy)
            .help("Tạo workspace mới")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
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
                userDisplayName: userDisplayName
            )
            .id(session.id)
        } else if viewModel.selectedWorkspace != nil {
            // Đã chọn workspace, openWorkspace vẫn đang chạy.
            ProgressView()
        } else {
            ContentUnavailableView("Chọn một workspace", systemImage: "tray")
        }
    }
}

#Preview {
    WorkspaceListView(userDisplayName: "Preview User", onSignOut: {})
}
