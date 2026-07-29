import SwiftUI

struct PlateCalculatorSheet: View {
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    let targetWeight: Double
    let unit: String
    @State private var barWeight: Double

    init(targetWeight: Double, unit: String) {
        self.targetWeight = targetWeight
        self.unit = unit
        _barWeight = State(initialValue: ["lb", "lbs"].contains(unit.lowercased()) ? 45 : 20)
    }

    private var loading: PlateLoading {
        WorkoutUtilityService.plateLoading(
            targetWeight: targetWeight,
            barWeight: barWeight,
            unit: unit
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Target") {
                    LabeledContent("Total weight", value: "\(format(targetWeight)) \(unit)")
                    Stepper(
                        "Bar: \(format(barWeight)) \(unit)",
                        value: $barWeight,
                        in: 0...max(targetWeight, barWeight),
                        step: ["lb", "lbs"].contains(unit.lowercased()) ? 5 : 2.5
                    )
                }

                Section("Each side") {
                    if loading.platesPerSide.isEmpty {
                        Text(targetWeight <= barWeight
                             ? "Use the bar only."
                             : "This target cannot be made exactly with common plates.")
                            .foregroundStyle(colors.muted)
                    } else {
                        ForEach(
                            Array(groupedPlates.enumerated()),
                            id: \.offset
                        ) { _, item in
                            LabeledContent(
                                "\(format(item.plate)) \(unit)",
                                value: "× \(item.count)"
                            )
                        }
                    }
                    LabeledContent(
                        "Loaded total",
                        value: "\(format(loading.actualWeight)) \(unit)"
                    )
                }

                Section {
                    Text("Plate counts are shown for one side of the bar. Shift rounds down when the exact target is unavailable.")
                        .font(.system(size: 13))
                        .foregroundStyle(colors.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.bg)
            .navigationTitle("Plate Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var groupedPlates: [(plate: Double, count: Int)] {
        var result: [(Double, Int)] = []
        for plate in loading.platesPerSide {
            if let last = result.last, last.0 == plate {
                result[result.count - 1].1 += 1
            } else {
                result.append((plate, 1))
            }
        }
        return result
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
    }
}
