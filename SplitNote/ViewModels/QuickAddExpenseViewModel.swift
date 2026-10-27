//
//  QuickAddExpenseViewModel.swift
//  SplitNote
//

import Combine
import Foundation

@MainActor
final class QuickAddExpenseViewModel: ObservableObject {
    @Published var amountText = "" {
        didSet {
            didSave = false
            // Chỉ nhóm lại "." khi gõ/xoá ở cuối — sửa giữa chuỗi mà format lại sẽ nhảy con trỏ.
            guard Self.isEditAtEnd(from: oldValue, to: amountText) else { return }
            let formatted = Self.groupedAmountText(fromDigits: amountText.filter(\.isNumber))
            guard formatted != amountText else { return }
            // Gán sau 1 nhịp runloop — gán ngay trong didSet thì SwiftUI không hiển thị kịp.
            DispatchQueue.main.async { [weak self] in
                self?.amountText = formatted
            }
        }
    }
    @Published var content = "" { didSet { didSave = false } }
    @Published var category: ExpenseCategory = .other { didSet { didSave = false } }
    @Published var date: Date { didSet { didSave = false } }
    /// Người chi (chỉ dùng khi `isFamily`), mặc định là người đang đăng nhập.
    @Published var paidBy: String = "" { didSet { didSave = false } }
    /// Người được chia, mặc định tất cả — không bao giờ rỗng vì chia đều cần mẫu số.
    @Published var selectedSharers: Set<String> = [] {
        didSet {
            didSave = false
            // Thiếu `!members.isEmpty` thì gán Set rỗng lại gọi didSet → đệ quy vô hạn.
            guard selectedSharers.isEmpty, !members.isEmpty else { return }
            selectedSharers = Set(members)
        }
    }
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?
    /// Bật sau khi lưu thành công để màn gọi biết đóng form và tải lại danh sách.
    @Published private(set) var didSave = false
    /// Số khoản đã lưu trong lần mở form này — form thêm mới giữ mở để nhập liên tiếp.
    @Published private(set) var savedCount = 0
    /// "Ăn trưa · 48.000 đ" của khoản vừa lưu, hiện làm xác nhận khi form vẫn mở.
    @Published private(set) var lastSavedSummary: String?
    
    let tabTitle: String
    /// Chỉ cho chọn ngày trong tháng của tab — hàng luôn ghi vào tab đang mở.
    let dateRange: ClosedRange<Date>
    /// Thành viên workspace — rỗng với `.personal` (ẩn luôn mục chia tiền).
    let memberEntries: [FamilyMember]
    private let spreadsheetId: String
    private let sheetsService: SheetsServiceProtocol
    /// Khác nil khi đang sửa 1 hàng có sẵn thay vì thêm mới.
    private let editingRowIndex: Int?
    /// Loại gốc trên sheet không khớp enum — giữ lại để sửa mà không chạm Loại thì không bị ghi thành "Khác".
    private let unmappedOriginalCategory: String?
    /// Sửa mà không đổi ngày thì giữ nguyên ô Ngày — tránh ghi đè ô có định dạng app không đọc được.
    private let initialDate: Date

    /// Tên hiển thị cho picker "Ai chi" và `MemberShareField`.
    var members: [String] { memberEntries.map(\.name) }
    var isEditing: Bool { editingRowIndex != nil }
    var isFamily: Bool { !memberEntries.isEmpty }

    /// Form thêm mới; `entry` khác nil thì điền sẵn để sửa đúng hàng đó.
    init(spreadsheetId: String, tabTitle: String, editing entry: ExpenseEntry? = nil, memberEntries: [FamilyMember] = [], currentUserName: String = "", currentUserEmail: String = "", sheetsService: SheetsServiceProtocol = SheetsService()) {
        // 1. Phụ thuộc + ngữ cảnh workspace.
        self.spreadsheetId = spreadsheetId
        self.tabTitle = tabTitle
        self.memberEntries = memberEntries
        self.sheetsService = sheetsService
        self.editingRowIndex = entry?.rowIndex
        // 2. Ngày: lấy theo hàng đang sửa (hoặc hôm nay), kẹp trong tháng của tab.
        let dateRange = Self.dateRange(forTabTitle: tabTitle)
        let sourceDate = entry.flatMap { DateFormatter.isoDay.date(from: $0.date) } ?? AppClock.now
        let initialDate = Self.clamped(sourceDate, to: dateRange)
        self.dateRange = dateRange
        self.date = initialDate
        self.initialDate = initialDate
        // 3. Nội dung, Loại, số tiền (format ngay, không qua `didSet` để khỏi nhấp nháy).
        self.content = entry?.content ?? ""
        let mappedCategory = entry.flatMap { ExpenseCategory(rawValue: $0.category) }
        self.category = mappedCategory ?? .other
        self.unmappedOriginalCategory = mappedCategory == nil ? entry?.category : nil
        let digits = entry.map { NSDecimalNumber(decimal: $0.amount).stringValue.filter(\.isNumber) } ?? ""
        self.amountText = Self.groupedAmountText(fromDigits: digits)
        // 4. Người chi + người được chia.
        let savedPaidBy = entry?.paidBy ?? ""
        self.paidBy = savedPaidBy.isEmpty ? Self.defaultPaidBy(memberEntries: memberEntries, currentUserName: currentUserName, currentUserEmail: currentUserEmail) : savedPaidBy
        self.selectedSharers = Self.initialSharers(sharedWith: entry?.sharedWith ?? "", memberEntries: memberEntries)
    }

    /// Ưu tiên khớp email tài khoản đang đăng nhập; không khớp mới so tên (tương thích workspace cũ).
    private static func defaultPaidBy(memberEntries: [FamilyMember], currentUserName: String, currentUserEmail: String) -> String {
        let matchedByEmail = memberEntries.first { !currentUserEmail.isEmpty && $0.email?.caseInsensitiveCompare(currentUserEmail) == .orderedSame }
        if let matchedByEmail {
            return matchedByEmail.name
        }
        let names = memberEntries.map(\.name)
        return names.contains(currentUserName) ? currentUserName : (names.first ?? "")
    }

    /// Hàng mới hoặc hàng cũ chưa có dữ liệu chia thì mặc định chia cho tất cả.
    private static func initialSharers(sharedWith: String, memberEntries: [FamilyMember]) -> Set<String> {
        let sharedNames = sharedWith
            .split(separator: ",")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
        return sharedNames.isEmpty ? Set(memberEntries.map(\.name)) : Set(sharedNames)
    }

    var canSubmit: Bool {
        !isSubmitting
            && parsedAmount != nil
            && !content.trimmed.isEmpty
            && (!isFamily || !paidBy.trimmed.isEmpty)
    }

    /// Nói rõ còn thiếu gì khi nút Lưu đang mờ; nil khi đã đủ.
    var missingFieldsHint: String? {
        let missingAmount = parsedAmount == nil
        let missingContent = content.trimmed.isEmpty
        if missingAmount && missingContent { return "Nhập số tiền và nội dung để lưu" }
        if missingAmount { return "Nhập số tiền để lưu" }
        if missingContent { return "Nhập nội dung để lưu" }
        if isFamily && paidBy.trimmed.isEmpty { return "Chọn người chi để lưu" }
        return nil
    }

    var isToday: Bool { Calendar.current.isDate(date, inSameDayAs: AppClock.now) }
    var isYesterday: Bool { Calendar.current.isDate(date, inSameDayAs: Self.yesterday) }
    /// Tab tháng cũ/mới không chứa hôm qua thì ẩn nút "Hôm qua".
    var canPickYesterday: Bool { dateRange.contains(Self.yesterday) }
    var canPickToday: Bool { dateRange.contains(AppClock.now) }

    func pickToday() {
        date = AppClock.now
    }

    func pickYesterday() {
        date = Self.yesterday
    }

    /// Lùi/tiến `days` ngày, không vượt ra ngoài tháng của tab.
    func shiftDate(byDays days: Int) {
        guard let shifted = Calendar.current.date(byAdding: .day, value: days, to: date) else { return }
        date = Self.clamped(shifted, to: dateRange)
    }

    private static var yesterday: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: AppClock.now) ?? AppClock.now
    }

    /// Nối theo thứ tự `members` (không theo `Set`) để cột "Chi cho ai" đồng nhất giữa các hàng.
    private var sharedWithToSave: String {
        members.filter(selectedSharers.contains).joined(separator: ",")
    }
    
    /// VNĐ không có phần lẻ — "." "," là phân cách hàng nghìn nên chỉ giữ chữ số.
    private var parsedAmount: Decimal? {
        let digitsOnly = amountText.filter(\.isNumber)
        guard !digitsOnly.isEmpty, let value = Decimal(string: digitsOnly), value > 0 else { return nil }
        return value
    }

    /// Giữ chữ Loại gốc nếu nó không khớp enum và người dùng chưa chọn loại khác.
    private var categoryToSave: String {
        if category == .other, let unmappedOriginalCategory {
            return unmappedOriginalCategory
        }
        return category.rawValue
    }
    
    func submitEntry() async {
        // Return bấm nhanh 2 lần tạo 2 Task trước khi kịp bật `isSubmitting` — chặn lần thứ 2 tại đây.
        guard !isSubmitting, let amount = parsedAmount else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            // Đang sửa thì ghi đè đúng hàng, thêm mới thì ghi hàng mới.
            if let rowIndex = editingRowIndex {
                try await updateExistingRow(rowIndex, amount: amount)
            } else {
                try await appendNewRow(amount: amount)
            }
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateExistingRow(_ rowIndex: Int, amount: Decimal) async throws {
        // Không đổi ngày thì gửi nil để giữ nguyên ô Ngày gốc.
        let dateToSave = Calendar.current.isDate(date, inSameDayAs: initialDate) ? nil : DateFormatter.isoDay.string(from: date)
        try await sheetsService.updateRow(
            spreadsheetId: spreadsheetId,
            tabTitle: tabTitle,
            rowIndex: rowIndex,
            date: dateToSave,
            category: categoryToSave,
            content: content.trimmed,
            amount: NSDecimalNumber(decimal: amount).stringValue,
            paidBy: isFamily ? paidBy : nil,
            sharedWith: isFamily ? sharedWithToSave : nil
        )
    }

    private func appendNewRow(amount: Decimal) async throws {
        // 1. Ghi hàng mới.
        try await sheetsService.appendRow(
            spreadsheetId: spreadsheetId,
            tabTitle: tabTitle,
            date: DateFormatter.isoDay.string(from: date),
            category: category.rawValue,
            content: content.trimmed,
            amount: NSDecimalNumber(decimal: amount).stringValue,
            paidBy: isFamily ? paidBy : nil,
            sharedWith: isFamily ? sharedWithToSave : nil
        )
        // 2. Hiện xác nhận ngay trên form.
        lastSavedSummary = "\(content.trimmed) · \(amount.formattedVND)"
        savedCount += 1
        // 3. Xoá số tiền/nội dung để nhập tiếp, giữ Loại và Ngày.
        amountText = ""
        content = ""
    }
    
    /// "1500000" -> "1.500.000".
    private static func groupedAmountText(fromDigits digits: String) -> String {
        guard !digits.isEmpty, let value = Decimal(string: digits) else { return "" }
        return NumberFormatter.vndGrouping.string(from: NSDecimalNumber(decimal: value)) ?? digits
    }

    /// Đúng khi chỉ gõ thêm/xoá ở cuối dãy số, không phải sửa ở giữa.
    private static func isEditAtEnd(from oldValue: String, to newValue: String) -> Bool {
        let oldDigits = oldValue.filter(\.isNumber)
        let newDigits = newValue.filter(\.isNumber)
        return newDigits.hasPrefix(oldDigits) || oldDigits.hasPrefix(newDigits)
    }
    
    /// Tiêu đề tab sai dạng thì không giới hạn, thay vì chặn hẳn việc nhập.
    private static func dateRange(forTabTitle tabTitle: String) -> ClosedRange<Date> {
        guard let interval = MonthTabTitle.dateInterval(for: tabTitle) else { return Date.distantPast...Date.distantFuture }
        return interval.start...interval.end.addingTimeInterval(-1)
    }

    /// Xem tab tháng cũ thì mặc định ngày cuối tháng đó, không phải hôm nay.
    private static func clamped(_ date: Date, to range: ClosedRange<Date>) -> Date {
        min(max(date, range.lowerBound), range.upperBound)
    }
}
