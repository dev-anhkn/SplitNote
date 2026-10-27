//
//  ViewModelTests.swift
//  SplitNoteTests
//

import Foundation
import Testing
@testable import SplitNote

@MainActor
struct ExpenseListViewModelTests {
    private func makeViewModel(rows: [ExpenseEntry] = [], error: Error? = nil) -> ExpenseListViewModel {
        let service = FakeSheetsService()
        service.rows = rows
        service.fetchRowsError = error
        return ExpenseListViewModel(spreadsheetId: "s", workspaceType: .personal, sheetsService: service)
    }

    @Test func groupsByDayNewestFirstWithTotals() async {
        let viewModel = makeViewModel(rows: [
            .fake(row: 2, date: "2026-09-01", amount: 100),
            .fake(row: 3, date: "2026-09-02", amount: 50),
            .fake(row: 4, date: "2026-09-01", amount: 30)
        ])
        await viewModel.loadEntries()

        let sections = viewModel.daySections
        #expect(sections.map(\.id) == ["2026-09-02", "2026-09-01"])
        #expect(sections.map(\.total) == [50, 130])
        #expect(sections[1].entries.map(\.rowIndex) == [4, 2])
        #expect(viewModel.totalAmount == 180)
    }

    @Test func topCategoriesSortedAndCapped() async {
        let viewModel = makeViewModel(rows: [
            .fake(row: 2, date: "2026-09-01", category: .food, amount: 10),
            .fake(row: 3, date: "2026-09-01", category: .travel, amount: 300),
            .fake(row: 4, date: "2026-09-01", category: .health, amount: 200),
            .fake(row: 5, date: "2026-09-01", category: .gifts, amount: 100)
        ])
        await viewModel.loadEntries()

        #expect(viewModel.topCategories.map(\.category) == [.travel, .health, .gifts])
    }

    @Test func missingTabShowsCreateState() async {
        let viewModel = makeViewModel(error: SheetsServiceError.notFound)
        await viewModel.loadEntries()

        #expect(viewModel.sheetMissing)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func otherErrorsSurfaceMessage() async {
        let viewModel = makeViewModel(error: SheetsServiceError.requestFailed("boom"))
        await viewModel.loadEntries()

        #expect(!viewModel.sheetMissing)
        #expect(viewModel.errorMessage == "boom")
    }

    @Test func switchingMonthDropsPreviousEntriesImmediately() async {
        let viewModel = makeViewModel(rows: [.fake(row: 2, date: "2026-09-01", amount: 100)])
        await viewModel.loadEntries()

        viewModel.goToPreviousMonth()

        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.isSwitchingMonth)
        await viewModel.loadEntries()
        #expect(!viewModel.isSwitchingMonth)
    }
}

@MainActor
struct QuickAddExpenseViewModelTests {
    private let tabTitle = MonthTabTitle.title(for: AppClock.now)
    private let members = [
        FamilyMember(name: "An", email: "an@gmail.com"),
        FamilyMember(name: "Bình")
    ]

    @Test func paidByPrefersEmailMatch() {
        let viewModel = QuickAddExpenseViewModel(spreadsheetId: "s", tabTitle: tabTitle, memberEntries: members, currentUserName: "Bình", currentUserEmail: "AN@gmail.com", sheetsService: FakeSheetsService())
        #expect(viewModel.paidBy == "An")
    }

    @Test func paidByFallsBackToNameThenFirstMember() {
        let byName = QuickAddExpenseViewModel(spreadsheetId: "s", tabTitle: tabTitle, memberEntries: members, currentUserName: "Bình", sheetsService: FakeSheetsService())
        #expect(byName.paidBy == "Bình")
        let fallback = QuickAddExpenseViewModel(spreadsheetId: "s", tabTitle: tabTitle, memberEntries: members, currentUserName: "Lạ", sheetsService: FakeSheetsService())
        #expect(fallback.paidBy == "An")
    }

    @Test func newFormSharesWithEveryone() {
        let viewModel = QuickAddExpenseViewModel(spreadsheetId: "s", tabTitle: tabTitle, memberEntries: members, sheetsService: FakeSheetsService())
        #expect(viewModel.selectedSharers == ["An", "Bình"])
    }

    @Test func missingFieldsHint() {
        let viewModel = QuickAddExpenseViewModel(spreadsheetId: "s", tabTitle: tabTitle, sheetsService: FakeSheetsService())
        #expect(viewModel.missingFieldsHint == "Nhập số tiền và nội dung để lưu")
        viewModel.content = "Ăn trưa"
        #expect(viewModel.missingFieldsHint == "Nhập số tiền để lưu")
        viewModel.amountText = "48000"
        #expect(viewModel.missingFieldsHint == nil)
        #expect(viewModel.canSubmit)
    }

    @Test func doubleSubmitSavesOnce() async {
        let service = FakeSheetsService()
        let viewModel = QuickAddExpenseViewModel(spreadsheetId: "s", tabTitle: tabTitle, sheetsService: service)
        viewModel.content = "Cafe"
        viewModel.amountText = "50000"

        async let first: Void = viewModel.submitEntry()
        async let second: Void = viewModel.submitEntry()
        _ = await (first, second)

        #expect(service.appendedRowCount == 1)
    }

    @Test func shiftDateStaysInsideTabMonth() {
        let entry = ExpenseEntry(rowIndex: 2, date: "2026-09-01", category: "Ăn uống", content: "x", amount: 1, paidBy: "", sharedWith: "")
        let viewModel = QuickAddExpenseViewModel(spreadsheetId: "s", tabTitle: "Tháng 09-2026", editing: entry, sheetsService: FakeSheetsService())
        viewModel.shiftDate(byDays: -1)
        #expect(DateFormatter.isoDay.string(from: viewModel.date) == "2026-09-01")
        viewModel.shiftDate(byDays: 3)
        #expect(DateFormatter.isoDay.string(from: viewModel.date) == "2026-09-04")
    }

    @Test func editingKeepsUnmappedCategoryAndAmount() {
        let entry = ExpenseEntry(rowIndex: 5, date: "2026-09-01", category: "Thú cưng", content: "Hạt", amount: 1_500_000, paidBy: "", sharedWith: "Bình")
        let viewModel = QuickAddExpenseViewModel(spreadsheetId: "s", tabTitle: "Tháng 09-2026", editing: entry, memberEntries: members, sheetsService: FakeSheetsService())
        #expect(viewModel.isEditing)
        #expect(viewModel.category == .other)
        #expect(viewModel.amountText == "1.500.000")
        #expect(viewModel.selectedSharers == ["Bình"])
    }
}

@MainActor
struct FamilyMembersViewModelTests {
    private func makeViewModel(sheets: FakeSheetsService = FakeSheetsService(), drive: FakeDriveService = FakeDriveService()) -> FamilyMembersViewModel {
        FamilyMembersViewModel(spreadsheetId: "s", tabTitle: "Tháng 09-2026", sheetsService: sheets, driveService: drive)
    }

    @Test func duplicateNamesFromSheetDoNotCrash() {
        let viewModel = makeViewModel()
        viewModel.setMembers(["An", "An"])
        viewModel.setMembers(["An", "An", "Bình"], emails: ["a@x.com"])
        #expect(viewModel.members == ["An", "An", "Bình"])
        #expect(viewModel.memberEntries.map(\.email) == ["a@x.com", nil, nil])
    }

    @Test func addMemberSavesNamesAndEmailsTogetherThenShares() async {
        let sheets = FakeSheetsService()
        let drive = FakeDriveService()
        let viewModel = makeViewModel(sheets: sheets, drive: drive)
        viewModel.setMembers(["An"])

        let saved = await viewModel.addMember(name: " Bình ", email: "binh@gmail.com")

        #expect(saved)
        #expect(sheets.savedMemberLists.last?.names == ["An", "Bình"])
        #expect(sheets.savedMemberLists.last?.emails == ["", "binh@gmail.com"])
        #expect(drive.sharedEmails == ["binh@gmail.com"])
    }

    @Test func addMemberRollsBackWhenSaveFails() async {
        let sheets = FakeSheetsService()
        sheets.setMemberListError = FakeError()
        let drive = FakeDriveService()
        let viewModel = makeViewModel(sheets: sheets, drive: drive)
        viewModel.setMembers(["An"])

        let saved = await viewModel.addMember(name: "Bình", email: "binh@gmail.com")

        #expect(!saved)
        #expect(viewModel.members == ["An"])
        #expect(viewModel.errorMessage != nil)
        #expect(drive.sharedEmails.isEmpty)
    }

    @Test func addMemberRejectsInvalidEmailAndDuplicates() async {
        let viewModel = makeViewModel()
        viewModel.setMembers(["An"])

        #expect(await viewModel.addMember(name: "Bình", email: "khong-phai-email") == false)
        #expect(viewModel.errorMessage == "Email không hợp lệ.")
        #expect(await viewModel.addMember(name: "An", email: "") == false)
        #expect(viewModel.members == ["An"])
    }

    @Test func removeMemberRevokesDriveAccess() async {
        let drive = FakeDriveService()
        let viewModel = makeViewModel(drive: drive)
        viewModel.setMembers(["An", "Bình"], emails: ["", "binh@gmail.com"])

        await viewModel.removeMember("Bình")

        #expect(viewModel.members == ["An"])
        #expect(drive.revokedEmails == ["binh@gmail.com"])
    }
}
