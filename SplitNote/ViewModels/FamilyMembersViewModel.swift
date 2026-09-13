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
    private let driveService: DriveServiceProtocol
    /// Kept in sync by `ExpenseListViewModel` whenever the selected month
    /// changes, so a persist always targets the tab currently on screen.
    var currentTabTitle: String

    init(spreadsheetId: String, tabTitle: String, sheetsService: SheetsServiceProtocol, driveService: DriveServiceProtocol = DriveService()) {
        self.spreadsheetId = spreadsheetId
        self.currentTabTitle = tabTitle
        self.sheetsService = sheetsService
        self.driveService = driveService
    }

    /// Syncs with the list last read alongside the expense entries themselves.
    func setMembers(_ members: [String]) {
        self.members = members
    }

    /// A plain name only affects "Ai chi"/"Chi cho ai" — an email also grants
    /// that Google account edit access to the spreadsheet itself, so signing
    /// into the app with it finds this workspace automatically.
    func addMember(_ rawInput: String) async {
        let name = rawInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !members.contains(name) else { return }
        members.append(name)

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await saveMemberList()
            if Self.isEmail(name) {
                try await driveService.shareFile(fileId: spreadsheetId, email: name, role: "writer")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Xoá khỏi danh sách hiển thị; nếu tên đó là email đã được cấp quyền
    /// Drive (qua `addMember`) thì thu hồi luôn — không thì người bị xoá vẫn
    /// mở/sửa được sheet dù không còn hiện trong "Ai chi"/"Chi cho ai".
    func removeMember(_ name: String) async {
        members.removeAll { $0 == name }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await saveMemberList()
            if Self.isEmail(name) {
                try await driveService.revokeAccess(fileId: spreadsheetId, email: name)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveMemberList() async throws {
        // 1. Ghi danh sách mới vào "Tổng hợp" — nguồn thật, mọi thiết bị
        // mở cùng spreadsheet đều đọc từ đây.
        try await sheetsService.setMembers(spreadsheetId: spreadsheetId, members: members)
        // 2. Ghi lại khối gia đình của tab đang xem ngay, khỏi phải chờ
        // lần `ensureTab` kế tiếp mới thấy cập nhật.
        try await sheetsService.ensureTab(spreadsheetId: spreadsheetId, tabTitle: currentTabTitle)
    }

    private static func isEmail(_ text: String) -> Bool {
        text.contains("@") && text.contains(".")
    }
}
