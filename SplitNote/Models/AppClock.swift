//
//  AppClock.swift
//  SplitNote
//

import Foundation

/// Single source of truth for "now" wherever month-tab logic needs it.
nonisolated enum AppClock {
    static var now: Date { Date() }
}
