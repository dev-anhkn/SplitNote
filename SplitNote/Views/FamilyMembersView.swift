//
//  FamilyMembersView.swift
//  SplitNote
//

import SwiftUI

/// Add/remove the names used by "Ai chi"/"Chi cho ai" in a `.family`
/// workspace. Tên hiển thị là bắt buộc, nhập riêng với email — email chỉ
/// dùng để `FamilyMembersViewModel` cấp quyền edit Drive, nên tài khoản
/// Google tương ứng đăng nhập vào app sẽ tự thấy được workspace này. Tách
/// riêng từ đầu để "Ai chi"/"Chi cho ai" không bao giờ lấy thẳng email làm
/// tên hiển thị.
struct FamilyMembersView: View {
    @ObservedObject var viewModel: FamilyMembersViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newMemberName = ""
    @State private var newMemberEmail = ""
    @State private var renamingMember: FamilyMember?
    @State private var renameText = ""

    var body: some View {
        Form {
            Section {
                TextField("Tên hiển thị (bắt buộc)", text: $newMemberName)
                TextField("Email Google (tuỳ chọn, để cấp quyền)", text: $newMemberEmail)
                    .onSubmit(addMember)
                #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                #endif
                Button("Thêm", action: addMember)
                    .disabled(newMemberName.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Thêm thành viên")
            } footer: {
                Text("Tên hiển thị dùng trong \"Ai chi\"/\"Chi cho ai\". Nhập thêm email Google sẽ tự cấp quyền chỉnh sửa sheet cho người đó — họ đăng nhập đúng email này trong app là thấy workspace ngay.")
            }

            Section("Thành viên hiện tại") {
                ForEach(viewModel.memberEntries) { member in
                    memberRow(member)
                        .swipeActions(edge: .leading) {
                            Button("Đổi tên") { beginRename(member) }
                                .tint(.blue)
                        }
                        .contextMenu {
                            Button("Đổi tên") { beginRename(member) }
                        }
                        .destructiveRowAction {
                            Task { await viewModel.removeMember(member.name) }
                        }
                }
                if viewModel.memberEntries.isEmpty {
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
        .alert("Đổi tên hiển thị", isPresented: renameAlertBinding, presenting: renamingMember) { member in
            TextField("Tên hiển thị", text: $renameText)
            Button("Lưu") {
                Task { await viewModel.renameMember(id: member.id, to: renameText) }
            }
            Button("Huỷ", role: .cancel) {}
        } message: { member in
            if let email = member.email {
                Text("Quyền Drive vẫn gắn với \(email), không đổi.")
            }
        }
    }

    private func memberRow(_ member: FamilyMember) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(member.name)
            if let email = member.email, email != member.name {
                Text(email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(get: { renamingMember != nil }, set: { if !$0 { renamingMember = nil } })
    }

    private func beginRename(_ member: FamilyMember) {
        renameText = member.name
        renamingMember = member
    }

    private func addMember() {
        let name = newMemberName
        let email = newMemberEmail
        newMemberName = ""
        newMemberEmail = ""
        Task { await viewModel.addMember(name: name, email: email) }
    }
}

#Preview {
    NavigationStack {
        FamilyMembersView(viewModel: FamilyMembersViewModel(spreadsheetId: "preview", tabTitle: "Tháng 09-2026", sheetsService: SheetsService()))
    }
}
