//
//  ExpenseListView.swift
//  SplitNote
//

import SwiftUI

/// Screen 2: expenses of the selected month's tab (mặc định tháng hiện tại,
/// lùi/tiến bằng 2 nút mũi tên). Tab thiếu thì hiện màn "tạo sheet", chỉ khi
/// đang xem tháng hiện tại — tháng cũ chưa dùng thì không cần tạo.
struct ExpenseListView: View {
    @StateObject private var viewModel: ExpenseListViewModel
    @State private var editingEntry: ExpenseEntry?
    @State private var entryPendingDeletion: ExpenseEntry?
    @State private var isShowingCategoryBreakdown = false
    @State private var isShowingMonthComparison = false
    private let spreadsheetId: String
    private let spreadsheetURL: URL?
    private let userDisplayName: String

    init(spreadsheetId: String, spreadsheetURL: URL?, workspaceType: WorkspaceType, userDisplayName: String) {
        self.spreadsheetId = spreadsheetId
        self.spreadsheetURL = spreadsheetURL
        self.userDisplayName = userDisplayName
        _viewModel = StateObject(wrappedValue: ExpenseListViewModel(spreadsheetId: spreadsheetId, workspaceType: workspaceType))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.sheetMissing {
                missingSheetView
            } else {
                expenseList
            }
        }
        .navigationTitle(viewModel.tabTitle)
        .toolbar {
            if !viewModel.sheetMissing {
                if viewModel.isFamily {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.isShowingMembers = true
                        } label: {
                            Image(systemName: "person.2")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isShowingCategoryBreakdown = true
                        } label: {
                            Label("Theo loại tháng này", systemImage: "chart.pie")
                        }
                        Button {
                            isShowingMonthComparison = true
                        } label: {
                            Label("So sánh theo tháng", systemImage: "chart.bar")
                        }
                    } label: {
                        Image(systemName: "chart.bar.xaxis")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.isShowingQuickAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingQuickAdd) {
            NavigationStack {
                QuickAddExpenseView(spreadsheetId: spreadsheetId, tabTitle: viewModel.tabTitle, members: viewModel.familyMembers.members, currentUserName: userDisplayName) {
                    Task { await viewModel.loadEntries() }
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            NavigationStack {
                QuickAddExpenseView(spreadsheetId: spreadsheetId, tabTitle: viewModel.tabTitle, editing: entry, members: viewModel.familyMembers.members, currentUserName: userDisplayName) {
                    Task { await viewModel.loadEntries() }
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingMembers) {
            NavigationStack {
                FamilyMembersView(viewModel: viewModel.familyMembers)
            }
        }
        .sheet(isPresented: $isShowingCategoryBreakdown) {
            CategoryBreakdownView(spreadsheetId: spreadsheetId, tabTitle: viewModel.tabTitle)
        }
        .sheet(isPresented: $isShowingMonthComparison) {
            MonthComparisonView(spreadsheetId: spreadsheetId)
        }
        .confirmationDialog(
            "Xoá khoản chi này?",
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { isPresented in if !isPresented { entryPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Xoá", role: .destructive) {
                if let entry = entryPendingDeletion {
                    Task { await viewModel.deleteEntry(entry) }
                }
                entryPendingDeletion = nil
            }
            Button("Huỷ", role: .cancel) {
                entryPendingDeletion = nil
            }
        }
        .task {
            await viewModel.loadEntries()
        }
        .refreshable {
            await viewModel.loadEntries()
        }
    }

    private var expenseList: some View {
        // Header ngoài List (không phải Section footer) để luôn ở trên cùng
        // khi danh sách dài ra, thay vì bị đẩy xuống cuối.
        VStack(spacing: 0) {
            monthNavigationHeader

            if !viewModel.entries.isEmpty {
                totalHeader
                Divider()
            }

            List {
                if viewModel.entries.isEmpty {
                    Text("Chưa có khoản chi nào trong tháng này — bấm + để thêm")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(viewModel.entries) { entry in
                            Button {
                                editingEntry = entry
                            } label: {
                                ExpenseRowView(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .destructiveRowAction {
                                entryPendingDeletion = entry
                            }
                        }
                    }
                }

                if let message = viewModel.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                }

                if let url = spreadsheetURL {
                    Section {
                        Link("Mở Google Sheet ↗", destination: url)
                    }
                }
            }
        }
    }

    private var monthNavigationHeader: some View {
        HStack {
            Button {
                viewModel.goToPreviousMonth()
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            Text(viewModel.tabTitle)
                .font(.headline)

            Spacer()

            Button {
                viewModel.goToNextMonth()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(viewModel.isCurrentMonth)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var totalHeader: some View {
        HStack {
            Text("Tổng cộng")
                .font(.headline)
            Spacer()
            Text(viewModel.totalAmount.formattedVND)
                .font(.headline)
                .monospacedDigit()
        }
        .padding()
    }

    private var missingSheetView: some View {
        VStack(spacing: 12) {
            monthNavigationHeader

            if viewModel.isCurrentMonth {
                Text("Chưa có sheet cho \(viewModel.tabTitle)")
                    .foregroundStyle(.secondary)

                Button {
                    Task { await viewModel.createMissingSheet() }
                } label: {
                    if viewModel.isCreatingSheet {
                        ProgressView()
                    } else {
                        Label("Tạo sheet tháng này", systemImage: "plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isCreatingSheet)
            } else {
                Text("Không có khoản chi nào cho \(viewModel.tabTitle)")
                    .foregroundStyle(.secondary)
            }

            if let message = viewModel.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding()
    }
}

private struct ExpenseRowView: View {
    let entry: ExpenseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.content.isEmpty ? entry.category : entry.content)
                Spacer()
                Text(entry.amount.formattedVND)
                    .monospacedDigit()
            }
            HStack {
                Text(entry.category)
                Spacer()
                Text(entry.date)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !entry.paidBy.isEmpty {
                Text(shareSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // Không có dòng này thì Spacer/padding không nhận tap được.
        .contentShape(Rectangle())
    }

    private var shareSummary: String {
        let sharedWith = entry.sharedWith.isEmpty ? "Tất cả" : entry.sharedWith
        return "\(entry.paidBy) chi · chia cho \(sharedWith)"
    }
}

#Preview {
    NavigationStack {
        ExpenseListView(spreadsheetId: "preview", spreadsheetURL: nil, workspaceType: .personal, userDisplayName: "Preview User")
    }
}
