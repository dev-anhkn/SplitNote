//
//  QuickAddExpenseView.swift
//  SplitNote
//

import SwiftUI

/// The expense-entry form, always presented as a sheet from `ExpenseListView`
/// — either its "+" button (add) or tapping a row (edit).
struct QuickAddExpenseView: View {
    @StateObject private var viewModel: QuickAddExpenseViewModel
    @Environment(\.dismiss) private var dismiss
    private let screenTitle: String
    private let onSaved: () -> Void

    init(spreadsheetId: String, tabTitle: String, memberEntries: [FamilyMember] = [], currentUserName: String = "", currentUserEmail: String = "", onSaved: @escaping () -> Void) {
        self.screenTitle = "Thêm khoản chi"
        self.onSaved = onSaved
        _viewModel = StateObject(wrappedValue: QuickAddExpenseViewModel(spreadsheetId: spreadsheetId, tabTitle: tabTitle, memberEntries: memberEntries, currentUserName: currentUserName, currentUserEmail: currentUserEmail))
    }

    /// Edits an existing row in place instead of appending a new one.
    init(spreadsheetId: String, tabTitle: String, editing entry: ExpenseEntry, memberEntries: [FamilyMember] = [], currentUserName: String = "", currentUserEmail: String = "", onSaved: @escaping () -> Void) {
        self.screenTitle = "Sửa khoản chi"
        self.onSaved = onSaved
        _viewModel = StateObject(wrappedValue: QuickAddExpenseViewModel(spreadsheetId: spreadsheetId, tabTitle: tabTitle, editing: entry, memberEntries: memberEntries, currentUserName: currentUserName, currentUserEmail: currentUserEmail))
    }

    var body: some View {
        Form {
            amountSection
            detailSection
            if viewModel.isFamily {
                shareSection
            }

            if let message = viewModel.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        // Style .grouped + ẩn nhãn để các dòng thẳng hàng như iOS (mặc định trên macOS là 2 cột).
        .formStyle(.grouped)
        .textFieldStyle(.plain)
        .navigationTitle(screenTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Huỷ") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: attemptSubmit) {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Text("Lưu")
                    }
                }
                .disabled(!viewModel.canSubmit)
            }
        }
    }

    private var amountSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Số tiền")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("Số tiền", text: $viewModel.amountText, prompt: Text("0"))
                        .labelsHidden()
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .onSubmit(attemptSubmit)
                    Text("đ")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var detailSection: some View {
        Section("Chi tiết") {
            // .onSubmit trên từng field (không phải 1 lần trên Form) để Return submit được từ bất kỳ field nào.
            HStack(spacing: 12) {
                IconBadge(systemName: "text.alignleft", color: .gray, size: 28)
                TextField("Nội dung", text: $viewModel.content, prompt: Text("Nội dung"))
                    .labelsHidden()
                    .onSubmit(attemptSubmit)
            }
            // submitScope: Enter ở đây chỉ xác nhận gợi ý Loại, không submit cả form.
            CategoryPickerField(selection: $viewModel.category)
                .submitScope()
        }
    }

    private var shareSection: some View {
        Section("Chia tiền") {
            Picker(selection: $viewModel.paidBy) {
                ForEach(viewModel.members, id: \.self) { member in
                    Text(member).tag(member)
                }
            } label: {
                HStack(spacing: 12) {
                    IconBadge(systemName: "creditcard.fill", color: .green, size: 28)
                    Text("Ai chi")
                }
            }
            MemberShareField(members: viewModel.members, selectedMembers: $viewModel.selectedSharers)
        }
    }

    /// Shared by nút "Lưu" và Return; no-op nếu form chưa hợp lệ.
    private func attemptSubmit() {
        guard viewModel.canSubmit else { return }
        Task {
            await viewModel.submitEntry()
            if viewModel.didSave {
                onSaved()
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        QuickAddExpenseView(spreadsheetId: "preview", tabTitle: "Tháng 09-2026", onSaved: {})
    }
}
