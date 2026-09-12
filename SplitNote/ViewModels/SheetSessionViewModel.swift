//
//  SheetSessionViewModel.swift
//  SplitNote
//

import Combine
import Foundation

@MainActor
final class SheetSessionViewModel: ObservableObject {
    @Published var amountText = ""
    @Published var content = ""
    @Published var category = ""
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?

    let tabTitle: String
    private let spreadsheetId: String
    private let sheetsService: SheetsServiceProtocol

    init(spreadsheetId: String, tabTitle: String, sheetsService: SheetsServiceProtocol = SheetsService()) {
        self.spreadsheetId = spreadsheetId
        self.tabTitle = tabTitle
        self.sheetsService = sheetsService
    }

    var canSubmit: Bool {
        !isSubmitting && parsedAmount != nil && !content.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var parsedAmount: Decimal? {
        let normalized = amountText.replacingOccurrences(of: ",", with: "")
        guard let value = Decimal(string: normalized), value > 0 else { return nil }
        return value
    }

    func submitEntry() async {
        guard let amount = parsedAmount else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await sheetsService.appendRow(
                spreadsheetId: spreadsheetId,
                tabTitle: tabTitle,
                date: Self.isoDateFormatter.string(from: Date()),
                content: content.trimmingCharacters(in: .whitespaces),
                category: category.trimmingCharacters(in: .whitespaces),
                amount: NSDecimalNumber(decimal: amount).stringValue
            )
            amountText = ""
            content = ""
            category = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// ISO format so Sheets parses it as a real date regardless of the
    /// spreadsheet's locale (unlike "dd/MM/yyyy" vs "MM/dd/yyyy", which is ambiguous).
    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()
}
