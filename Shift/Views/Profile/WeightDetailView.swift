import SwiftUI
import Charts

struct WeightTabView: View {
    @Binding var triggerAdd: Bool

    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors

    @State private var entries: [WeightEntry] = []
    @State private var isLoading = true
    @State private var showAddSheet = false

    private var weightUnit: String { authManager.user?.settings.weightUnit ?? "kg" }

    var body: some View {
        Group {
            if isLoading {
                Spacer()
                ProgressView().tint(colors.accent)
                Spacer()
            } else if entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        currentWeightCard
                        if entries.count >= 2 { chartCard }
                        historyCard
                    }
                    .padding(20)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            WeightEntrySheet {
                await loadEntries()
            }
        }
        .task { await loadEntries() }
        .onChange(of: triggerAdd) { _, val in
            if val {
                triggerAdd = false
                showAddSheet = true
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "scalemass")
                .font(.system(size: 36))
                .foregroundStyle(colors.muted)
            Text("No weight entries yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colors.text)
            Text("Track your body weight over time")
                .font(.system(size: 14))
                .foregroundStyle(colors.muted)

            Button {
                showAddSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Log Weight")
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

    // MARK: - Current weight card

    private var currentWeightCard: some View {
        let latest = entries.first
        let previous = entries.count > 1 ? entries[1] : nil
        let diff: Double? = {
            guard let l = latest, let p = previous else { return nil }
            return l.weight - p.weight
        }()

        return VStack(spacing: 8) {
            Text(latest.map { formatWeightValue($0.weight) + " " + weightUnit } ?? "--")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(colors.text)

            if let diff, abs(diff) > 0.05 {
                HStack(spacing: 4) {
                    Image(systemName: diff > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(diff > 0 ? "+" : "")\(formatWeightValue(diff)) \(weightUnit)")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(colors.muted)
            }

            if let latest {
                HStack(spacing: 4) {
                    if latest.source == "healthkit" {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.pink)
                    }
                    Text(latest.recordedAt, style: .date)
                        .font(.system(size: 12))
                        .foregroundStyle(colors.muted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    // MARK: - Chart card

    private var chartCard: some View {
        let chartEntries = Array(entries.prefix(30).reversed())
        let weights = chartEntries.map(\.weight)
        let minW = (weights.min() ?? 0) - 2
        let maxW = (weights.max() ?? 100) + 2

        return VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.muted)
                .textCase(.uppercase)
                .kerning(0.5)

            Chart {
                ForEach(chartEntries, id: \.id) { entry in
                    LineMark(
                        x: .value("Date", entry.recordedAt),
                        y: .value("Weight", entry.weight)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(colors.accent)

                    AreaMark(
                        x: .value("Date", entry.recordedAt),
                        y: .value("Weight", entry.weight)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [colors.accent.opacity(0.2), colors.accent.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    PointMark(
                        x: .value("Date", entry.recordedAt),
                        y: .value("Weight", entry.weight)
                    )
                    .foregroundStyle(colors.accent)
                    .symbolSize(20)
                }
            }
            .chartYScale(domain: minW...maxW)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine().foregroundStyle(colors.border)
                    AxisValueLabel()
                        .foregroundStyle(colors.muted)
                        .font(.system(size: 10))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine().foregroundStyle(colors.border)
                    AxisValueLabel()
                        .foregroundStyle(colors.muted)
                        .font(.system(size: 10))
                }
            }
            .frame(height: 200)
        }
        .padding(16)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    // MARK: - History card

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.muted)
                .textCase(.uppercase)
                .kerning(0.5)

            ForEach(entries) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.recordedAt, style: .date)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(colors.text)
                        HStack(spacing: 4) {
                            if entry.source == "healthkit" {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.pink)
                                Text("Apple Health")
                                    .font(.system(size: 11))
                                    .foregroundStyle(colors.muted)
                            } else {
                                Text("Manual")
                                    .font(.system(size: 11))
                                    .foregroundStyle(colors.muted)
                            }
                        }
                    }

                    Spacer()

                    Text("\(formatWeightValue(entry.weight)) \(weightUnit)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.accent)
                }
                .padding(12)
                .background(colors.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contextMenu {
                    Button(role: .destructive) {
                        Task {
                            try? await WeightEntryService.delete(entry.id)
                            await loadEntries()
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .padding(16)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    // MARK: - Data loading

    private func loadEntries() async {
        guard let userId = try? authManager.requireUserId() else { return }
        isLoading = true

        var fetched = (try? await WeightEntryRepository.findAll(userId: userId)) ?? []

        if fetched.isEmpty, let profileWeight = authManager.user?.weight, profileWeight > 0 {
            let seed = WeightEntry(
                id: UUID().uuidString.lowercased(),
                userId: userId,
                weight: profileWeight,
                unit: authManager.user?.settings.weightUnit ?? "kg",
                source: "manual",
                recordedAt: Date(),
                createdAt: Date()
            )
            _ = try? await WeightEntryService.insert(seed)
            fetched = [seed]
        }

        entries = fetched
        isLoading = false
    }

    private func formatWeightValue(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

// MARK: - Weight Entry Sheet

struct WeightEntrySheet: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    var onSaved: (() async -> Void)?

    @State private var weightText = ""
    @State private var date = Date()
    @State private var isSaving = false
    @State private var healthKitWeight: Double?

    private var weightUnit: String { authManager.user?.settings.weightUnit ?? "kg" }

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                Form {
                    Section("Weight") {
                        HStack {
                            TextField("e.g. 80", text: $weightText)
                                .keyboardType(.decimalPad)
                                .foregroundStyle(colors.text)
                            Text(weightUnit)
                                .foregroundStyle(colors.muted)
                                .font(.system(size: 13))
                        }
                    }
                    .listRowBackground(colors.surface)

                    if let hkWeight = healthKitWeight {
                        Section {
                            Button {
                                weightText = formatWeightValue(hkWeight)
                            } label: {
                                HStack {
                                    Image(systemName: "heart.fill")
                                        .foregroundStyle(.pink)
                                        .font(.system(size: 14))
                                    Text("Use Apple Health: \(formatWeightValue(hkWeight)) \(weightUnit)")
                                        .font(.system(size: 14))
                                        .foregroundStyle(colors.text)
                                    Spacer()
                                    Image(systemName: "arrow.right.circle.fill")
                                        .foregroundStyle(colors.accent)
                                        .font(.system(size: 16))
                                }
                            }
                        }
                        .listRowBackground(colors.accent.opacity(0.08))
                    }

                    Section("Date") {
                        DatePicker(
                            "Recorded",
                            selection: $date,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .foregroundStyle(colors.text)
                        .tint(colors.accent)
                    }
                    .listRowBackground(colors.surface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(colors.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Save")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(colors.accent)
                        }
                    }
                    .disabled(isSaving || weightText.isEmpty)
                }
            }
            .onAppear {
                if let w = authManager.user?.weight {
                    weightText = formatWeightValue(w)
                }
                loadHealthKitWeight()
            }
        }
    }

    private func loadHealthKitWeight() {
        guard authManager.user?.settings.healthKit.syncBodyWeight == true else { return }
        Task {
            guard let hkWeightKg = await HealthKitService.readLatestBodyWeight() else { return }
            let displayWeight = convertWeight(hkWeightKg, to: weightUnit)
            healthKitWeight = (displayWeight * 10).rounded() / 10
        }
    }

    private func save() async {
        guard let w = Double(weightText),
              let userId = try? authManager.requireUserId() else { return }
        isSaving = true

        let source = healthKitWeight.map({ abs($0 - w) < 0.05 }) == true ? "healthkit" : "manual"

        let entry = WeightEntry(
            id: UUID().uuidString.lowercased(),
            userId: userId,
            weight: w,
            unit: weightUnit,
            source: source,
            recordedAt: date,
            createdAt: Date()
        )

        _ = try? await WeightEntryService.insert(entry)
        _ = try? await ProfileService.updateProfile(ProfilePatch(weight: w))

        if authManager.user?.settings.healthKit.syncBodyWeight == true {
            let weightKg = weightUnit == "lbs" ? w / 2.20462 : w
            _ = try? await HealthKitService.writeBodyWeight(weightKg, date: date)
        }

        await authManager.refreshUser()
        await onSaved?()
        isSaving = false
        dismiss()
    }

    private func formatWeightValue(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
