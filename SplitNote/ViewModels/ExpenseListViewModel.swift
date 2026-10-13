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
    /// Load gặp `.notFound` — hiện màn "tạo sheet" thay vì danh sách rỗng dễ hiểu nhầm là chưa chi gì.
    @Published private(set) var sheetMissing = false
    @Published private(set) var isCreatingSheet = false
    @Published var errorMessage: String?
    @Published private(set) var selectedMonth: Date

    let spreadsheetId: String
    let workspaceType: WorkspaceType
    /// Rỗng (và ẩn toàn bộ UI gia đình) với `.personal`.
    let familyMembers: FamilyMembersViewModel
    private let sheetsService: SheetsServiceProtocol
    /// Chỉ lần load đầu hiện spinner toàn màn; các lần sau cập nhật tại chỗ, không xoá trắng danh sách.
    private var hasLoadedOnce = false
    /// Tăng mỗi lần load để kết quả cũ (vd chuyển tháng nhanh) không ghi đè kết quả mới.
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
    
    /// Chỉ tháng hiện tại mới đề nghị tạo sheet; tháng cũ chỉ báo là không có dữ liệu.
    var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: AppClock.now, toGranularity: .month)
    }
    
    var totalAmount: Decimal {
        entries.reduce(0) { $0 + $1.amount }
    }

    struct DaySection: Identifiable {
        let id: String
        let title: String
        let total: Decimal
        let entries: [ExpenseEntry]
    }

    /// `entries` đã xếp mới nhất trước nên chỉ cần gom các khoản liền nhau cùng ngày.
    var daySections: [DaySection] {
        var sections: [DaySection] = []
        for entry in entries {
            guard let last = sections.last, last.id == entry.date else {
                sections.append(DaySection(id: entry.date, title: Self.dayTitle(for: entry.date), total: entry.amount, entries: [entry]))
                continue
            }
            sections[sections.count - 1] = DaySection(id: last.id, title: last.title, total: last.total + entry.amount, entries: last.entries + [entry])
        }
        return sections
    }

    private static let topCategoryCount = 3

    /// Top 3 loại chi nhiều nhất tháng — hiện trong thẻ tổng chi.
    var topCategories: [(category: ExpenseCategory, total: Decimal)] {
        let totals = Dictionary(grouping: entries) { ExpenseCategory.from($0.category) }
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        return totals.sorted { $0.value > $1.value }.prefix(Self.topCategoryCount).map { ($0.key, $0.value) }
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

        // 2. Đọc thành viên + email song song với khoản chi (đọc thẳng từ sheet, không cache).
        async let membersTask = fetchMembersIfFamily()
        async let memberEmailsTask = fetchMemberEmailsIfFamily()
        // 3. Đọc khoản chi; không có tab thì chuyển sang trạng thái "cần tạo".
        let result: Result<[ExpenseEntry], Error>
        do {
            result = .success(try await sheetsService.fetchRows(spreadsheetId: spreadsheetId, tabTitle: tabTitle))
        } catch {
            result = .failure(error)
        }
        guard generation == loadGeneration else { return }
        switch result {
        case .success(let rows):
            entries = Self.newestFirst(rows)
            sheetMissing = false
        case .failure(SheetsServiceError.notFound):
            entries = []
            sheetMissing = true
        case .failure(let error):
            errorMessage = error.localizedDescription
            return
        }
        // 4. Cập nhật danh sách thành viên.
        let (names, emails) = await (membersTask, memberEmailsTask)
        familyMembers.setMembers(names, emails: emails)
    }

    /// Lỗi đọc thành viên không chặn danh sách khoản chi — coi như rỗng.
    private func fetchMembersIfFamily() async -> [String] {
        guard isFamily else { return [] }
        return (try? await sheetsService.fetchMembers(spreadsheetId: spreadsheetId)) ?? []
    }

    private func fetchMemberEmailsIfFamily() async -> [String] {
        guard isFamily else { return [] }
        return (try? await sheetsService.fetchMemberEmails(spreadsheetId: spreadsheetId)) ?? []
    }
    
    /// Tạo (hoặc tạo lại) tab tháng hiện tại rồi load lại danh sách.
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

    /// "Hôm nay" / "Hôm qua" / "Thứ Năm, 1 thg 10"; ô ngày không đọc được thì giữ nguyên chữ gốc.
    private static func dayTitle(for isoDate: String) -> String {
        guard let date = DateFormatter.isoDay.date(from: isoDate) else { return isoDate }
        let calendar = Calendar.current
        let today = AppClock.now
        if calendar.isDate(date, inSameDayAs: today) { return "Hôm nay" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), calendar.isDate(date, inSameDayAs: yesterday) { return "Hôm qua" }
        return DateFormatter.vietnameseDayTitle.string(from: date)
    }


    /// Ngày ISO `yyyy-MM-dd` so chuỗi là đúng thứ tự; cùng ngày thì khoản nhập sau lên trước.
    private static func newestFirst(_ rows: [ExpenseEntry]) -> [ExpenseEntry] {
        rows.sorted { ($0.date, $0.rowIndex) > ($1.date, $1.rowIndex) }
    }
}
