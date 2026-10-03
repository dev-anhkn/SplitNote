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
    @State private var isShowingQuickAdd = false
    @State private var isShowingMembers = false
    @State private var isReloading = false
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
                            isShowingMembers = true
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
                        isShowingQuickAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingQuickAdd) {
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
        .sheet(isPresented: $isShowingMembers) {
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
        // Header ngoài List (không phải Section footer) để luôn ở trên cùng khi danh sách dài ra.
        VStack(spacing: 12) {
            monthNavigationHeader
            summaryCard
                .padding(.horizontal)

            List {
                if !viewModel.entries.isEmpty {
                    Section("Khoản chi") {
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
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if let url = spreadsheetURL {
                    Section {
                        Link(destination: url) {
                            Label("Mở Google Sheet", systemImage: "arrow.up.right.square")
                        }
                    }
                }
            }
            .overlay {
                if viewModel.entries.isEmpty {
                    ContentUnavailableView(
                        "Chưa có khoản chi",
                        systemImage: "tray",
                        description: Text("Bấm + để thêm khoản chi đầu tiên của tháng này.")
                    )
                }
            }
        }
    }

    private var monthNavigationHeader: some View {
        HStack {
            MonthStepButton(systemName: "chevron.left") {
                viewModel.goToPreviousMonth()
            }

            Spacer()

            HStack(spacing: 8) {
                Text(viewModel.tabTitle)
                    .font(.system(.headline, design: .rounded))
                #if os(macOS)
                // macOS không có kéo-xuống-để-tải-lại như iOS nên cần nút riêng.
                reloadButton
                #endif
            }

            Spacer()

            MonthStepButton(systemName: "chevron.right") {
                viewModel.goToNextMonth()
            }
            .disabled(viewModel.isCurrentMonth)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var reloadButton: some View {
        ReloadButton(isLoading: isReloading, help: "Tải lại khoản chi (⌘R)") {
            Task { await reload() }
        }
        .keyboardShortcut("r", modifiers: .command)
    }

    private func reload() async {
        isReloading = true
        defer { isReloading = false }
        await viewModel.loadEntries()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tổng chi tháng này")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(viewModel.totalAmount.formattedVND)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            StatusPill(text: "\(viewModel.entries.count) khoản chi", color: .accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var missingSheetView: some View {
        VStack(spacing: 16) {
            monthNavigationHeader

            Spacer()

            if viewModel.isCurrentMonth {
                ContentUnavailableView {
                    Label("Chưa có sheet cho \(viewModel.tabTitle)", systemImage: "tablecells.badge.ellipsis")
                } description: {
                    Text("Tạo sheet để bắt đầu ghi chi tiêu tháng này.")
                } actions: {
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
                    .controlSize(.large)
                    .disabled(viewModel.isCreatingSheet)
                }
            } else {
                ContentUnavailableView(
                    "Không có khoản chi nào",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("\(viewModel.tabTitle) chưa được ghi chi tiêu.")
                )
            }

            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding()
    }
}

private struct MonthStepButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(.quaternary.opacity(0.5), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct ExpenseRowView: View {
    let entry: ExpenseEntry

    private var category: ExpenseCategory {
        ExpenseCategory.from(entry.category)
    }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: category.icon, color: category.color, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.content.isEmpty ? entry.category : entry.content)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text(entry.amount.formattedVND)
                        .font(.body.weight(.semibold))
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
                    Label(shareSummary, systemImage: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
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
