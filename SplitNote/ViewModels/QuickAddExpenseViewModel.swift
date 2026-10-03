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
            // Chỉ tự nhóm lại dấu "." khi gõ thêm/xoá ở cuối (cách gõ số tiền
            // thông thường) — sửa ở giữa chuỗi thì bỏ qua, tránh nhảy con trỏ
            // về cuối field mỗi lần bấm phím.
            guard Self.isEditAtEnd(from: oldValue, to: amountText) else { return }
            let formatted = Self.groupedAmountText(fromDigits: amountText.filter(\.isNumber))
            guard formatted != amountText else { return }
            // Gán lại sau 1 nhịp runloop — SwiftUI ưu tiên giữ nguyên chữ vừa gõ
            // nên gán ngay trong didSet của chính field này không hiển thị kịp.
            DispatchQueue.main.async { [weak self] in
                self?.amountText = formatted
            }
        }
    }
    @Published var content = "" { didSet { didSave = false } }
    @Published var category: ExpenseCategory = .other { didSet { didSave = false } }
    /// Who paid — only meaningful when `isFamily`. Defaults to the current
    /// user but stays editable for entering someone else's expense.
    @Published var paidBy: String = "" { didSet { didSave = false } }
    /// Who this expense splits across. Defaults to every member ("Tất cả"
    /// in the UI) — never left empty, since an empty set has no meaningful
    /// "chia đều" denominator.
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
    /// Flipped after a successful `submitEntry()` so the presenting sheet
    /// knows to dismiss and refresh its list.
    @Published private(set) var didSave = false
    
    let tabTitle: String
    /// Every member of this workspace — empty for `.personal`, which hides
    /// the "Ai chi"/"Chi cho ai" fields entirely.
    let memberEntries: [FamilyMember]
    private let spreadsheetId: String
    private let sheetsService: SheetsServiceProtocol
    /// Non-nil when editing an existing row (updates it in place) instead of
    /// appending a new one.
    private let editingRowIndex: Int?
    /// The sheet's original category text when it doesn't match any
    /// `ExpenseCategory` case — kept so an edit that never touches the
    /// category field doesn't silently overwrite it with "Khác" on save.
    private let unmappedOriginalCategory: String?

    /// Display names — what the "Ai chi" picker and `MemberShareField` show.
    var members: [String] { memberEntries.map(\.name) }
    var isFamily: Bool { !memberEntries.isEmpty }

    init(spreadsheetId: String, tabTitle: String, memberEntries: [FamilyMember] = [], currentUserName: String = "", currentUserEmail: String = "", sheetsService: SheetsServiceProtocol = SheetsService()) {
        self.spreadsheetId = spreadsheetId
        self.tabTitle = tabTitle
        self.memberEntries = memberEntries
        self.sheetsService = sheetsService
        self.editingRowIndex = nil
        self.unmappedOriginalCategory = nil
        self.paidBy = Self.defaultPaidBy(memberEntries: memberEntries, currentUserName: currentUserName, currentUserEmail: currentUserEmail)
        self.selectedSharers = Set(memberEntries.map(\.name))
    }

    /// Pre-fills the form from an existing row; `submitEntry()` then updates
    /// that row in place rather than appending a new one.
    init(spreadsheetId: String, tabTitle: String, editing entry: ExpenseEntry, memberEntries: [FamilyMember] = [], currentUserName: String = "", currentUserEmail: String = "", sheetsService: SheetsServiceProtocol = SheetsService()) {
        self.spreadsheetId = spreadsheetId
        self.tabTitle = tabTitle
        self.memberEntries = memberEntries
        self.sheetsService = sheetsService
        self.editingRowIndex = entry.rowIndex
        self.content = entry.content
        let mappedCategory = ExpenseCategory(rawValue: entry.category)
        self.category = mappedCategory ?? .other
        self.unmappedOriginalCategory = mappedCategory == nil ? entry.category : nil
        // Format số tiền ngay từ đầu, không qua `didSet` (tránh nhấp nháy khi mở màn).
        let digits = NSDecimalNumber(decimal: entry.amount).stringValue.filter(\.isNumber)
        self.amountText = Self.groupedAmountText(fromDigits: digits)
        self.paidBy = entry.paidBy.isEmpty ? Self.defaultPaidBy(memberEntries: memberEntries, currentUserName: currentUserName, currentUserEmail: currentUserEmail) : entry.paidBy
        let sharedNames = entry.sharedWith
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // Hàng cũ chưa từng có dữ liệu gia đình (trước khi có tính năng này)
        // thì coi như chia cho tất cả, thay vì để trống.
        self.selectedSharers = sharedNames.isEmpty ? Set(memberEntries.map(\.name)) : Set(sharedNames)
    }

    /// Ưu tiên khớp theo email tài khoản đang đăng nhập với email đã gắn cho
    /// từng thành viên (`FamilyMember.email`) — đúng cho cả người tạo lẫn
    /// người được mời, không phụ thuộc tên hiển thị Google có trùng tên
    /// thành viên trong sheet hay không. Không khớp được thì mới rơi về so
    /// tên hiển thị (tương thích các workspace cũ chưa có email gắn theo).
    private static func defaultPaidBy(memberEntries: [FamilyMember], currentUserName: String, currentUserEmail: String) -> String {
        if !currentUserEmail.isEmpty, let matched = memberEntries.first(where: { $0.email?.caseInsensitiveCompare(currentUserEmail) == .orderedSame }) {
            return matched.name
        }
        let names = memberEntries.map(\.name)
        return names.contains(currentUserName) ? currentUserName : (names.first ?? "")
    }

    var canSubmit: Bool {
        !isSubmitting
            && parsedAmount != nil
            && !content.trimmingCharacters(in: .whitespaces).isEmpty
            && (!isFamily || !paidBy.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// Comma-joined in `members` order (not `Set`'s arbitrary order) so the
    /// sheet's "Chi cho ai" column reads consistently across rows.
    private var sharedWithToSave: String {
        members.filter(selectedSharers.contains).joined(separator: ",")
    }
    
    /// VND has no minor unit — "." "," here are thousands separators, not
    /// decimals, so strip to digits only before parsing.
    private var parsedAmount: Decimal? {
        let digitsOnly = amountText.filter(\.isNumber)
        guard !digitsOnly.isEmpty, let value = Decimal(string: digitsOnly), value > 0 else { return nil }
        return value
    }

    /// The category string to persist: the sheet's original text if it never
    /// mapped to a case and the user hasn't picked a different one, else the
    /// currently selected case.
    private var categoryToSave: String {
        if category == .other, let unmappedOriginalCategory {
            return unmappedOriginalCategory
        }
        return category.rawValue
    }
    
    func submitEntry() async {
        guard let amount = parsedAmount else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            // Đang sửa thì update đúng hàng, đang thêm mới thì append hàng mới.
            if let rowIndex = editingRowIndex {
                try await sheetsService.updateRow(
                    spreadsheetId: spreadsheetId,
                    tabTitle: tabTitle,
                    rowIndex: rowIndex,
                    category: categoryToSave,
                    content: content.trimmingCharacters(in: .whitespaces),
                    amount: NSDecimalNumber(decimal: amount).stringValue,
                    paidBy: isFamily ? paidBy : nil,
                    sharedWith: isFamily ? sharedWithToSave : nil
                )
            } else {
                try await sheetsService.appendRow(
                    spreadsheetId: spreadsheetId,
                    tabTitle: tabTitle,
                    date: Self.isoDateFormatter.string(from: Date()),
                    category: category.rawValue,
                    content: content.trimmingCharacters(in: .whitespaces),
                    amount: NSDecimalNumber(decimal: amount).stringValue,
                    paidBy: isFamily ? paidBy : nil,
                    sharedWith: isFamily ? sharedWithToSave : nil
                )
                // Xoá số tiền/nội dung để nhập tiếp, giữ Loại (hay nhập liên tiếp cùng loại).
                amountText = ""
                content = ""
            }
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// "1500000" -> "1.500.000".
    private static func groupedAmountText(fromDigits digits: String) -> String {
        guard !digits.isEmpty, let value = Decimal(string: digits) else { return "" }
        return NumberFormatter.vndGrouping.string(from: NSDecimalNumber(decimal: value)) ?? digits
    }

    /// True when `newValue` only appended to or trimmed from the end of
    /// `oldValue`'s digits — the common typing flow, as opposed to an edit
    /// somewhere in the middle of the string.
    private static func isEditAtEnd(from oldValue: String, to newValue: String) -> Bool {
        let oldDigits = oldValue.filter(\.isNumber)
        let newDigits = newValue.filter(\.isNumber)
        return newDigits.hasPrefix(oldDigits) || oldDigits.hasPrefix(newDigits)
    }
    
    /// ISO format tránh nhập nhằng "dd/MM/yyyy" vs "MM/dd/yyyy" theo locale sheet.
    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()
}
