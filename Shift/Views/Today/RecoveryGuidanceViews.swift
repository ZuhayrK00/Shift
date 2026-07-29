import SwiftUI

struct RecoveryGuidanceCard: View {
    @Environment(\.shiftColors) private var colors
    let snapshot: RecoverySnapshot
    let onCheckIn: () -> Void

    var body: some View {
        Button(action: onCheckIn) {
            HStack(spacing: 13) {
                Image(systemName: snapshot.recommendation.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(colors.accent)
                    .frame(width: 42, height: 42)
                    .background(colors.accent.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Recovery")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(colors.muted)
                            .textCase(.uppercase)
                        Spacer()
                        Text(snapshot.checkIn == nil ? "Check in" : "Update")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(colors.accent)
                    }
                    Text(snapshot.recommendation.rawValue)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(colors.text)
                    Text(snapshot.reasons.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(colors.muted)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .background(colors.surface)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

struct RecoveryCheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.shiftColors) private var colors
    let currentValue: Int?
    let onSave: (Int) -> Void

    @State private var selected = 3

    private let choices = [
        (1, "Run down", "battery.0percent"),
        (2, "Tired", "battery.25percent"),
        (3, "Okay", "battery.50percent"),
        (4, "Good", "battery.75percent"),
        (5, "Great", "battery.100percent")
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("How do you feel today?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(colors.text)

                VStack(spacing: 8) {
                    ForEach(choices, id: \.0) { value, title, symbol in
                        Button {
                            selected = value
                        } label: {
                            HStack {
                                Image(systemName: symbol)
                                    .frame(width: 25)
                                Text(title)
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                                if selected == value {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            .foregroundStyle(selected == value ? colors.accent : colors.text)
                            .padding(14)
                            .background(selected == value ? colors.accent.opacity(0.1) : colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Guidance uses your check-in and available Health data. It is not a medical assessment.")
                    .font(.system(size: 12))
                    .foregroundStyle(colors.muted)

                Spacer()

                Button {
                    onSave(selected)
                    dismiss()
                } label: {
                    Text("Save check-in")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(20)
            .background(colors.bg.ignoresSafeArea())
            .navigationTitle("Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { selected = currentValue ?? 3 }
        }
        .presentationDetents([.medium, .large])
    }
}
