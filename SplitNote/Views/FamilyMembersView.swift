//
//  FamilyMembersView.swift
//  SplitNote
//

import SwiftUI

/// Thêm/sửa/xoá thành viên gia đình; email nhập riêng, chỉ dùng để cấp quyền Drive.
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
                HStack(spacing: 12) {
                    TextField("Tên thành viên", text: $newMemberName, prompt: Text("Tên thành viên"))
                        .labelsHidden()
                        .onSubmit(addMember)
                    Button(action: addMember) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isNewMemberNameEmpty || viewModel.isSaving)
                }
                TextField("Email Google (tuỳ chọn)", text: $newMemberEmail, prompt: Text("Email Google (tuỳ chọn)"))
                    .labelsHidden()
                    .onSubmit(addMember)
            } header: {
                Text("Thêm thành viên")
            } footer: {
                Text("Có email thì người đó được cấp quyền sửa sheet và tự thấy workspace khi đăng nhập.")
            }

            Section {
                ForEach(viewModel.memberEntries) { member in
                    HStack(spacing: 12) {
                        MemberAvatar(name: member.name)
                        memberRow(member)
                    }
                    .destructiveRowAction(onEdit: { beginRename(member) }) {
                        Task { await viewModel.removeMember(member.name) }
                    }
                    .disabled(viewModel.isSaving)
                }
                if viewModel.memberEntries.isEmpty {
                    Text("Chưa có thành viên nào")
                        .foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("Thành viên hiện tại")
                    Spacer()
                    if viewModel.isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            } footer: {
                Text("Vuốt sang trái để xoá; chuột phải trên Mac để sửa tên hoặc xoá.")
            }

            if let message = viewModel.errorMessage {
                Section {
                    ErrorLabel(message: message)
                }
            }
        }
        .formStyle(.grouped)
        .textFieldStyle(.plain)
        .appBackground()
        .navigationTitle("Thành viên")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Xong") { dismiss() }
            }
        }
        .alert("Đổi tên hiển thị", isPresented: Binding(isPresent: $renamingMember), presenting: renamingMember) { member in
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

    private func beginRename(_ member: FamilyMember) {
        renameText = member.name
        renamingMember = member
    }

    private var isNewMemberNameEmpty: Bool {
        newMemberName.trimmed.isEmpty
    }

    /// Chỉ xoá ô nhập khi đã lưu thành công — lỗi thì giữ nguyên chữ để sửa lại.
    private func addMember() {
        guard !isNewMemberNameEmpty, !viewModel.isSaving else { return }
        Task {
            guard await viewModel.addMember(name: newMemberName, email: newMemberEmail) else { return }
            newMemberName = ""
            newMemberEmail = ""
        }
    }
}

/// Vòng tròn chữ cái đầu tô nhạt như `IconBadge`, màu cố định theo tên để mỗi người luôn cùng một màu.
private struct MemberAvatar: View {
    let name: String

    private static let palette: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .indigo, .red]

    private var color: Color {
        let seed = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.palette[seed % Self.palette.count]
    }

    var body: some View {
        Text(name.prefix(1).uppercased())
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background(color.opacity(0.18), in: Circle())
    }
}

#Preview {
    NavigationStack {
        FamilyMembersView(viewModel: FamilyMembersViewModel(spreadsheetId: "preview", tabTitle: "Tháng 09-2026", sheetsService: SheetsService()))
    }
}
