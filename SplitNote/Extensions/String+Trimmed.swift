//
//  String+Trimmed.swift
//  SplitNote
//

import Foundation

extension String {
    /// Bỏ khoảng trắng 2 đầu (không bỏ xuống dòng).
    var trimmed: String {
        trimmingCharacters(in: .whitespaces)
    }

    /// Dạng so khớp tìm kiếm: bỏ dấu, không phân biệt hoa/thường, "đ" → "d".
    var searchFolded: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "đ", with: "d")
            .trimmed
    }
}
