//
//  ParsedNote.swift
//  SplitNote
//

import Foundation

/// The structured result of parsing a single free-form note line, before any
/// workspace or spreadsheet context (real people, category list, ...) is applied.
struct ParsedNote: Equatable {
    let rawText: String
    let noteDescription: String
    let amount: Decimal
    let splitStrategy: SplitStrategy
}

/// How the amount in a `ParsedNote` should be divided among people.
/// Resolving names into real `Person` values, and picking who fills an
/// unnamed equal split, happens later once a workspace's participant list is known.
enum SplitStrategy: Equatable {
    /// e.g. "/3" — split equally among a given number of people, participants unnamed.
    case equalCount(Int)
    /// e.g. "@An,Binh" with optional "/trừ Minh" — split among named people, minus any excluded.
    case byParticipants(include: [String], exclude: [String])
}
