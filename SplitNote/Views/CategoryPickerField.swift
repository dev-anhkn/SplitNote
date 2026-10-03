//
//  CategoryPickerField.swift
//  SplitNote
//

import SwiftUI

/// Combo-box "Loại" field: gõ để lọc `ExpenseCategory` (không dấu, không phân
/// biệt hoa/thường), hoặc bấm chọn trực tiếp. ↑/↓ di chuyển gợi ý, Return/Tab
/// xác nhận gợi ý đang sáng, Esc huỷ. Giá trị luôn ràng buộc vào
/// `ExpenseCategory` — chữ tự do không khớp gì bị bỏ, trả về loại đang chọn.
struct CategoryPickerField: View {
    @Binding var selection: ExpenseCategory
    @State private var queryText: String
    @State private var highlightedIndex = 0
    @FocusState private var isFocused: Bool

    init(selection: Binding<ExpenseCategory>) {
        _selection = selection
        _queryText = State(initialValue: selection.wrappedValue.rawValue)
    }

    /// Chữ vẫn là tên loại đang chọn (chưa gõ gì) thì hiện đủ danh sách để duyệt bằng mũi tên.
    private var isQueryUntouched: Bool {
        queryText == selection.rawValue
    }

    private var suggestions: [ExpenseCategory] {
        let folded = Self.fold(queryText)
        guard !folded.isEmpty, !isQueryUntouched else { return ExpenseCategory.allCases }
        return ExpenseCategory.allCases.filter { Self.fold($0.rawValue).contains(folded) }
    }

    private var defaultHighlightIndex: Int {
        guard isQueryUntouched else { return 0 }
        return suggestions.firstIndex(of: selection) ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                IconBadge(systemName: selection.icon, color: selection.color, size: 28)
                    .animation(.snappy, value: selection)
                TextField("Loại", text: $queryText, prompt: Text("Loại"))
                    .labelsHidden()
                    .focused($isFocused)
                    .onSubmit(commitHighlighted)
                    .onKeyPress(.tab) {
                        commitHighlighted()
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        moveHighlight(by: 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        moveHighlight(by: -1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        cancelEditing()
                        return .handled
                    }
                    .onChange(of: isFocused) { _, focused in
                        guard !focused else { return highlightedIndex = defaultHighlightIndex }
                        // Rời ô khi đã gõ mà chưa xác nhận thì tự xác nhận; vừa chọn xong thì bỏ qua để không chọn lại theo index cũ.
                        guard !isQueryUntouched else { return }
                        commitHighlighted()
                    }
                    .onChange(of: queryText) {
                        highlightedIndex = defaultHighlightIndex
                    }
                    // selection đổi từ bên ngoài (vd reset form) thì đồng bộ lại chữ hiển thị.
                    .onChange(of: selection) { _, newValue in
                        queryText = newValue.rawValue
                    }
            }

            if isFocused {
                suggestionList
            }
        }
    }

    @ViewBuilder
    private var suggestionList: some View {
        if suggestions.isEmpty {
            Text("Không tìm thấy loại phù hợp")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(suggestions.enumerated()), id: \.element) { index, category in
                            suggestionRow(category, isHighlighted: index == highlightedIndex)
                                .id(category)
                        }
                    }
                }
                .frame(maxHeight: 200)
                // Giữ dòng đang sáng luôn trong vùng nhìn thấy khi bấm mũi tên.
                .onChange(of: highlightedIndex) { _, index in
                    guard suggestions.indices.contains(index) else { return }
                    proxy.scrollTo(suggestions[index])
                }
            }
        }
    }

    private func suggestionRow(_ category: ExpenseCategory, isHighlighted: Bool) -> some View {
        Button {
            select(category)
        } label: {
            HStack(spacing: 10) {
                IconBadge(systemName: category.icon, color: category.color, size: 24)
                Text(category.rawValue)
                Spacer()
                if category == selection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(
                isHighlighted ? Color.accentColor.opacity(0.18) : .clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func moveHighlight(by offset: Int) {
        guard !suggestions.isEmpty else { return }
        highlightedIndex = min(max(highlightedIndex + offset, 0), suggestions.count - 1)
    }

    private func commitHighlighted() {
        guard suggestions.indices.contains(highlightedIndex) else {
            // Không có gợi ý khớp thì trả về loại đang chọn, không nhận chữ tự do.
            queryText = selection.rawValue
            return
        }
        select(suggestions[highlightedIndex])
    }

    private func cancelEditing() {
        queryText = selection.rawValue
        highlightedIndex = defaultHighlightIndex
        isFocused = false
    }

    private func select(_ category: ExpenseCategory) {
        selection = category
        queryText = category.rawValue
        isFocused = false
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
