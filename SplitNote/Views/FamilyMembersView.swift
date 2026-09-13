//
//  FamilyMembersView.swift
//  SplitNote
//

import SwiftUI

/// Add/remove the names used by "Ai chi"/"Chi cho ai" in a `.family`
/// workspace. Local-only for now — there's no cross-account invite yet, so
/// this just types out names rather than adding real Google accounts (see
/// `WorkspaceStore.members`).
struct FamilyMembersView: View {
    @ObservedObject var viewModel: FamilyMembersViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newMemberName = ""

    var body: some View {
        Form {
            Section("Thêm thành viên") {
                HStack {
                    TextField("Tên thành viên", text: $newMemberName)
                        .onSubmit(addMember)
                    Button("Thêm", action: addMember)
                        .disabled(newMemberName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Thành viên hiện tại") {
                ForEach(viewModel.members, id: \.self) { member in
                    Text(member)
                        .destructiveRowAction {
                            Task { await viewModel.removeMember(member) }
                        }
                }
                if viewModel.members.isEmpty {
                    Text("Chưa có thành viên nào")
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isSaving {
                Section {
                    HStack {
                        ProgressView()
                        Text("Đang lưu...")
                    }
                }
            }

            if let message = viewModel.errorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Thành viên")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Xong") { dismiss() }
            }
        }
    }

    private func addMember() {
        let name = newMemberName
        newMemberName = ""
        Task { await viewModel.addMember(name) }
    }
}

#Preview {
    NavigationStack {
        FamilyMembersView(viewModel: FamilyMembersViewModel(spreadsheetId: "preview", tabTitle: "Tháng 09-2026", sheetsService: SheetsService()))
    }
}
