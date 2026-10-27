//
//  ExpenseListView.swift
//  SplitNote
//

import SwiftUI

/// Màn khoản chi của tháng đang chọn; thiếu tab tháng hiện tại thì hiện màn "tạo sheet".
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
    private let workspaceTitle: String
    private let workspaceType: WorkspaceType
    private var workspaceColor: Color { workspaceType.color }
    @Environment(\.colorScheme) private var colorScheme
    private let userDisplayName: String
    private let userEmail: String

    init(spreadsheetId: String, spreadsheetURL: URL?, workspaceType: WorkspaceType, workspaceTitle: String, userDisplayName: String, userEmail: String) {
        self.spreadsheetId = spreadsheetId
        self.spreadsheetURL = spreadsheetURL
        self.workspaceTitle = workspaceTitle
        self.workspaceType = workspaceType
        self.userDisplayName = userDisplayName
        self.userEmail = userEmail
        _viewModel = StateObject(wrappedValue: ExpenseListViewModel(spreadsheetId: spreadsheetId, workspaceType: workspaceType))
    }

    var body: some View {
        withPresentedSheets(content)
            // Tháng đã hiện trong thẻ tổng chi — tiêu đề dùng tên workspace cho khỏi lặp.
            .navigationTitle(workspaceTitle)
            .toolbar { toolbarContent }
            .confirmationDialog(
                "Xoá khoản chi này?",
                isPresented: Binding(isPresent: $entryPendingDeletion),
                titleVisibility: .visible
            ) {
                Button("Xoá", role: .destructive, action: confirmDeletion)
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
            #if os(macOS)
            .focusedSceneValue(\.quickAddAction, quickAddAction)
            #endif
    }

    #if os(macOS)
    /// Chỉ cho ⌘N mở Quick Add khi tháng đã có sheet; chưa có thì tắt lệnh.
    private var quickAddAction: (() -> Void)? {
        guard !viewModel.sheetMissing else { return nil }
        return { isShowingQuickAdd = true }
    }
    #endif

    @ViewBuilder
    private var content: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.sheetMissing {
                missingSheetView
            } else {
                expenseList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground())
    }

    // MARK: - Toolbar & sheet

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
                #if os(iOS)
                // macOS dùng lệnh menu ⌘N (SplitNoteCommands) nên không gắn phím ở nút.
                .keyboardShortcut("n", modifiers: .command)
                #endif
                .help("Thêm khoản chi (⌘N)")
            }
        }
    }

    /// Gắn các sheet con: thêm/sửa khoản chi, thành viên, biểu đồ.
    private func withPresentedSheets(_ content: some View) -> some View {
        content
            .sheet(isPresented: $isShowingQuickAdd) {
                NavigationStack {
                    QuickAddExpenseView(spreadsheetId: spreadsheetId, tabTitle: viewModel.tabTitle, memberEntries: viewModel.familyMembers.memberEntries, currentUserName: userDisplayName, currentUserEmail: userEmail) {
                        Task { await viewModel.loadEntries() }
                    }
                }
            }
            .sheet(item: $editingEntry) { entry in
                NavigationStack {
                    QuickAddExpenseView(spreadsheetId: spreadsheetId, tabTitle: viewModel.tabTitle, editing: entry, memberEntries: viewModel.familyMembers.memberEntries, currentUserName: userDisplayName, currentUserEmail: userEmail) {
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
    }

    private func confirmDeletion() {
        defer { entryPendingDeletion = nil }
        guard let entry = entryPendingDeletion else { return }
        Task { await viewModel.deleteEntry(entry) }
    }

    // MARK: - Nội dung

    private var expenseList: some View {
        // Header ngoài List (không phải Section footer) để luôn ở trên cùng khi danh sách dài ra.
        VStack(spacing: 4) {
            summaryCard
                .padding(.horizontal)
                .padding(.top, 8)

            List {
                // Tiêu đề ngày là 1 hàng thường (không phải Section header) — tránh dải nền xám của header List trên macOS.
                ForEach(viewModel.daySections) { section in
                    DayHeaderView(title: section.title, total: section.total)
                    ForEach(section.entries) { entry in
                        Button {
                            editingEntry = entry
                        } label: {
                            ExpenseRowView(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .destructiveRowAction(onEdit: { editingEntry = entry }) {
                            entryPendingDeletion = entry
                        }
                    }
                }

                if let message = viewModel.errorMessage {
                    ErrorLabel(message: message)
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .overlay {
                if viewModel.isSwitchingMonth {
                    ProgressView()
                } else if viewModel.entries.isEmpty {
                    ContentUnavailableView(
                        "Chưa có khoản chi",
                        systemImage: "tray",
                        description: Text("Bấm + để thêm khoản chi đầu tiên của tháng này.")
                    )
                }
            }
        }
    }

    /// ‹ tháng › gộp trong 1 viên thuốc, thay cho 2 nút tròn tách rời 2 đầu màn hình.
    private var monthSwitcher: some View {
        HStack(spacing: 2) {
            MonthStepButton(systemName: "chevron.left") {
                viewModel.goToPreviousMonth()
            }
            Text(MonthTabTitle.displayLabel(for: viewModel.selectedMonth))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 104)
            MonthStepButton(systemName: "chevron.right") {
                viewModel.goToNextMonth()
            }
            .disabled(viewModel.isCurrentMonth)
        }
        .padding(3)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private var reloadButton: some View {
        SubtleReloadButton(isLoading: isReloading, help: "Tải lại khoản chi (⌘R)") {
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
        VStack(alignment: .leading, spacing: 16) {
            // Hàng điều khiển: chuyển tháng bên trái, thao tác phụ bên phải.
            HStack(spacing: 8) {
                monthSwitcher
                Spacer()
                #if os(macOS)
                // macOS không có kéo-xuống-để-tải-lại như iOS nên cần nút riêng.
                reloadButton
                #endif
                if let url = spreadsheetURL {
                    googleSheetLink(url)
                }
            }

            // Màn rộng: top loại chi nằm bên phải số tổng; màn hẹp (iPhone) thì xuống dưới.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 24) {
                    totalBlock
                    Spacer(minLength: 0)
                    topCategoriesBlock
                }
                VStack(alignment: .leading, spacing: 14) {
                    totalBlock
                    topCategoriesBlock
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppStyle.cardPadding + 4)
        .background(
            LinearGradient(colors: cardGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(workspaceColor.opacity(0.25), lineWidth: 1)
        )
    }

    /// Dark mode pha sang màu còn lại (vàng ↔ tím chàm) như wallpaper Golden Gate — 1 màu mờ trên nền tối trông đục.
    private var cardGradientColors: [Color] {
        guard colorScheme == .dark else { return [workspaceColor.opacity(0.22), workspaceColor.opacity(0.05)] }
        let blend = workspaceType == .personal ? AppStyle.indigo : AppStyle.gold
        return [workspaceColor.opacity(0.30), blend.opacity(0.18)]
    }

    private var totalBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isCurrentMonth ? "Tổng chi tháng này" : "Tổng chi")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(viewModel.totalAmount.formattedVND)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            StatusPill(text: "\(viewModel.entries.count) khoản chi", color: workspaceColor)
        }
        .fixedSize()
    }

    @ViewBuilder
    private var topCategoriesBlock: some View {
        if !viewModel.topCategories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.topCategories, id: \.category) { item in
                    HStack(spacing: 8) {
                        IconBadge(systemName: item.category.icon, color: item.category.color, size: 20)
                        Text(item.category.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Text(item.total.formattedVND)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            }
            .frame(minWidth: 200, maxWidth: 260)
        }
    }

    private func googleSheetLink(_ url: URL) -> some View {
        Link(destination: url) {
            Label("Google Sheet", systemImage: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(.quaternary.opacity(0.5), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Mở Google Sheet")
    }

    private var missingSheetView: some View {
        VStack(spacing: 16) {
            monthSwitcher
                .padding(.top, 8)

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
                    .buttonStyle(.primary)
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
                ErrorLabel(message: message)
            }

            Spacer()
        }
        .padding()
    }
}

private struct MonthStepButton: View {
    let systemName: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.3)
    }
}

private struct DayHeaderView: View {
    let title: String
    let total: Decimal

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(total.formattedVND)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.top, 10)
        .listRowSeparator(.hidden)
    }
}

private struct ExpenseRowView: View {
    let entry: ExpenseEntry
    @State private var isHovering = false

    private var category: ExpenseCategory {
        ExpenseCategory.from(entry.category)
    }

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: category.icon, color: category.color, size: 32)

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
                Text(entry.category)
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
        // Rê chuột (macOS) làm nổi dòng — gợi ý bấm để sửa, chuột phải để xoá.
        .background(.quaternary.opacity(isHovering ? 0.35 : 0), in: RoundedRectangle(cornerRadius: 8).inset(by: -6))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
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
        ExpenseListView(spreadsheetId: "preview", spreadsheetURL: nil, workspaceType: .personal, workspaceTitle: "Cá nhân 1", userDisplayName: "Preview User", userEmail: "preview@example.com")
    }
}
