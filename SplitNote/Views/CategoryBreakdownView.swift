//
//  CategoryBreakdownView.swift
//  SplitNote
//

import SwiftUI
import Charts

/// Donut chart tổng chi theo Loại của 1 tháng — chỉ hiện category đang có
/// giá trị (`ViewModel.totals` đã lọc >0), kèm legend liệt kê số tiền/%.
/// Tự tải dữ liệu từ tab "Tổng hợp" thay vì nhận sẵn từ màn danh sách.
struct CategoryBreakdownView: View {
    @StateObject private var viewModel: CategoryBreakdownViewModel
    @Environment(\.dismiss) private var dismiss

    init(spreadsheetId: String, tabTitle: String) {
        _viewModel = StateObject(wrappedValue: CategoryBreakdownViewModel(spreadsheetId: spreadsheetId, tabTitle: tabTitle))
    }

    private var grandTotal: Decimal {
        viewModel.totals.reduce(0) { $0 + $1.total }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.totals.isEmpty {
                    ProgressView()
                } else if let message = viewModel.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                } else if viewModel.totals.isEmpty {
                    ContentUnavailableView("Chưa có khoản chi nào", systemImage: "chart.pie")
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            chart
                            legend
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle(viewModel.tabTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task {
                await viewModel.load()
            }
        }
    }

    private var chart: some View {
        Chart(viewModel.totals, id: \.category) { item in
            SectorMark(
                angle: .value("Số tiền", NSDecimalNumber(decimal: item.total).doubleValue),
                innerRadius: .ratio(0.6),
                angularInset: 1.5
            )
            .foregroundStyle(Self.color(for: item.category))
            .cornerRadius(4)
        }
        .frame(height: 260)
        .padding(.horizontal)
    }

    private var legend: some View {
        VStack(spacing: 10) {
            ForEach(viewModel.totals, id: \.category) { item in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Self.color(for: item.category))
                        .frame(width: 10, height: 10)
                    Text(item.category)
                    Spacer()
                    Text(item.total.formattedVND)
                        .monospacedDigit()
                    Text(Self.percentageText(item.total, of: grandTotal))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .font(.subheadline)
            }
        }
        .padding(.horizontal)
    }

    private static func color(for category: String) -> Color {
        ExpenseCategory(rawValue: category)?.color ?? .gray
    }

    private static func percentageText(_ value: Decimal, of total: Decimal) -> String {
        guard total > 0 else { return "0%" }
        let fraction = NSDecimalNumber(decimal: value).doubleValue / NSDecimalNumber(decimal: total).doubleValue
        return String(format: "%.0f%%", fraction * 100)
    }
}

#Preview {
    CategoryBreakdownView(spreadsheetId: "preview", tabTitle: "Tháng 09-2026")
}
