//
//  CategoryPickerField.swift
//  SplitNote
//

import SwiftUI

/// Combo-box "Loại" field: gõ để lọc `ExpenseCategory` (không dấu, không phân
/// biệt hoa/thường), hoặc bấm chọn trực tiếp. Return/Tab xác nhận gợi ý đầu.
/// Giá trị luôn ràng buộc vào `ExpenseCategory` — chữ tự do không khớp gì bị
/// bỏ, trả về loại đang chọn.
struct CategoryPickerField: View {
    @Binding var selection: ExpenseCategory
    @State private var queryText: String
    @FocusState private var isFocused: Bool

    init(selection: Binding<ExpenseCategory>) {
        _selection = selection
        _queryText = State(initialValue: selection.wrappedValue.rawValue)
    }

    private var suggestions: [ExpenseCategory] {
        let folded = Self.fold(queryText)
        guard !folded.isEmpty else { return ExpenseCategory.allCases }
        return ExpenseCategory.allCases.filter { Self.fold($0.rawValue).contains(folded) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Loại", text: $queryText)
                .focused($isFocused)
                .onSubmit(commitTopSuggestion)
                .onKeyPress(.tab) {
                    commitTopSuggestion()
                    return .handled
                }
                // Rời ô mà chưa xác nhận thì tự xác nhận.
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitTopSuggestion() }
                }
                // selection đổi từ bên ngoài (vd reset form) thì đồng bộ lại chữ hiển thị.
                .onChange(of: selection) { _, newValue in
                    queryText = newValue.rawValue
                }

            if isFocused {
                if suggestions.isEmpty {
                    Text("Không tìm thấy loại phù hợp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(suggestions) { category in
                                Button {
                                    select(category)
                                } label: {
                                    Text(category.rawValue)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
            }
        }
    }

    private func commitTopSuggestion() {
        if let match = suggestions.first {
            select(match)
        } else {
            // Không có gợi ý khớp thì trả về loại đang chọn, không nhận chữ tự do.
            queryText = selection.rawValue
        }
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
