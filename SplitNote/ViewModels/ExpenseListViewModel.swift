//
//  ExpenseListViewModel.swift
//  SplitNote
//

import Combine
import Foundation

@MainActor
final class ExpenseListViewModel: ObservableObject {
    @Published private(set) var entries: [ExpenseEntry] = []
    @Published private(set) var isLoading = true
    /// True once a load fails with `.notFound` — the tab (or the whole
    /// spreadsheet) isn't there, so the list gives way to a "create it" state
    /// instead of showing an empty list that looks like "no expenses yet".
    @Published private(set) var sheetMissing = false
    @Published private(set) var isCreatingSheet = false
    @Published var errorMessage: String?
    @Published var isShowingQuickAdd = false
    @Published private(set) var selectedMonth: Date
    @Published var isShowingMembers = false

    let spreadsheetId: String
    let workspaceType: WorkspaceType
    /// Empty (and the whole family UI hidden) for `.personal`.
    let familyMembers: FamilyMembersViewModel
    private let sheetsService: SheetsServiceProtocol
    /// Guards `isLoading` so only the very first load shows the full-screen
    /// spinner — a pull-to-refresh, a reload after quick-add, or switching to
    /// another month should update the list in place instead of blanking it
    /// out from under the user.
    private var hasLoadedOnce = false
    /// Bumped on every `loadEntries()` call so a stale, still-in-flight load
    /// (e.g. from rapid month switching) can't overwrite a newer one's result.
    private var loadGeneration = 0
    
    init(
        spreadsheetId: String,
        workspaceType: WorkspaceType,
        initialMonth: Date = AppClock.now,
        sheetsService: SheetsServiceProtocol = SheetsService()
    ) {
        self.spreadsheetId = spreadsheetId
        self.workspaceType = workspaceType
        self.selectedMonth = initialMonth
        self.sheetsService = sheetsService
        self.familyMembers = FamilyMembersViewModel(spreadsheetId: spreadsheetId, tabTitle: MonthTabTitle.title(for: initialMonth), sheetsService: sheetsService)
    }

    var tabTitle: String { MonthTabTitle.title(for: selectedMonth) }
    var isFamily: Bool { workspaceType == .family }
    
    /// The "create this month's sheet" flow only makes sense for the current
    /// month — an old month that never had entries should just say so
    /// instead of offering to create a tab for a month that's already over.
    var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: AppClock.now, toGranularity: .month)
    }
    
    var totalAmount: Decimal {
        entries.reduce(0) { $0 + $1.amount }
    }

    func goToPreviousMonth() {
        shiftSelectedMonth(by: -1)
    }
    
    func goToNextMonth() {
        // Không cho xem "tháng sau" tính từ hôm nay — chưa có gì để xem.
        guard !isCurrentMonth else { return }
        shiftSelectedMonth(by: 1)
    }
    
    private func shiftSelectedMonth(by value: Int) {
        guard let newMonth = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) else { return }
        selectedMonth = newMonth
        familyMembers.currentTabTitle = tabTitle
        Task { await loadEntries() }
    }
    
    func loadEntries() async {
        loadGeneration += 1
        let generation = loadGeneration

        // 1. Chỉ hiện spinner toàn màn ở lần load đầu tiên.
        if !hasLoadedOnce {
            isLoading = true
        }
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        // 2. Đọc các khoản chi + (nếu là gia đình) danh sách thành viên từ
        // sheet song song — thành viên đọc thẳng từ "Tổng hợp", không cache
        // cục bộ, nên đổi trên thiết bị nào cũng thấy ngay ở đây.
        async let membersTask: [String] = isFamily ? ((try? await sheetsService.fetchMembers(spreadsheetId: spreadsheetId)) ?? []) : []
        do {
            let rows = try await sheetsService.fetchRows(spreadsheetId: spreadsheetId, tabTitle: tabTitle)
            guard generation == loadGeneration else { return }
            entries = rows
            sheetMissing = false
            familyMembers.setMembers(await membersTask)
        } catch SheetsServiceError.notFound {
            guard generation == loadGeneration else { return }
            // 3. Không tìm thấy tab/sheet thì chuyển sang trạng thái "cần tạo".
            entries = []
            sheetMissing = true
            familyMembers.setMembers(await membersTask)
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }
    
    /// Tạo (hoặc tạo lại) tab tháng hiện tại, rồi load lại danh sách (chắc
    /// chắn rỗng vì vừa tạo).
    func createMissingSheet() async {
        isCreatingSheet = true
        errorMessage = nil
        defer { isCreatingSheet = false }
        
        do {
            // 1. Tạo tab còn thiếu.
            try await sheetsService.ensureTab(spreadsheetId: spreadsheetId, tabTitle: tabTitle)
            // 2. Load lại danh sách.
            await loadEntries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Xoá 1 khoản chi rồi load lại danh sách để tổng/UI cập nhật theo.
    func deleteEntry(_ entry: ExpenseEntry) async {
        errorMessage = nil
        do {
            try await sheetsService.deleteRow(spreadsheetId: spreadsheetId, tabTitle: tabTitle, rowIndex: entry.rowIndex)
            await loadEntries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
