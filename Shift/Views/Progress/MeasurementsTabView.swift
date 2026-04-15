import SwiftUI
import Charts

struct MeasurementsTabView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var authManager

    @State private var latestPerType: [BodyMeasurement] = []
    @State private var isLoading = true
    @State private var showAddSheet = false

    private var measurementUnit: String {
        authManager.user?.settings.measurementUnit ?? "cm"
    }

    var body: some View {
        Group {
            if isLoading {
                Spacer()
                ProgressView().tint(colors.accent)
                Spacer()
            } else if latestPerType.isEmpty {
                emptyState
            } else {
                measurementList
            }
        }
        .task { await loadData() }
        .sheet(isPresented: $showAddSheet) {
            AddMeasurementSheet(unit: measurementUnit) {
                Task { await loadData() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.accent)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "ruler")
                .font(.system(size: 36))
                .foregroundStyle(colors.muted)
            Text("No measurements yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colors.text)
            Text("Tap + to log your first measurement")
                .font(.system(size: 14))
                .foregroundStyle(colors.muted)
            Spacer()
        }
    }

    private var measurementList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(latestPerType, id: \.id) { measurement in
                    NavigationLink {
                        MeasurementDetailView(measurementType: measurement.type)
                    } label: {
                        measurementRow(measurement)
                    }
                    .buttonStyle(.plain)
                }

                // Quick-add for types not yet tracked
                let trackedTypes = Set(latestPerType.map(\.type))
                let untrackedTypes = MeasurementType.allCases.filter { !trackedTypes.contains($0.rawValue) }
                if !untrackedTypes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add more")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(colors.muted)
                            .textCase(.uppercase)
                            .kerning(0.3)
                            .padding(.top, 8)

                        FlowLayout(spacing: 8) {
                            ForEach(untrackedTypes, id: \.rawValue) { type in
                                Button {
                                    showAddSheet = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 10, weight: .bold))
                                        Text(type.displayName)
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundStyle(colors.accent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(colors.accent.opacity(0.1))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    private func measurementRow(_ measurement: BodyMeasurement) -> some View {
        let type = measurement.measurementType

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(colors.accent.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: type?.icon ?? "ruler")
                    .font(.system(size: 16))
                    .foregroundStyle(colors.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(type?.displayName ?? measurement.type)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.text)
                Text(measurement.recordedAt, style: .date)
                    .font(.system(size: 12))
                    .foregroundStyle(colors.muted)
            }

            Spacer()

            Text(formatValue(measurement.value) + " " + measurement.unit)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(colors.text)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colors.muted)
        }
        .padding(14)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    private func formatValue(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private func loadData() async {
        isLoading = true
        latestPerType = (try? await ProgressService.getLatestPerType()) ?? []
        isLoading = false
    }
}

// MARK: - AddMeasurementSheet

struct AddMeasurementSheet: View {
    let unit: String
    var onSave: (() -> Void)?

    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: MeasurementType = .chest
    @State private var value = ""
    @State private var recordedAt = Date()
    @State private var saving = false
    @State private var saveError: String?

    private var canSave: Bool {
        Double(value) != nil && Double(value)! > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                Form {
                    Section("Measurement Type") {
                        Picker("Type", selection: $selectedType) {
                            ForEach(MeasurementType.allCases, id: \.rawValue) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .foregroundStyle(colors.text)
                    }
                    .listRowBackground(colors.surface)

                    Section("Value (\(unit))") {
                        TextField("0.0", text: $value)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 15))
                            .foregroundStyle(colors.text)
                    }
                    .listRowBackground(colors.surface)

                    Section("Date") {
                        DatePicker("", selection: $recordedAt, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .foregroundStyle(colors.text)
                    }
                    .listRowBackground(colors.surface)

                    if let saveError {
                        Section {
                            Text(saveError)
                                .font(.system(size: 13))
                                .foregroundStyle(colors.danger)
                        }
                        .listRowBackground(colors.danger.opacity(0.1))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canSave ? colors.accent : colors.muted)
                    .disabled(!canSave || saving)
                }
            }
        }
    }

    private func save() async {
        guard let numericValue = Double(value), numericValue > 0 else { return }
        saving = true
        saveError = nil
        do {
            _ = try await ProgressService.addMeasurement(
                type: selectedType.rawValue,
                value: numericValue,
                unit: unit,
                recordedAt: recordedAt
            )
            onSave?()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        saving = false
    }
}

// MARK: - MeasurementDetailView

struct MeasurementDetailView: View {
    let measurementType: String

    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var authManager

    @State private var entries: [BodyMeasurement] = []
    @State private var isLoading = true
    @State private var showAddSheet = false
    @State private var entryToDelete: BodyMeasurement?

    private var type: MeasurementType? {
        MeasurementType(rawValue: measurementType)
    }

    private var measurementUnit: String {
        authManager.user?.settings.measurementUnit ?? "cm"
    }

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(colors.accent)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Chart
                        if entries.count >= 2 {
                            chartSection
                        }

                        // History
                        historySection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle(type?.displayName ?? measurementType)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.accent)
                }
            }
        }
        .task { await loadData() }
        .sheet(isPresented: $showAddSheet) {
            AddMeasurementSheet(unit: measurementUnit) {
                Task { await loadData() }
            }
        }
        .alert("Delete Entry", isPresented: .init(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { entryToDelete = nil }
            Button("Delete", role: .destructive) {
                if let entry = entryToDelete {
                    Task {
                        try? await ProgressService.deleteMeasurement(entry.id)
                        await loadData()
                    }
                }
            }
        } message: {
            Text("Delete this measurement entry?")
        }
    }

    private var chartSection: some View {
        let sortedEntries = entries.reversed()

        return VStack(alignment: .leading, spacing: 8) {
            Text("Trend")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.muted)
                .textCase(.uppercase)
                .kerning(0.3)

            Chart {
                ForEach(Array(sortedEntries), id: \.id) { entry in
                    LineMark(
                        x: .value("Date", entry.recordedAt),
                        y: .value("Value", entry.value)
                    )
                    .foregroundStyle(colors.accent)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", entry.recordedAt),
                        y: .value("Value", entry.value)
                    )
                    .foregroundStyle(colors.accent)
                    .symbolSize(30)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(formatValue(v))
                                .font(.system(size: 11))
                                .foregroundStyle(colors.muted)
                        }
                    }
                    AxisGridLine()
                        .foregroundStyle(colors.border)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.system(size: 10))
                                .foregroundStyle(colors.muted)
                        }
                    }
                }
            }
            .frame(height: 200)
            .padding(16)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(colors.border, lineWidth: 1)
            )
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.muted)
                .textCase(.uppercase)
                .kerning(0.3)

            LazyVStack(spacing: 0) {
                ForEach(entries, id: \.id) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatValue(entry.value) + " " + entry.unit)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(colors.text)
                            Text(entry.recordedAt, style: .date)
                                .font(.system(size: 12))
                                .foregroundStyle(colors.muted)
                        }

                        Spacer()

                        // Change from previous
                        if let idx = entries.firstIndex(where: { $0.id == entry.id }),
                           idx + 1 < entries.count {
                            let prev = entries[idx + 1]
                            let diff = entry.value - prev.value
                            if abs(diff) > 0.05 {
                                HStack(spacing: 2) {
                                    Image(systemName: diff > 0 ? "arrow.up.right" : "arrow.down.right")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("\(diff > 0 ? "+" : "")\(formatValue(diff))")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(colors.muted)
                            }
                        }

                        Button {
                            entryToDelete = entry
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundStyle(colors.danger.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    if entry.id != entries.last?.id {
                        Divider()
                            .background(colors.border)
                            .padding(.leading, 14)
                    }
                }
            }
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(colors.border, lineWidth: 1)
            )
        }
    }

    private func formatValue(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private func loadData() async {
        isLoading = true
        entries = (try? await ProgressService.getMeasurements(type: measurementType)) ?? []
        isLoading = false
    }
}
