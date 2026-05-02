import SwiftUI
import Charts

struct MeasurementsTabView: View {
    @Binding var triggerAdd: Bool

    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var authManager

    @State private var latestPerType: [BodyMeasurement] = []
    @State private var isLoading = true
    @State private var showAddSheet = false
    @State private var preselectedType: MeasurementType?

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
        .sheet(isPresented: $showAddSheet, onDismiss: { preselectedType = nil }) {
            AddMeasurementSheet(unit: measurementUnit, preselectedType: preselectedType) {
                Task { await loadData() }
            }
        }
        .onChange(of: triggerAdd) { _, val in
            if val {
                triggerAdd = false
                preselectedType = nil
                showAddSheet = true
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
            Text("Track body measurements to see your progress over time")
                .font(.system(size: 14))
                .foregroundStyle(colors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                preselectedType = nil
                showAddSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Add Measurement")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(colors.accent)
                .clipShape(Capsule())
            }
            .padding(.top, 4)
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
                                    preselectedType = type
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
        if latestPerType.isEmpty { isLoading = true }
        latestPerType = (try? await ProgressService.getLatestPerType()) ?? []
        isLoading = false
    }
}

// MARK: - AddMeasurementSheet

struct AddMeasurementSheet: View {
    let unit: String
    var preselectedType: MeasurementType?
    var onSave: (() -> Void)?

    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @FocusState private var valueIsFocused: Bool

    @State private var selectedType: MeasurementType = .chest
    @State private var value = ""
    @State private var recordedAt = Date()
    @State private var saving = false
    @State private var saveError: String?

    private var canSave: Bool {
        guard let v = Double(value) else { return false }
        return v > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            // Type selector
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Type")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(colors.muted)
                                    .textCase(.uppercase)
                                    .kerning(0.3)

                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)
                                ], spacing: 8) {
                                    ForEach(MeasurementType.allCases, id: \.rawValue) { type in
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.15)) { selectedType = type }
                                        } label: {
                                            VStack(spacing: 6) {
                                                Image(systemName: type.icon)
                                                    .font(.system(size: 16))
                                                Text(type.displayName)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.8)
                                            }
                                            .foregroundStyle(selectedType == type ? .white : colors.text)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(selectedType == type ? colors.accent : colors.surface)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(selectedType == type ? colors.accent : colors.border, lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            // Value input
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Value")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(colors.muted)
                                        .textCase(.uppercase)
                                        .kerning(0.3)
                                    Spacer()
                                    if valueIsFocused {
                                        Button("Done") { valueIsFocused = false }
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(colors.accent)
                                    }
                                }

                                HStack(spacing: 12) {
                                    TextField("0.0", text: $value)
                                        .keyboardType(.decimalPad)
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(colors.text)
                                        .focused($valueIsFocused)
                                        .multilineTextAlignment(.center)

                                    Text(unit)
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(colors.muted)
                                }
                                .padding(16)
                                .background(colors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(valueIsFocused ? colors.accent : colors.border, lineWidth: 1)
                                )
                            }
                            .id("valueField")

                            // Date
                            HStack {
                                Text("Date")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(colors.muted)
                                    .textCase(.uppercase)
                                    .kerning(0.3)
                                Spacer()
                                DatePicker("", selection: $recordedAt, in: ...Date(), displayedComponents: .date)
                                    .labelsHidden()
                                    .tint(colors.accent)
                            }
                            .padding(14)
                            .background(colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(colors.border, lineWidth: 1)
                            )

                            if let saveError {
                                Text(saveError)
                                    .font(.system(size: 13))
                                    .foregroundStyle(colors.danger)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(colors.danger.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            // Spacer so keyboard doesn't cover content
                            Spacer().frame(height: 120)
                        }
                        .padding(16)
                    }
                    .onChange(of: valueIsFocused) { _, focused in
                        if focused {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation { proxy.scrollTo("valueField", anchor: .center) }
                            }
                        }
                    }
                }
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
            .onAppear {
                if let preselectedType { selectedType = preselectedType }
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
                        if entries.count >= 2 { chartSection }
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
            AddMeasurementSheet(unit: measurementUnit, preselectedType: type) {
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
        if entries.isEmpty { isLoading = true }
        entries = (try? await ProgressService.getMeasurements(type: measurementType)) ?? []
        isLoading = false
    }
}
