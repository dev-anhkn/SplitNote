//
//  FamilyMembersViewModel.swift
//  SplitNote
//

import Combine
import Foundation

/// Quản lý danh sách thành viên gia đình, đọc/ghi thẳng vào sheet để mọi thiết bị thấy giống nhau.
@MainActor
final class FamilyMembersViewModel: ObservableObject {
    @Published private(set) var memberEntries: [FamilyMember] = []
    /// Đang lưu thì chặn thao tác mới — tránh 2 lần lưu chồng nhau ghi đè trạng thái của nhau.
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    /// Tên dùng cho "Ai chi"/"Chi cho ai" và bảng cân đối.
    var members: [String] { memberEntries.map(\.name) }

    private let spreadsheetId: String
    private let sheetsService: SheetsServiceProtocol
    private let driveService: DriveServiceProtocol
    /// `ExpenseListViewModel` cập nhật khi đổi tháng để lưu luôn nhắm đúng tab đang xem.
    var currentTabTitle: String

    init(spreadsheetId: String, tabTitle: String, sheetsService: SheetsServiceProtocol, driveService: DriveServiceProtocol = DriveService()) {
        self.spreadsheetId = spreadsheetId
        self.currentTabTitle = tabTitle
        self.sheetsService = sheetsService
        self.driveService = driveService
    }

    /// Đồng bộ danh sách vừa đọc; giữ nguyên `id` theo tên để list trên UI không bị dựng lại mỗi lần tải.
    func setMembers(_ names: [String], emails: [String] = []) {
        // Sheet có thể bị sửa tay thành trùng tên — giữ id đầu tiên thay vì crash.
        let previousIds = Dictionary(memberEntries.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
        let paddedEmails = emails + Array(repeating: "", count: max(0, names.count - emails.count))
        memberEntries = zip(names, paddedEmails).map { name, email in
            FamilyMember(id: previousIds[name] ?? UUID(), name: name, email: email.isEmpty ? nil : email)
        }
    }

    /// Tên bắt buộc (không lấy email làm tên); email, nếu có, chỉ dùng để cấp quyền Drive. Trả về true nếu đã lưu.
    @discardableResult
    func addMember(name rawName: String, email rawEmail: String) async -> Bool {
        // 1. Kiểm tra tên/email hợp lệ.
        let name = rawName.trimmed
        let email = rawEmail.trimmed
        guard !isSaving, !name.isEmpty else { return false }
        guard !memberEntries.contains(where: { $0.name == name }) else {
            errorMessage = "\"\(name)\" đã có trong danh sách."
            return false
        }
        guard email.isEmpty || Self.isEmail(email) else {
            errorMessage = "Email không hợp lệ."
            return false
        }
        // 2. Thêm vào danh sách rồi lưu lên sheet.
        let normalizedEmail = email.isEmpty ? nil : email
        let saved = await applyAndSave { $0.append(FamilyMember(name: name, email: normalizedEmail)) }
        guard saved, let normalizedEmail else { return saved }
        // 3. Cấp quyền Drive — lỗi chỉ báo, danh sách đã lưu thì giữ nguyên.
        await reportError { try await driveService.shareFile(fileId: spreadsheetId, email: normalizedEmail, role: DriveService.writerRole) }
        return true
    }

    /// Chỉ đổi tên hiển thị — email/quyền Drive giữ nguyên, khoản chi cũ vẫn mang tên cũ.
    func renameMember(id: FamilyMember.ID, to rawNewName: String) async {
        let newName = rawNewName.trimmed
        guard !isSaving, !newName.isEmpty else { return }
        guard let index = memberEntries.firstIndex(where: { $0.id == id }), memberEntries[index].name != newName else { return }
        guard !memberEntries.contains(where: { $0.id != id && $0.name == newName }) else {
            errorMessage = "\"\(newName)\" đã có trong danh sách."
            return
        }
        await applyAndSave { $0[index].name = newName }
    }

    /// Xoá thành viên và thu hồi quyền Drive — không thì người bị xoá vẫn mở/sửa được sheet.
    func removeMember(_ name: String) async {
        guard !isSaving else { return }
        // 1. Bỏ khỏi danh sách rồi lưu lên sheet.
        let email = memberEntries.first { $0.name == name }?.email
        let saved = await applyAndSave { $0.removeAll { $0.name == name } }
        guard saved, let email else { return }
        // 2. Thu hồi quyền Drive.
        await reportError { try await driveService.revokeAccess(fileId: spreadsheetId, email: email) }
    }

    /// Đổi danh sách hiển thị ngay, lưu lên sheet; lỗi thì hoàn tác để UI không hiện dữ liệu chưa lưu.
    @discardableResult
    private func applyAndSave(_ change: (inout [FamilyMember]) -> Void) async -> Bool {
        // 1. Chụp lại trạng thái cũ rồi áp thay đổi.
        let previous = memberEntries
        change(&memberEntries)
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        // 2. Ghi tên + email vào "Tổng hợp" trong 1 request; lỗi thì trả lại trạng thái cũ.
        do {
            try await sheetsService.setMemberList(spreadsheetId: spreadsheetId, names: members, emails: memberEntries.map { $0.email ?? "" })
        } catch {
            memberEntries = previous
            errorMessage = error.localizedDescription
            return false
        }
        // 3. Làm mới khối gia đình của tab đang xem — lỗi chỉ báo vì danh sách đã lưu.
        await reportError { try await sheetsService.ensureTab(spreadsheetId: spreadsheetId, tabTitle: currentTabTitle) }
        return true
    }

    private func reportError(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func isEmail(_ text: String) -> Bool {
        text.contains("@") && text.contains(".")
    }
}
