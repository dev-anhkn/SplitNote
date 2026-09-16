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
            Section(screenTitle) {
                // .onSubmit trên từng field (không phải 1 lần trên Form) để Return
                // submit được từ bất kỳ field nào, thay vì chỉ chuyển focus.
                TextField("Số tiền", text: $viewModel.amountText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .onSubmit(attemptSubmit)
                TextField("Nội dung", text: $viewModel.content)
                    .onSubmit(attemptSubmit)
                // submitScope: Enter ở đây chỉ xác nhận gợi ý Loại, không submit cả form.
                CategoryPickerField(selection: $viewModel.category)
                    .submitScope()

                if viewModel.isFamily {
                    Picker("Ai chi", selection: $viewModel.paidBy) {
                        ForEach(viewModel.members, id: \.self) { member in
                            Text(member).tag(member)
                        }
                    }
                    MemberShareField(members: viewModel.members, selectedMembers: $viewModel.selectedSharers)
                }
            }

            if let message = viewModel.errorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
        }
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
