//
//  AppClock.swift
//  SplitNote
//

import Foundation

/// Single source of truth for "now" wherever month-tab logic needs it.
/// TEMP TEST HACK: hardcoded to October to test month rollover — revert `now` back to `Date()` once confirmed.
enum AppClock {
    static var now: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 5
        return Calendar.current.date(from: components) ?? Date()
    }
}
