//
//  SheetSessionView.swift
//  SplitNote
//

import SwiftUI

/// The "working session" for one sheet tab: add an expense row. The running
/// total lives in the sheet itself (column F's `SUM` formula) — open the
/// link to see it.
struct SheetSessionView: View {
    @StateObject private var viewModel: SheetSessionViewModel
    private let spreadsheetURL: URL?

    init(spreadsheetId: String, tabTitle: String, spreadsheetURL: URL?) {
        _viewModel = StateObject(wrappedValue: SheetSessionViewModel(spreadsheetId: spreadsheetId, tabTitle: tabTitle))
        self.spreadsheetURL = spreadsheetURL
    }

    var body: some View {
        Form {
            Section("Thêm khoản chi") {
                TextField("Số tiền", text: $viewModel.amountText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                TextField("Nội dung", text: $viewModel.content)
                TextField("Loại", text: $viewModel.category)

                Button {
                    Task { await viewModel.submitEntry() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Thêm")
                        }
                        Spacer()
                    }
                }
                .disabled(!viewModel.canSubmit)
            }

            if let message = viewModel.errorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                }
            }

            if let url = spreadsheetURL {
                Section {
                    Link("Mở Google Sheet ↗", destination: url)
                }
            }
        }
        .navigationTitle(viewModel.tabTitle)
    }
}
