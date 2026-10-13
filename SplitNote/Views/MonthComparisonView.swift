//
//  MonthComparisonView.swift
//  SplitNote
//

import SwiftUI
import Charts

/// Biểu đồ cột so sánh tổng chi 3/6/9 tháng gần nhất.
struct MonthComparisonView: View {
    @StateObject private var viewModel: MonthComparisonViewModel
    @Environment(\.dismiss) private var dismiss

    init(spreadsheetId: String) {
        _viewModel = StateObject(wrappedValue: MonthComparisonViewModel(spreadsheetId: spreadsheetId))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Khoảng thời gian", selection: $viewModel.rangeInMonths) {
                    ForEach(MonthComparisonViewModel.rangeOptions, id: \.self) { months in
                        Text("\(months) tháng").tag(months)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if viewModel.isLoading && viewModel.monthlyTotals.isEmpty {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if let message = viewModel.errorMessage {
                    Spacer()
                    ErrorLabel(message: message)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            statsRow
                            chart
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppBackground())
            .animation(.snappy, value: viewModel.rangeInMonths)
            .navigationTitle("So sánh theo tháng")
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

    private var rangeTotal: Decimal {
        viewModel.monthlyTotals.reduce(0) { $0 + $1.total }
    }

    private var monthlyAverage: Decimal {
        guard !viewModel.monthlyTotals.isEmpty else { return 0 }
        return rangeTotal / Decimal(viewModel.monthlyTotals.count)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatTile(title: "Tổng \(viewModel.rangeInMonths) tháng", value: rangeTotal.formattedVND, icon: "sum", color: AppStyle.gold)
            StatTile(title: "Trung bình/tháng", value: monthlyAverage.roundedToWhole.formattedVND, icon: "chart.line.flattrend.xyaxis", color: AppStyle.indigo)
        }
    }

    private var chart: some View {
        Chart(viewModel.monthlyTotals) { item in
            BarMark(
                x: .value("Tháng", item.label),
                y: .value("Số tiền", NSDecimalNumber(decimal: item.total).doubleValue)
            )
            // 1 chỉ số duy nhất theo thời gian — giữ 1 màu nhất quán.
            .foregroundStyle(AppStyle.gold.gradient)
            .cornerRadius(6)
            .annotation(position: .top) {
                Text(item.total.formattedVND)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 280)
        .cardStyle()
    }
}

#Preview {
    MonthComparisonView(spreadsheetId: "preview")
}

private struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            IconBadge(systemName: icon, color: color, size: 26)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.headline, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
