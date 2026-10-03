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
            Section("Thêm thành viên") {
                HStack(spacing: 12) {
                    TextField("Tên thành viên", text: $newMemberName, prompt: Text("Tên thành viên"))
                        .labelsHidden()
                        .onSubmit(addMember)
                    Button(action: addMember) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isNewMemberNameEmpty)
                }
            }

            Section {
                ForEach(viewModel.members, id: \.self) { member in
                    HStack(spacing: 12) {
                        MemberAvatar(name: member)
                        Text(member)
                    }
                    .destructiveRowAction {
                        Task { await viewModel.removeMember(member) }
                    }
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
                Text("Vuốt sang trái (hoặc chuột phải trên Mac) để xoá thành viên.")
            }

            if let message = viewModel.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .textFieldStyle(.plain)
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

    private var isNewMemberNameEmpty: Bool {
        newMemberName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func addMember() {
        let name = newMemberName
        let email = newMemberEmail
        newMemberName = ""
        newMemberEmail = ""
        Task { await viewModel.addMember(name: name, email: email) }
    }
}

/// Vòng tròn chữ cái đầu, màu cố định theo tên để mỗi người luôn cùng một màu.
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
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(color.gradient, in: Circle())
    }
}

#Preview {
    NavigationStack {
        FamilyMembersView(viewModel: FamilyMembersViewModel(spreadsheetId: "preview", tabTitle: "Tháng 09-2026", sheetsService: SheetsService()))
    }
}
