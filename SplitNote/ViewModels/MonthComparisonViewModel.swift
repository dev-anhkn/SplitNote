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
            DateFormatter.shortMonth.string(from: month)
        }
    }
    
    @Published private(set) var monthlyTotals: [MonthTotal] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// Các khoảng so sánh cho người dùng chọn.
    static let rangeOptions = [3, 6, 9]

    @Published var rangeInMonths = rangeOptions[0] {
        didSet {
            guard rangeInMonths != oldValue else { return }
            // Dữ liệu mọi tháng đã có sẵn từ `load()` — chỉ cắt lại, không gọi API.
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

    /// Đọc tổng mọi tháng từ "Tổng hợp" — 1 lần gọi API dù xem 3, 6 hay 9 tháng.
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let rows = try await sheetsService.fetchMonthlyTotals(spreadsheetId: spreadsheetId)
            totalsByTabTitle = Dictionary(rows.map { ($0.tabTitle, $0.total) }, uniquingKeysWith: { first, _ in first })
        } catch SheetsServiceError.notFound {
            // Spreadsheet cũ chưa có "Tổng hợp" → coi như chưa có tháng nào.
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
