//
//  FamilyMembersViewModel.swift
//  SplitNote
//

import Combine
import Foundation

/// Owns the `.family` member list — read from (and written to) the
/// spreadsheet itself, not any per-device cache — so every family member
/// sees the same list regardless of device. Separate from
/// `ExpenseListViewModel` since adding/removing a member is its own concern
/// from loading/browsing that month's expenses.
@MainActor
final class FamilyMembersViewModel: ObservableObject {
    @Published private(set) var members: [String] = []
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let spreadsheetId: String
    private let sheetsService: SheetsServiceProtocol
    /// Kept in sync by `ExpenseListViewModel` whenever the selected month
    /// changes, so a persist always targets the tab currently on screen.
    var currentTabTitle: String

    init(spreadsheetId: String, tabTitle: String, sheetsService: SheetsServiceProtocol) {
        self.spreadsheetId = spreadsheetId
        self.currentTabTitle = tabTitle
        self.sheetsService = sheetsService
    }

    /// Syncs with the list last read alongside the expense entries themselves.
    func setMembers(_ members: [String]) {
        self.members = members
    }

    func addMember(_ rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !members.contains(name) else { return }
        members.append(name)
        await persist()
    }

    func removeMember(_ name: String) async {
        members.removeAll { $0 == name }
        await persist()
    }

    private func persist() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            // 1. Ghi danh sách mới vào "Tổng hợp" — nguồn thật, mọi thiết bị
            // mở cùng spreadsheet đều đọc từ đây.
            try await sheetsService.setMembers(spreadsheetId: spreadsheetId, members: members)
            // 2. Ghi lại khối gia đình của tab đang xem ngay, khỏi phải chờ
            // lần `ensureTab` kế tiếp mới thấy cập nhật.
            try await sheetsService.ensureTab(spreadsheetId: spreadsheetId, tabTitle: currentTabTitle)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
