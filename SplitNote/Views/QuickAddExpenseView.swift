//
//  QuickAddExpenseView.swift
//  SplitNote
//

import SwiftUI

/// Form nhập khoản chi, mở dạng sheet từ `ExpenseListView` (nút "+" để thêm, chạm hàng để sửa).
struct QuickAddExpenseView: View {
    @StateObject private var viewModel: QuickAddExpenseViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isAmountFocused: Bool
    private let screenTitle: String
    private let onSaved: () -> Void

    init(spreadsheetId: String, tabTitle: String, memberEntries: [FamilyMember] = [], currentUserName: String = "", currentUserEmail: String = "", onSaved: @escaping () -> Void) {
        self.screenTitle = "Thêm khoản chi"
        self.onSaved = onSaved
        _viewModel = StateObject(wrappedValue: QuickAddExpenseViewModel(spreadsheetId: spreadsheetId, tabTitle: tabTitle, memberEntries: memberEntries, currentUserName: currentUserName, currentUserEmail: currentUserEmail))
    }

    /// Sửa đúng hàng có sẵn thay vì thêm hàng mới.
    init(spreadsheetId: String, tabTitle: String, editing entry: ExpenseEntry, memberEntries: [FamilyMember] = [], currentUserName: String = "", currentUserEmail: String = "", onSaved: @escaping () -> Void) {
        self.screenTitle = "Sửa khoản chi"
        self.onSaved = onSaved
        _viewModel = StateObject(wrappedValue: QuickAddExpenseViewModel(spreadsheetId: spreadsheetId, tabTitle: tabTitle, editing: entry, memberEntries: memberEntries, currentUserName: currentUserName, currentUserEmail: currentUserEmail))
    }

    var body: some View {
        Form {
            if let summary = viewModel.lastSavedSummary {
                Section {
                    Label("Đã lưu: \(summary) · \(viewModel.savedCount) khoản", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }
            }
            amountSection
            detailSection
            if viewModel.isFamily {
                shareSection
            }

            if let message = viewModel.errorMessage {
                Section {
                    ErrorLabel(message: message)
                }
            } else if let hint = viewModel.missingFieldsHint {
                Section {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(.snappy, value: viewModel.savedCount)
        // ⌘Return: lưu rồi đóng luôn — Return thường thì lưu và giữ form để nhập tiếp.
        .background {
            Button("", action: { attemptSubmit(closeAfterSave: true) })
                .keyboardShortcut(.return, modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        }
        .onAppear { isAmountFocused = true }
        // Style .grouped + ẩn nhãn để các dòng thẳng hàng như iOS (mặc định trên macOS là 2 cột).
        .formStyle(.grouped)
        .textFieldStyle(.plain)
        .appBackground()
        .navigationTitle(screenTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                // Đã lưu ít nhất 1 khoản thì không còn gì để huỷ.
                Button(viewModel.savedCount > 0 ? "Xong" : "Huỷ") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: { attemptSubmit(closeAfterSave: viewModel.isEditing) }) {
                    if viewModel.isSubmitting {
                        ProgressView()
                    } else {
                        Text("Lưu")
                    }
                }
                .buttonStyle(.primary)
                .disabled(!viewModel.canSubmit)
                .help(viewModel.isEditing ? "Lưu thay đổi" : "Lưu và nhập tiếp (Return) · Lưu rồi đóng (⌘Return)")
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
                        .focused($isAmountFocused)
                        .onSubmit { attemptSubmit() }
                        // Co theo nội dung để "đ" đứng sát ngay sau con số.
                        .fixedSize()
                    Text("đ")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                // Cả hàng nhận click để focus, vì ô số đã co hẹp theo nội dung.
                .contentShape(Rectangle())
                .onTapGesture { isAmountFocused = true }
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
                    .onSubmit { attemptSubmit() }
            }
            // submitScope: trên iOS Enter ở ô Loại chỉ xác nhận gợi ý, không submit cả form.
            CategoryPickerField(selection: $viewModel.category, onSubmit: { attemptSubmit() })
                .submitScope()
            dateRow
        }
    }

    private var dateRow: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: "calendar", color: AppStyle.gold, size: 28)
            Text("Ngày")
            Spacer(minLength: 8)
            if viewModel.canPickToday {
                SelectableChip(title: "Hôm nay", isSelected: viewModel.isToday, action: viewModel.pickToday)
            }
            if viewModel.canPickYesterday {
                SelectableChip(title: "Hôm qua", isSelected: viewModel.isYesterday, action: viewModel.pickYesterday)
            }
            #if os(macOS)
            // Nút mở lịch thay cho ô chữ ngày/tháng/năm — ô chữ giữ phím Tab lại bên trong.
            CalendarPopoverButton(date: $viewModel.date, range: viewModel.dateRange)
            #else
            DatePicker("Ngày", selection: $viewModel.date, in: viewModel.dateRange, displayedComponents: .date)
                .labelsHidden()
            #endif
        }
        #if os(macOS)
        .keyboardStepper(
            onUp: { viewModel.shiftDate(byDays: 1) },
            onDown: { viewModel.shiftDate(byDays: -1) },
            onSubmit: { attemptSubmit() }
        )
        .help("↑/↓ đổi ngày")
        #endif
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

    /// Dùng chung cho nút "Lưu" và Return; thêm mới thì mặc định giữ form mở để nhập tiếp.
    private func attemptSubmit(closeAfterSave: Bool = false) {
        guard viewModel.canSubmit else { return }
        Task {
            // 1. Lưu; lỗi thì dừng (thông báo đã hiện trên form).
            await viewModel.submitEntry()
            guard viewModel.didSave else { return }
            // 2. Báo màn danh sách tải lại.
            onSaved()
            // 3. Đóng form, hoặc focus lại ô số tiền để nhập tiếp.
            guard closeAfterSave || viewModel.isEditing else {
                isAmountFocused = true
                return
            }
            dismiss()
        }
    }
}

#if os(macOS)
/// Hiện ngày đang chọn, bấm thì mở lịch; chọn xong tự đóng.
private struct CalendarPopoverButton: View {
    @Binding var date: Date
    let range: ClosedRange<Date>
    @State private var isShowingCalendar = false

    var body: some View {
        Button {
            isShowingCalendar = true
        } label: {
            Text(date, format: .dateTime.day().month(.twoDigits).year())
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingCalendar, arrowEdge: .bottom) {
            DatePicker("Ngày", selection: $date, in: range, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding()
        }
        .onChange(of: date) {
            isShowingCalendar = false
        }
    }
}
#endif

#Preview {
    NavigationStack {
        QuickAddExpenseView(spreadsheetId: "preview", tabTitle: "Tháng 09-2026", onSaved: {})
    }
}
