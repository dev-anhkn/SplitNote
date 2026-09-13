//
//  MonthComparisonViewModel.swift
//  SplitNote
//

import Combine
import Foundation

@MainActor
final class MonthComparisonViewModel: ObservableObject {
    struct MonthTotal: Identifiable {
        let month: Date
        let total: Decimal
        var id: Date { month }
        
        var label: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM/yy"
            return formatter.string(from: month)
        }
    }
    
    static let rangeOptions = [3, 6, 9]
    
    @Published private(set) var monthlyTotals: [MonthTotal] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var rangeInMonths = 3 {
        didSet {
            guard rangeInMonths != oldValue else { return }
            // Dữ liệu của mọi tháng đã có sẵn trong `totalsByTabTitle` từ lần
            // `load()` đầu — đổi range chỉ cần cắt lại danh sách, không cần
            // gọi lại API.
            recomputeMonthlyTotals()
        }
    }

    private let spreadsheetId: String
    private let sheetsService: SheetsServiceProtocol
    private var totalsByTabTitle: [String: Decimal] = [:]

    init(spreadsheetId: String, sheetsService: SheetsServiceProtocol = SheetsService()) {
        self.spreadsheetId = spreadsheetId
        self.sheetsService = sheetsService
    }

    /// Đọc toàn bộ tổng theo tháng từ tab "Tổng hợp" — 1 lần gọi API duy
    /// nhất dù đang xem 3, 6 hay 9 tháng.
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let rows = try await sheetsService.fetchMonthlyTotals(spreadsheetId: spreadsheetId)
            totalsByTabTitle = Dictionary(rows.map { ($0.tabTitle, $0.total) }, uniquingKeysWith: { first, _ in first })
        } catch SheetsServiceError.notFound {
            // Chưa có tab "Tổng hợp" (spreadsheet cũ chưa mở lại lần nào từ
            // khi có tính năng này) → coi như chưa có tháng nào.
            totalsByTabTitle = [:]
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        recomputeMonthlyTotals()
    }

    private func recomputeMonthlyTotals() {
        let calendar = Calendar.current
        let now = AppClock.now
        let months = (0..<rangeInMonths).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: now)
        }
        monthlyTotals = months.map { month in
            MonthTotal(month: month, total: totalsByTabTitle[MonthTabTitle.title(for: month)] ?? 0)
        }
    }
}
