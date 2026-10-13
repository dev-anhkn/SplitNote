//
//  AppClock.swift
//  SplitNote
//

import Foundation

/// Nguồn "bây giờ" duy nhất cho logic tab tháng.
nonisolated enum AppClock {
    static var now: Date { Date() }
}
