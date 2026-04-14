import SwiftUI

struct ActivityDetailView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors

    @State var activityData: ActivityData
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    // Animated values
    @State private var animatedMove: Double = 0
    @State private var animatedExercise: Double = 0
    @State private var animatedStand: Double = 0
    @State private var animatedSteps: Int = 0
    @State private var animatedDistance: Double = 0

    private var moveProgress: Double {
        activityData.moveGoal > 0 ? min(1.0, animatedMove / activityData.moveGoal) : 0
    }
    private var exerciseProgress: Double {
        activityData.exerciseGoal > 0 ? min(1.0, animatedExercise / activityData.exerciseGoal) : 0
    }
    private var standProgress: Double {
        activityData.standGoal > 0 ? min(1.0, animatedStand / activityData.standGoal) : 0
    }

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Week calendar
                WeekCalendar(
                    selected: $selectedDate,
                    weekStartsOn: authManager.user?.settings.weekStartsOn ?? "monday"
                )
                .padding(.bottom, 4)

                VStack(spacing: 12) {
                    // Rings
                    ringsSection
                        .padding(.top, 4)

                    // Stat rows
                    statRow(color: .red, icon: "flame.fill", title: "Move",
                            value: Int(animatedMove), unit: "kcal",
                            goal: Int(activityData.moveGoal), progress: moveProgress)

                    statRow(color: .green, icon: "figure.run", title: "Exercise",
                            value: Int(animatedExercise), unit: "min",
                            goal: Int(activityData.exerciseGoal), progress: exerciseProgress)

                    statRow(color: .cyan, icon: "figure.stand", title: "Stand",
                            value: Int(animatedStand), unit: "hrs",
                            goal: Int(activityData.standGoal), progress: standProgress)

                    // Steps + Distance side by side
                    HStack(spacing: 12) {
                        bottomCard(
                            icon: "figure.walk",
                            title: "Steps",
                            value: formatSteps(animatedSteps),
                            subtitle: stepGoalSubtitle
                        )
                        bottomCard(
                            icon: "map.fill",
                            title: "Distance",
                            value: formatDistance(animatedDistance),
                            subtitle: nil
                        )
                    }
                }
                .padding(.horizontal, 16)

                Spacer()
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { syncAnimatedValues(animate: false) }
        .onChange(of: selectedDate) {
            Task { await loadActivity() }
        }
    }

    // MARK: - Rings

    private var ringsSection: some View {
        ZStack {
            Circle().stroke(colors.border, lineWidth: 10).frame(width: 130, height: 130)
            Circle()
                .trim(from: 0, to: moveProgress)
                .stroke(Color.red, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .frame(width: 130, height: 130)
                .rotationEffect(.degrees(-90))

            Circle().stroke(colors.border, lineWidth: 10).frame(width: 104, height: 104)
            Circle()
                .trim(from: 0, to: exerciseProgress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .frame(width: 104, height: 104)
                .rotationEffect(.degrees(-90))

            Circle().stroke(colors.border, lineWidth: 10).frame(width: 78, height: 78)
            Circle()
                .trim(from: 0, to: standProgress)
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .frame(width: 78, height: 78)
                .rotationEffect(.degrees(-90))
        }
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.6), value: animatedMove)
        .animation(.easeInOut(duration: 0.6), value: animatedExercise)
        .animation(.easeInOut(duration: 0.6), value: animatedStand)
    }

    // MARK: - Stat row

    private func statRow(
        color: Color, icon: String, title: String,
        value: Int, unit: String, goal: Int, progress: Double
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(colors.text)
                }
                Spacer()
                HStack(spacing: 3) {
                    Text("\(value)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.text)
                        .contentTransition(.numericText())
                    Text("/ \(goal) \(unit)")
                        .font(.system(size: 12))
                        .foregroundStyle(colors.muted)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colors.surface2)
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * progress, height: 5)
                        .animation(.easeInOut(duration: 0.6), value: progress)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    // MARK: - Bottom card

    private func bottomCard(icon: String, title: String, value: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(colors.accent)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.muted)
            }
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(colors.text)
                .contentTransition(.numericText())
            Text(subtitle ?? " ")
                .font(.system(size: 11))
                .foregroundStyle(subtitle != nil ? colors.muted : .clear)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    private var stepGoalSubtitle: String? {
        guard let goal = authManager.user?.settings.dailyStepGoal else { return nil }
        let diff = animatedSteps - goal
        let isToday = Calendar.current.isDateInToday(selectedDate)

        if diff >= 0 {
            return diff == 0 ? "Goal hit" : "\(formatSteps(diff)) over target"
        }
        if isToday {
            return "\(formatSteps(-diff)) to go"
        }
        return "\(formatSteps(-diff)) short of target"
    }

    // MARK: - Helpers

    private func formatSteps(_ steps: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }

    private func formatDistance(_ km: Double) -> String {
        let unit = authManager.user?.settings.distanceUnit ?? "km"
        let value = unit == "mi" ? km * 0.621371 : km
        return String(format: "%.2f %@", value, unit)
    }

    // MARK: - Animation

    private func syncAnimatedValues(animate: Bool) {
        if animate {
            withAnimation(.easeInOut(duration: 0.6)) {
                animatedMove = activityData.moveCalories
                animatedExercise = activityData.exerciseMinutes
                animatedStand = activityData.standHours
                animatedSteps = activityData.steps
                animatedDistance = activityData.distanceKm
            }
        } else {
            animatedMove = activityData.moveCalories
            animatedExercise = activityData.exerciseMinutes
            animatedStand = activityData.standHours
            animatedSteps = activityData.steps
            animatedDistance = activityData.distanceKm
        }
    }

    // MARK: - Data loading

    private func loadActivity() async {
        if let data = await HealthKitService.fetchActivity(for: selectedDate) {
            activityData = data
        } else {
            activityData = ActivityData()
        }
        syncAnimatedValues(animate: true)
    }
}
