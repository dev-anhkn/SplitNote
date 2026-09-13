//
//  NoteParserService.swift
//  SplitNote
//

import Foundation

protocol NoteParserServiceProtocol {
    func parse(_ rawText: String) throws -> ParsedNote
}

enum NoteParserError: Error, Equatable, LocalizedError {
    case emptyInput
    case missingAmount
    case invalidAmount(String)
    case missingSplitInfo
    case invalidSplitCount(Int)
    case exclusionWithoutParticipants
    case excludedNameNotIncluded(String)
    case noParticipantsLeftAfterExclusion
    
    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Note text is empty."
        case .missingAmount:
            return "Could not find an amount in the note."
        case .invalidAmount(let raw):
            return "Amount \"\(raw)\" must be a positive number."
        case .missingSplitInfo:
            return "Note must specify a split, e.g. \"/3\" or \"@Name1,Name2\"."
        case .invalidSplitCount(let count):
            return "Split count must be positive, got \(count)."
        case .exclusionWithoutParticipants:
            return "\"/trừ\" requires an \"@\" participant list to exclude from."
        case .excludedNameNotIncluded(let name):
            return "\"\(name)\" is excluded but was not in the participant list."
        case .noParticipantsLeftAfterExclusion:
            return "All participants were excluded; nothing left to split."
        }
    }
}

/// Parses a note line like "Ăn trưa 300k /3" or "Cafe 90k @Lan,Hoa /trừ Minh".
/// Markers: amount (+ k/tr suffix), `@Names`, `/N` (equal split, must be last
/// token to avoid clashing with dates like "10/09"), `/trừ Names`.
struct NoteParserService: NoteParserServiceProtocol {
    
    func parse(_ rawText: String) throws -> ParsedNote {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NoteParserError.emptyInput }
        
        var remaining = trimmed as NSString
        
        let excludedNames = Self.extractNameList(regex: Self.excludeRegex, from: &remaining)
        let equalCount = Self.extractEqualCount(from: &remaining)
        let includedNames = Self.extractNameList(regex: Self.participantsRegex, from: &remaining)
        
        let amount = try Self.extractAmount(from: &remaining)
        
        let splitStrategy = try Self.resolveSplitStrategy(
            includedNames: includedNames,
            excludedNames: excludedNames,
            equalCount: equalCount
        )
        
        let noteDescription = (remaining as String)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        return ParsedNote(
            rawText: trimmed,
            noteDescription: noteDescription,
            amount: amount,
            splitStrategy: splitStrategy
        )
    }
    
    // MARK: - Precompiled patterns
    
    private static let excludeRegex = try! NSRegularExpression(
        pattern: #"/trừ\s+(\S+(?:,\S+)*)"#, options: [.caseInsensitive]
    )
    private static let participantsRegex = try! NSRegularExpression(
        pattern: #"@(\S+)"#, options: [.caseInsensitive]
    )
    /// Anchored to end-of-string so a date like "10/09" isn't read as a split count.
    private static let equalCountRegex = try! NSRegularExpression(
        pattern: #"/(\d+)\s*$"#
    )
    /// Group 1: digits (with "." "," as separators). Group 2: optional k/tr/triệu
    /// suffix, lookahead-guarded so it doesn't swallow a word like "trà".
    private static let amountRegex = try! NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)*)\s*(?:(k|tr|triệu)(?!\p{L}))?"#, options: [.caseInsensitive]
    )
    
    // MARK: - Extraction helpers
    
    private static func extractNameList(regex: NSRegularExpression, from text: inout NSString) -> [String] {
        guard let match = regex.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)),
              match.numberOfRanges > 1 else {
            return []
        }
        let namesString = text.substring(with: match.range(at: 1))
        text = text.replacingCharacters(in: match.range(at: 0), with: "") as NSString
        return namesString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    private static func extractEqualCount(from text: inout NSString) -> Int? {
        guard let match = equalCountRegex.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        let count = Int(text.substring(with: match.range(at: 1)))
        text = text.replacingCharacters(in: match.range(at: 0), with: "") as NSString
        return count
    }
    
    /// Takes the *last* number in what remains, since other markers are already
    /// stripped and unrelated numbers (a quantity, a date) tend to come first.
    private static func extractAmount(from text: inout NSString) throws -> Decimal {
        let matches = amountRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        guard let match = matches.last else {
            throw NoteParserError.missingAmount
        }
        
        let rawNumberText = text.substring(with: match.range(at: 1))
        let hasSuffix = match.range(at: 2).location != NSNotFound
        let normalized = normalizeNumberString(rawNumberText, hasSuffix: hasSuffix)
        guard let baseValue = Decimal(string: normalized) else {
            throw NoteParserError.invalidAmount(rawNumberText)
        }
        
        let suffix = hasSuffix ? text.substring(with: match.range(at: 2)).lowercased() : ""
        let multiplier: Decimal
        switch suffix {
        case "k": multiplier = 1_000
        case "tr", "triệu": multiplier = 1_000_000
        default: multiplier = 1
        }
        
        let amount = baseValue * multiplier
        guard amount > 0 else {
            throw NoteParserError.invalidAmount(rawNumberText)
        }
        
        text = text.replacingCharacters(in: match.range(at: 0), with: "") as NSString
        return amount
    }
    
    /// "." and "," are thousands separators, unless a k/tr suffix makes the last
    /// one a decimal point instead (e.g. "1.5tr").
    private static func normalizeNumberString(_ raw: String, hasSuffix: Bool) -> String {
        guard hasSuffix, let lastSeparatorIndex = raw.lastIndex(where: { $0 == "." || $0 == "," }) else {
            return raw.filter { $0 != "." && $0 != "," }
        }
        let integerPart = raw[raw.startIndex..<lastSeparatorIndex].filter { $0 != "." && $0 != "," }
        let fractionPart = raw[raw.index(after: lastSeparatorIndex)...]
        return "\(integerPart).\(fractionPart)"
    }
    
    private static func resolveSplitStrategy(
        includedNames: [String],
        excludedNames: [String],
        equalCount: Int?
    ) throws -> SplitStrategy {
        if !includedNames.isEmpty {
            for name in excludedNames {
                guard includedNames.contains(name) else {
                    throw NoteParserError.excludedNameNotIncluded(name)
                }
            }
            guard !Set(includedNames).subtracting(excludedNames).isEmpty else {
                throw NoteParserError.noParticipantsLeftAfterExclusion
            }
            return .byParticipants(include: includedNames, exclude: excludedNames)
        }
        
        guard excludedNames.isEmpty else {
            throw NoteParserError.exclusionWithoutParticipants
        }
        
        guard let equalCount else {
            throw NoteParserError.missingSplitInfo
        }
        guard equalCount > 0 else {
            throw NoteParserError.invalidSplitCount(equalCount)
        }
        return .equalCount(equalCount)
    }
}
