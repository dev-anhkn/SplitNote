//
//  CategoryBreakdownViewModel.swift
//  SplitNote
//

import Combine
import Foundation

@MainActor
final class CategoryBreakdownViewModel: ObservableObject {
    @Published private(set) var totals: [(category: String, total: Decimal)] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let tabTitle: String
    private let spreadsheetId: String
    private let sheetsService: SheetsServiceProtocol

    init(spreadsheetId: String, tabTitle: String, sheetsService: SheetsServiceProtocol = SheetsService()) {
        self.spreadsheetId = spreadsheetId
        self.tabTitle = tabTitle
        self.sheetsService = sheetsService
    }

    /// Đọc thẳng hàng của tháng trong "Tổng hợp" thay vì tải hết khoản chi rồi tự cộng.
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            totals = try await sheetsService.fetchCategoryTotals(spreadsheetId: spreadsheetId, tabTitle: tabTitle)
        } catch SheetsServiceError.notFound {
            totals = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
