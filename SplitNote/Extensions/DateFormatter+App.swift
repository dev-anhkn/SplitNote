//
//  DateFormatter+App.swift
//  SplitNote
//

import Foundation

extension DateFormatter {
    /// "yyyy-MM-dd" — tránh nhập nhằng dd/MM vs MM/dd theo locale của sheet.
    static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()

    /// "Thứ Năm, 1 thg 10" cho tiêu đề nhóm ngày.
    static let vietnameseDayTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "EEEE, d 'thg' M"
        return formatter
    }()

    /// "09/26" cho nhãn cột biểu đồ tháng.
    static let shortMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/yy"
        return formatter
    }()
}
