//
//  WorkspaceListView.swift
//  SplitNote
//

import SwiftUI

/// Screen 1 after sign-in: the list of workspaces already created (personal,
/// family, ...). Tap one to enter its working session. The "+" button
/// creates a new one, asking which type first.
struct WorkspaceListView: View {
    @StateObject private var viewModel = WorkspaceListViewModel()
    let userDisplayName: String
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingWorkspaces {
                    ProgressView()
                } else {
                    List {
                        ForEach(viewModel.workspaces) { workspace in
                            Button {
                                Task { await viewModel.openWorkspace(workspace) }
                            } label: {
                                HStack {
                                    Text(workspace.type.displayName)
                                    Spacer()
                                    if viewModel.preparingType == workspace.type {
                                        ProgressView()
                                    }
                                }
                            }
                            .disabled(viewModel.preparingType != nil)
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
            .navigationTitle("Workspaces")
            .toolbar {
                if !viewModel.isLoadingWorkspaces {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.isShowingCreatePicker = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(viewModel.availableTypesToCreate.isEmpty || viewModel.preparingType != nil)
                    }
                }
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
            .navigationDestination(item: $viewModel.activeSession) { session in
                SheetSessionView(spreadsheetId: session.spreadsheetId, tabTitle: session.tabTitle, spreadsheetURL: session.spreadsheetURL)
            }
        }
        .task {
            await viewModel.reconcileMissingWorkspaces()
        }
    }
}

#Preview {
    WorkspaceListView(userDisplayName: "Preview User", onSignOut: {})
}
