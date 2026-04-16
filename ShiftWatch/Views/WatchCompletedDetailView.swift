import SwiftUI

struct WatchCompletedDetailView: View {
    @Environment(WatchSessionManager.self) private var session
    @Environment(\.dismiss) private var dismiss

    let completed: WatchCompletedSession

    @State private var showDeleteAlert = false
    @State private var isDeleting = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Header
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(WatchColors.success)

                Text(completed.name)
                    .font(.system(size: 15, weight: .bold))
                    .multilineTextAlignment(.center)

                // Stats
                VStack(spacing: 10) {
                    statRow(icon: "clock", label: "Duration", value: formatDuration(from: completed.startedAt, to: completed.endedAt))
                    statRow(icon: "figure.strengthtraining.traditional", label: "Exercises", value: "\(completed.exerciseCount)")
                    statRow(icon: "number", label: "Sets", value: "\(completed.setCount)")
                }
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Delete button
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Delete Workout", systemImage: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(isDeleting)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete workout?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                isDeleting = true
                session.deleteSession(sessionId: completed.sessionId) { _ in
                    Task { @MainActor in
                        isDeleting = false
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This workout will be permanently deleted.")
        }
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
    }

    private func formatDuration(from start: Date, to end: Date) -> String {
        let mins = Int(end.timeIntervalSince(start)) / 60
        if mins < 1 { return "<1m" }
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(mins)m"
    }
}
