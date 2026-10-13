//
//  SheetsHelpersTests.swift
//  SplitNoteTests
//

import Foundation
import Testing
@testable import SplitNote

struct SheetsHTTPTests {
    @Test(arguments: [(1, "A"), (4, "D"), (6, "F"), (26, "Z"), (27, "AA"), (52, "AZ"), (53, "BA")])
    func columnLetter(index: Int, expected: String) {
        #expect(SheetsHTTP.columnLetter(index) == expected)
    }

    @Test(arguments: [("300000", Decimal(300000)), ("300.000", 300000), ("300,000", 300000), ("-50.000", -50000)])
    func parseAmount(text: String, expected: Decimal) {
        #expect(SheetsHTTP.parseAmount(text) == expected)
    }

    @Test func parseAmountRejectsEmpty() {
        #expect(SheetsHTTP.parseAmount("") == nil)
        #expect(SheetsHTTP.parseAmount("abc") == nil)
    }

    @Test func cellReturnsEmptyWhenTrimmedBySheets() {
        let row = ["2026-09-01", "Ăn uống"]
        #expect(SheetsHTTP.cell(row, 1) == "Ăn uống")
        #expect(SheetsHTTP.cell(row, 3) == "")
    }

    @Test func bodyRangeEscapesSingleQuote() {
        #expect(SheetsHTTP.bodyRange(tabTitle: "Tháng 09-2026", cells: "A1:D1") == "'Tháng 09-2026'!A1:D1")
        #expect(SheetsHTTP.bodyRange(tabTitle: "An's", cells: "A1") == "'An''s'!A1")
    }
}

struct SheetsLayoutTests {
    @Test func totalSitsInColumnFAfterSpacer() {
        #expect(SheetsLayout.totalColumn == "F")
    }

    @Test func headerAndTotalWritesToCurrentLayout() {
        let ranges = SheetsRequests.headerAndTotal(tabTitle: "T").map(\.range)
        #expect(ranges == ["'T'!A1:D1", "'T'!F1:F2"])
    }

    @Test func familyHeadersMatchDataColumns() {
        let ranges = SheetsRequests.familyHeaders(tabTitle: "T").map(\.range)
        #expect(ranges == ["'T'!H1:J1", "'T'!L1:O1"])
    }
}

struct MonthTabTitleTests {
    private func date(_ year: Int, _ month: Int, _ day: Int = 15) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func titleIsZeroPaddedWithDash() {
        #expect(MonthTabTitle.title(for: date(2026, 9)) == "Tháng 09-2026")
    }

    @Test func dateIntervalRoundTrips() throws {
        let interval = try #require(MonthTabTitle.dateInterval(for: "Tháng 09-2026"))
        #expect(interval.start == date(2026, 9, 1))
        #expect(MonthTabTitle.title(for: interval.start) == "Tháng 09-2026")
    }

    @Test(arguments: ["Tổng hợp", "_Mẫu", "Tháng 9", "Tháng ab-2026"])
    func dateIntervalRejectsOtherTitles(title: String) {
        #expect(MonthTabTitle.dateInterval(for: title) == nil)
    }

    @Test func displayLabel() {
        #expect(MonthTabTitle.displayLabel(for: date(2026, 9)) == "Tháng 9 · 2026")
    }
}

struct WorkspaceStoreTests {
    private func makeStore() -> (WorkspaceStore, UserDefaults) {
        let suite = "SplitNoteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (WorkspaceStore(defaults: defaults), defaults)
    }

    @Test func nextAvailableIndexSkipsFilledSlots() {
        let (store, _) = makeStore()
        store.setSpreadsheetId("a", for: .personal, at: 0)
        store.setSpreadsheetId("c", for: .personal, at: 2)
        #expect(store.nextAvailableIndex(for: .personal) == 1)
        store.setSpreadsheetId("b", for: .personal, at: 1)
        #expect(store.nextAvailableIndex(for: .personal) == nil)
    }

    @Test func legacyKeyMigratesIntoSlotZero() {
        let (store, defaults) = makeStore()
        defaults.set("old-id", forKey: StorageKeys.legacySpreadsheetId(type: .personal))
        #expect(store.spreadsheetId(for: .personal, at: 0) == "old-id")
        #expect(defaults.string(forKey: StorageKeys.legacySpreadsheetId(type: .personal)) == nil)
        #expect(defaults.string(forKey: StorageKeys.spreadsheetId(type: .personal, index: 0)) == "old-id")
    }

    @Test func clearingSlotAlsoClearsName() {
        let (store, _) = makeStore()
        store.setSpreadsheetId("a", for: .personal, at: 0)
        store.setName("Du lịch", for: .personal, at: 0)
        store.clearSpreadsheetId(for: .personal, at: 0)
        #expect(store.name(for: .personal, at: 0) == nil)
    }
}

struct WorkspaceNameTests {
    private typealias Workspace = WorkspaceListViewModel.Workspace

    @Test func driveTitleRoundTrips() {
        #expect(Workspace.name(fromDriveTitle: Workspace.driveTitle(for: "Du lịch")) == "Du lịch")
    }

    @Test func driveTitleWithoutPrefixUsesWholeTitle() {
        #expect(Workspace.name(fromDriveTitle: "Sổ của tôi") == "Sổ của tôi")
        #expect(Workspace.name(fromDriveTitle: "SplitNote - ") == nil)
    }

    @Test func sanitizedNameTrimsAndLimitsLength() {
        #expect(Workspace.sanitizedName("   ") == nil)
        #expect(Workspace.sanitizedName("  Ăn chơi ") == "Ăn chơi")
        #expect(Workspace.sanitizedName(String(repeating: "a", count: 100))?.count == Workspace.maxNameLength)
    }
}

struct DecimalTests {
    @Test func formattedVNDGroupsThousands() {
        #expect(Decimal(1_500_000).formattedVND == "1.500.000 đ")
    }

    @Test func roundedToWhole() {
        #expect(Decimal(string: "1234.6")!.roundedToWhole == 1235)
    }
}

struct StringSearchTests {
    @Test func searchFoldedIgnoresAccentsCaseAndD() {
        #expect("Điện nước".searchFolded == "dien nuoc")
        #expect("  Ăn Uống ".searchFolded == "an uong")
    }
}
