//
//  CategoryPickerField.swift
//  SplitNote
//

import SwiftUI

/// Ô "Loại": macOS dùng menu chọn gốc, iOS gõ-để-lọc kèm danh sách chạm-để-chọn.
struct CategoryPickerField: View {
    @Binding var selection: ExpenseCategory
    /// Return khi đang focus ô này (macOS) — để lưu form giống các ô khác.
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        #if os(macOS)
        menuPicker
        #else
        CategorySearchField(selection: $selection)
        #endif
    }

    #if os(macOS)
    /// Menu gốc không có trạng thái "đang gõ" nên không kẹt focus, không che form.
    private var menuPicker: some View {
        Picker(selection: $selection) {
            ForEach(ExpenseCategory.allCases) { category in
                Label(category.rawValue, systemImage: category.icon)
                    .tag(category)
            }
        } label: {
            HStack(spacing: 12) {
                IconBadge(systemName: selection.icon, color: selection.color, size: 28)
                    .animation(.snappy, value: selection)
                Text("Loại")
            }
        }
        .pickerStyle(.menu)
        .keyboardStepper(onUp: { step(by: -1) }, onDown: { step(by: 1) }, onCharacter: jump(to:), onSubmit: onSubmit)
        .help("↑/↓ đổi loại · gõ chữ cái đầu để nhảy tới")
    }

    /// Đi lên/xuống trong danh sách, quá 2 đầu thì xoay vòng.
    private func step(by offset: Int) {
        let all = ExpenseCategory.allCases
        guard let index = all.firstIndex(of: selection) else { return }
        let newIndex = ((index + offset) % all.count + all.count) % all.count
        selection = all[newIndex]
    }

    /// Nhảy tới loại kế tiếp bắt đầu bằng chữ vừa gõ (không dấu); gõ lại cùng chữ thì xoay vòng.
    private func jump(to character: Character) {
        let typed = String(character).searchFolded
        let all = ExpenseCategory.allCases
        let startIndex = (all.firstIndex(of: selection) ?? -1) + 1
        let ordered = all[startIndex...] + all[..<startIndex]
        let match = ordered.first { $0.rawValue.searchFolded.hasPrefix(typed) }
        guard let match else { return }
        selection = match
    }
    #endif
}

#if os(iOS)
/// Gõ để lọc loại (không dấu, không phân biệt hoa/thường), danh sách hiện ngay dưới ô khi đang focus.
private struct CategorySearchField: View {
    @Binding var selection: ExpenseCategory
    @State private var queryText: String
    @FocusState private var isFocused: Bool

    init(selection: Binding<ExpenseCategory>) {
        _selection = selection
        _queryText = State(initialValue: selection.wrappedValue.rawValue)
    }

    /// Chữ vẫn là tên loại đang chọn (chưa gõ gì) thì hiện đủ danh sách để duyệt.
    private var isQueryUntouched: Bool {
        queryText == selection.rawValue
    }

    private var suggestions: [ExpenseCategory] {
        let folded = queryText.searchFolded
        guard !folded.isEmpty, !isQueryUntouched else { return ExpenseCategory.allCases }
        return ExpenseCategory.allCases.filter { $0.rawValue.searchFolded.contains(folded) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldRow
            if isFocused {
                suggestionList
            }
        }
    }

    private var fieldRow: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: selection.icon, color: selection.color, size: 28)
                .animation(.snappy, value: selection)
            Text("Loại")
            TextField("Loại", text: $queryText, prompt: Text("Gõ để tìm"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .onSubmit(commitQuery)
                .onChange(of: isFocused) { _, focused in
                    // Rời ô khi đã gõ mà chưa xác nhận thì tự xác nhận.
                    guard !focused, !isQueryUntouched else { return }
                    commitQuery()
                }
                // selection đổi từ bên ngoài (vd reset form) thì đồng bộ lại chữ hiển thị.
                .onChange(of: selection) { _, newValue in
                    guard queryText != newValue.rawValue else { return }
                    queryText = newValue.rawValue
                }
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var suggestionList: some View {
        if suggestions.isEmpty {
            Text("Không tìm thấy loại phù hợp")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions, id: \.self) { category in
                        Button {
                            select(category)
                        } label: {
                            suggestionRow(category)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    private func suggestionRow(_ category: ExpenseCategory) -> some View {
        HStack(spacing: 10) {
            IconBadge(systemName: category.icon, color: category.color, size: 24)
            Text(category.rawValue)
            Spacer()
            if category == selection {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// Chọn xong thì đóng danh sách — bỏ focus để không bị kẹt trong ô.
    private func select(_ category: ExpenseCategory) {
        selection = category
        queryText = category.rawValue
        isFocused = false
    }

    /// Khớp đúng tên thì chọn loại đó; không thì lấy gợi ý đầu tiên; không có gợi ý thì giữ loại đang chọn.
    private func commitQuery() {
        let match = Self.exactMatch(for: queryText) ?? (isQueryUntouched ? nil : suggestions.first)
        select(match ?? selection)
    }

    private static func exactMatch(for text: String) -> ExpenseCategory? {
        let folded = text.searchFolded
        return ExpenseCategory.allCases.first { $0.rawValue.searchFolded == folded }
    }
}
#endif
