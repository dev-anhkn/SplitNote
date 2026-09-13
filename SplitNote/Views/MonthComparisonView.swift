//
//  MonthComparisonView.swift
//  SplitNote
//

import SwiftUI
import Charts

/// Biểu đồ cột so sánh tổng chi giữa các tháng, lọc theo 3/6/9 tháng gần
/// nhất tính tới tháng hiện tại.
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
                    Text(message)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                } else {
                    Chart(viewModel.monthlyTotals) { item in
                        BarMark(
                            x: .value("Tháng", item.label),
                            y: .value("Số tiền", NSDecimalNumber(decimal: item.total).doubleValue)
                        )
                        // 1 chỉ số duy nhất (tổng chi) theo thời gian, không
                        // phải nhiều series cần phân biệt — giữ 1 màu nhất quán.
                        .foregroundStyle(Color.accentColor)
                        .annotation(position: .top) {
                            Text(item.total.formattedVND)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    Spacer()
                }
            }
            .padding(.top)
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
}

#Preview {
    MonthComparisonView(spreadsheetId: "preview")
}
