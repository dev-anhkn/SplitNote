//
//  AppClock.swift
//  SplitNote
//

import Foundation

/// Single source of truth for "now" wherever month-tab logic needs it.
enum AppClock {
    nonisolated static var now: Date {
        Date()
    }
}
