import SwiftUI
import Charts

// MARK: - ExerciseProgressView

/// Charts and personal bests for a single exercise.
struct ExerciseProgressView: View {
    let exerciseId: String

    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var authManager

    @State private var progressData: ProgressData?
    @State private var selectedFilter: TimeFilter = .threeMonths
    @State private var selectedMetric: MetricTab  = .heaviestWeight
    @State private var loading = true

    // MARK: - Metric tabs

    enum MetricTab: String, CaseIterable {
        case heaviestWeight = "Weight"
        case estimated1RM   = "Est. 1RM"
        case totalVolume    = "Volume"
    }

    private var chartPoints: [ChartPoint] {
        guard let data = progressData else { return [] }
        switch selectedMetric {
        case .heaviestWeight: return data.heaviestWeight
        case .estimated1RM:   return data.estimated1RM
        case .totalVolume:    return data.totalVolume
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Time filter pills
                timeFilterRow

                // Metric tabs
                metricTabRow

                // Chart
                chartSection

                // Personal bests
                if let data = progressData {
                    personalBestsSection(data.personalBests)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .task(id: selectedFilter) { await load() }
    }

    // MARK: - Time filter row

    private var timeFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TimeFilter.allCases, id: \.self) { filter in
                    filterPill(filter)
                }
            }
        }
    }

    @ViewBuilder
    private func filterPill(_ filter: TimeFilter) -> some View {
        Button {
            selectedFilter = filter
        } label: {
            Text(filter.rawValue)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selectedFilter == filter ? .white : colors.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selectedFilter == filter ? colors.accent : colors.surface2)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metric tab row

    private var metricTabRow: some View {
        SegmentedControl(
            segments: MetricTab.allCases.map {
                SegmentedControl<MetricTab>.Segment(label: $0.rawValue, value: $0)
            },
            selection: $selectedMetric
        )
    }

    // MARK: - Chart section

    @ViewBuilder
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if loading {
                ZStack {
                    colors.surface
                    ProgressView().tint(colors.accent)
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else if chartPoints.isEmpty {
                ZStack {
                    colors.surface
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 32))
                            .foregroundStyle(colors.muted)
                        Text("No data in this range")
                            .font(.system(size: 14))
                            .foregroundStyle(colors.muted)
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Chart(chartPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(selectedMetric.rawValue, point.value)
                    )
                    .foregroundStyle(colors.accent)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value(selectedMetric.rawValue, point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [colors.accent.opacity(0.3), colors.accent.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(selectedMetric.rawValue, point.value)
                    )
                    .foregroundStyle(colors.accent)
                    .symbolSize(30)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(colors.border)
                        AxisValueLabel()
                            .foregroundStyle(colors.muted)
                            .font(.system(size: 10))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(colors.border)
                        AxisValueLabel()
                            .foregroundStyle(colors.muted)
                            .font(.system(size: 10))
                    }
                }
                .frame(height: 200)
                .padding(12)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(colors.border, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Personal bests section

    @ViewBuilder
    private func personalBestsSection(_ bests: [PersonalBestStat]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal Bests")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colors.muted)
                .textCase(.uppercase)
                .tracking(0.5)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(bests, id: \.label) { stat in
                    personalBestCard(stat)
                }
            }
        }
    }

    @ViewBuilder
    private func personalBestCard(_ stat: PersonalBestStat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: stat.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(colors.accent)
                Text(stat.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colors.muted)
            }
            Text(stat.value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(colors.text)
            Text(stat.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(colors.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    // MARK: - Data loading

    private func load() async {
        loading = true
        defer { loading = false }
        let unit = authManager.user?.settings.weightUnit ?? "kg"
        progressData = try? await ExerciseHistoryService.getProgress(
            exerciseId,
            filter: selectedFilter,
            unit: unit
        )
    }
}

// MARK: - Preview

#Preview {
    ExerciseProgressView(exerciseId: "exercise-1")
        .background(Color(hex: "#0b0b0f"))
        .shiftTheme()
        .environment(AuthManager())
}
