import SwiftUI

struct WorkoutProgramCard: View {
    @Environment(\.shiftColors) private var colors

    let program: WorkoutProgramSummary
    let isStarting: Bool
    let onOpen: () -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: program.source == "ai" ? "sparkles" : "rectangle.stack.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(colors.accent)
                        .frame(width: 36, height: 36)
                        .background(colors.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(program.name)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(colors.text)
                                .lineLimit(1)
                            if program.isActive {
                                Text("ACTIVE")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(colors.success)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(colors.success.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        Text("\(program.workouts.count)-workout rotation")
                            .font(.system(size: 12))
                            .foregroundStyle(colors.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(colors.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let next = program.nextWorkout {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("UP NEXT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(colors.muted)
                            .tracking(0.7)
                        Text(next.plan.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(colors.text)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(action: onStart) {
                        HStack(spacing: 6) {
                            if isStarting {
                                ProgressView().tint(.white).scaleEffect(0.75)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10))
                            }
                            Text("Start")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(colors.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isStarting)
                }
                .padding(12)
                .background(colors.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 11))
            }
        }
        .padding(14)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(colors.border, lineWidth: 1))
    }
}

struct WorkoutProgramDetailView: View {
    @Environment(\.shiftColors) private var colors
    let program: WorkoutProgramSummary
    let onMakeActive: () -> Void
    @State private var becameActive = false

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !program.isActive && !becameActive {
                        Button {
                            becameActive = true
                            onMakeActive()
                        } label: {
                            Label("Make Active Program", systemImage: "checkmark.circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(colors.accent)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(colors.accent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(Array(program.workouts.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item.plan) {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(colors.accent)
                                    .frame(width: 30, height: 30)
                                    .background(colors.accent.opacity(0.12))
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.plan.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(colors.text)
                                    Text("\(pluralise(item.exerciseCount, "exercise")) · \(WorkoutDurationEstimator.formatDuration(minutes: item.estimatedMinutes))")
                                        .font(.system(size: 12))
                                        .foregroundStyle(colors.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(colors.muted)
                            }
                            .padding(14)
                            .background(colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(colors.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
