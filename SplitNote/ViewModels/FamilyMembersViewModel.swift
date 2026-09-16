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
    @Published private(set) var memberEntries: [FamilyMember] = []
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    /// What "Ai chi"/"Chi cho ai" and the balance table actually use —
    /// unaffected by which entries carry an email.
    var members: [String] { memberEntries.map(\.name) }

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

    /// Syncs with the list (names + linked emails) last read alongside the
    /// expense entries themselves — `emails` is row-aligned with `names`,
    /// padded with "" if shorter (e.g. an older spreadsheet with no email
    /// column written yet). Keeps each entry's `id` stable across reloads
    /// when its name is unchanged, so `FamilyMembersView`'s list doesn't
    /// visually reset every refresh.
    func setMembers(_ names: [String], emails: [String] = []) {
        let previousIds = Dictionary(uniqueKeysWithValues: memberEntries.map { ($0.name, $0.id) })
        let paddedEmails = emails + Array(repeating: "", count: max(0, names.count - emails.count))
        memberEntries = zip(names, paddedEmails).map { name, email in
            FamilyMember(id: previousIds[name] ?? UUID(), name: name, email: email.isEmpty ? nil : email)
        }
    }

    /// `name` là bắt buộc — luôn dùng trong "Ai chi"/"Chi cho ai" ngay từ
    /// khoản chi đầu tiên, không bao giờ tự lấy email làm tên nữa (tránh phải
    /// đổi tên sau này khi đã có dữ liệu gắn theo email). `email`, nếu có,
    /// chỉ dùng để cấp quyền edit Drive cho đúng account đó.
    func addMember(name rawName: String, email rawEmail: String) async {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        let email = rawEmail.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !memberEntries.contains(where: { $0.name == name }) else { return }
        guard email.isEmpty || Self.isEmail(email) else {
            errorMessage = "Email không hợp lệ."
            return
        }
        let normalizedEmail = email.isEmpty ? nil : email
        memberEntries.append(FamilyMember(name: name, email: normalizedEmail))

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await saveMemberList()
            if let normalizedEmail {
                try await driveService.shareFile(fileId: spreadsheetId, email: normalizedEmail, role: "writer")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Đổi tên hiển thị dùng trong "Ai chi"/"Chi cho ai" — email (và quyền
    /// Drive gắn theo nó, nếu có) giữ nguyên, không share/revoke lại. Các
    /// khoản chi đã ghi trước đó vẫn giữ tên cũ vì không bị ghi đè lại.
    func renameMember(id: FamilyMember.ID, to rawNewName: String) async {
        let newName = rawNewName.trimmingCharacters(in: .whitespaces)
        guard let index = memberEntries.firstIndex(where: { $0.id == id }) else { return }
        guard !newName.isEmpty, !memberEntries.contains(where: { $0.id != id && $0.name == newName }) else { return }
        guard memberEntries[index].name != newName else { return }
        memberEntries[index].name = newName

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await saveMemberList()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Xoá khỏi danh sách hiển thị; nếu thành viên đó có email đã được cấp
    /// quyền Drive (qua `addMember`) thì thu hồi luôn — không thì người bị
    /// xoá vẫn mở/sửa được sheet dù không còn hiện trong "Ai chi"/"Chi cho ai".
    func removeMember(_ name: String) async {
        let email = memberEntries.first { $0.name == name }?.email
        memberEntries.removeAll { $0.name == name }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await saveMemberList()
            if let email {
                try await driveService.revokeAccess(fileId: spreadsheetId, email: email)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveMemberList() async throws {
        // 1. Ghi danh sách tên + email mới vào "Tổng hợp" — nguồn thật, mọi
        // thiết bị mở cùng spreadsheet đều đọc từ đây.
        try await sheetsService.setMembers(spreadsheetId: spreadsheetId, members: members)
        try await sheetsService.setMemberEmails(spreadsheetId: spreadsheetId, emails: memberEntries.map { $0.email ?? "" })
        // 2. Ghi lại khối gia đình của tab đang xem ngay, khỏi phải chờ
        // lần `ensureTab` kế tiếp mới thấy cập nhật.
        try await sheetsService.ensureTab(spreadsheetId: spreadsheetId, tabTitle: currentTabTitle)
    }

    private static func isEmail(_ text: String) -> Bool {
        text.contains("@") && text.contains(".")
    }
}
