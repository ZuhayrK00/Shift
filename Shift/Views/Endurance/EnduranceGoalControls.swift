import SwiftUI

struct EnduranceGoalControls: View {
    @Environment(\.shiftColors) private var colors
    @Binding var sport: String
    @Binding var metric: EnduranceMetric
    @Binding var period: EnduranceGoalPeriod
    @Binding var target: String
    @Binding var deadline: Date
    var unit: String
    @FocusState private var targetFocused: Bool
    @State private var editingTarget = false
    private var targetUnit: String { metric == .distance ? unit : metric == .duration ? "minutes" : "activities" }
    private var presets: [Int] { metric == .distance ? [5, 10, 20, 50] : metric == .duration ? [30, 60, 90, 150] : [2, 3, 5, 7] }
    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 18) {
                Image(systemName: EnduranceSport(rawValue: sport)?.symbol ?? "target")
                    .font(.system(size: 34, weight: .medium)).foregroundStyle(colors.enduranceAccent)
                    .frame(width: 86, height: 86).background(colors.enduranceSoft, in: Circle())
                    .overlay(Circle().stroke(colors.enduranceAccent.opacity(0.3), lineWidth: 1))
                VStack(spacing: 4) {
                    Group {
                        if editingTarget {
                            TextField("5", text: $target).textFieldStyle(.plain).multilineTextAlignment(.center)
                                .focused($targetFocused).accessibilityLabel("Goal target")
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .onAppear { targetFocused = true }
                                .onChange(of: targetFocused) { _, focused in if !focused { editingTarget = false } }
                        } else {
                            Button { editingTarget = true } label: { Text(target.isEmpty ? "0" : target).frame(maxWidth: .infinity) }
                                .buttonStyle(.plain).accessibilityLabel("Edit goal target").accessibilityValue(target)
                        }
                    }.font(.system(size: 64, weight: .bold, design: .rounded)).minimumScaleFactor(0.5)
                    Text("\(targetUnit) \(period == .week ? "each week" : period == .month ? "each month" : "by your target date")")
                        .font(.subheadline).foregroundStyle(colors.muted)
                }
                HStack(spacing: 28) {
                    adjustButton("minus", amount: -1)
                    Text("YOUR TARGET").font(.caption2.weight(.semibold)).tracking(1.8).foregroundStyle(colors.muted)
                    adjustButton("plus", amount: 1)
                }
                HStack(spacing: 10) {
                    ForEach(presets, id: \.self) { value in
                        Button { targetFocused = false; target = value.formatted() } label: {
                            Text("\(value)").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(target == value.formatted() ? colors.enduranceSoft : colors.surface2, in: Capsule())
                                .foregroundStyle(target == value.formatted() ? colors.enduranceAccent : colors.muted)
                        }.buttonStyle(.plain).accessibilityLabel("Set target to \(value) \(targetUnit)")
                    }
                }
            }.padding(.vertical, 18)
            VStack(alignment: .leading, spacing: 16) {
                Text("Activity").font(.headline)
                HStack(spacing: 8) {
                    sportButton("All", "target", "all")
                    ForEach(EnduranceSport.allCases) { sportButton($0.title, $0.symbol, $0.rawValue) }
                }
                Divider().overlay(colors.border)
                HStack {
                    Text("Measure").font(.subheadline)
                    Spacer()
                    Picker("Measure", selection: $metric) { ForEach(EnduranceMetric.allCases) { Text($0.title).tag($0) } }.labelsHidden().tint(colors.enduranceAccent)
                }
            }.padding(18).background(colors.surface, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(colors.border, lineWidth: 1))
            VStack(alignment: .leading, spacing: 14) {
                Text("Timeframe").font(.headline)
                HStack(spacing: 6) {
                    ForEach(EnduranceGoalPeriod.allCases) { value in
                        Button { targetFocused = false; period = value } label: {
                            Text(value.title).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(period == value ? colors.enduranceSoft : colors.surface2, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(period == value ? colors.enduranceAccent : colors.muted)
                        }.buttonStyle(.plain)
                    }
                }
                if period == .deadline { DatePicker("Target date", selection: $deadline, in: Date()..., displayedComponents: .date).font(.subheadline) }
                Text(period == .deadline ? "Counts activities from when you created this goal, through your chosen date." : "Your activities and Apple Health imports count for the whole calendar \(period == .week ? "week" : "month").")
                    .font(.caption).foregroundStyle(colors.muted).fixedSize(horizontal: false, vertical: true)
            }.padding(18).background(colors.surface, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(colors.border, lineWidth: 1))
        }
    }
    private func sportButton(_ title: String, _ symbol: String, _ value: String) -> some View {
        Button { targetFocused = false; sport = value } label: {
            VStack(spacing: 9) { Image(systemName: symbol).font(.title3); Text(title).font(.caption.weight(.medium)) }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .foregroundStyle(sport == value ? colors.enduranceAccent : colors.muted)
                .background(sport == value ? colors.enduranceSoft : colors.surface2, in: RoundedRectangle(cornerRadius: 15))
        }.buttonStyle(.plain).accessibilityAddTraits(sport == value ? .isSelected : [])
    }
    private func adjustButton(_ symbol: String, amount: Double) -> some View {
        Button {
            targetFocused = false
            let formatter = NumberFormatter(); formatter.numberStyle = .decimal
            let value = formatter.number(from: target)?.doubleValue ?? 0
            target = max(metric == .duration ? 5 : 1, value + amount * (metric == .duration ? 5 : 1)).formatted(.number.precision(.fractionLength(0...2)))
        } label: { Image(systemName: symbol).font(.title3.weight(.medium)).frame(width: 46, height: 46).background(colors.surface2, in: Circle()) }
            .buttonStyle(.plain).accessibilityLabel(amount > 0 ? "Increase goal" : "Decrease goal")
    }
}
