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

    /// Đọc trực tiếp hàng của tháng này trong tab "Tổng hợp" — không cần
    /// tải toàn bộ khoản chi rồi tự group/sum nữa.
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
