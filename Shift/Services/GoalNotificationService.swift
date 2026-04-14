import Foundation

// MARK: - GoalNotificationService

enum GoalNotificationService {

    // MARK: - Public

    /// Clears all existing goal notifications and reschedules based on current state.
    /// Called on app launch, after finishing a workout, and after goal changes.
    static func scheduleAllNotifications() async {
        let settings = authManager.user?.settings ?? .default

        // Clear existing
        NotificationManager.cancelNotifications(withPrefix: "shift.exercise-goal-")
        NotificationManager.cancelNotifications(withPrefix: "shift.frequency-")
        NotificationManager.cancelNotifications(withPrefix: "shift.steps-")
        NotificationManager.cancelNotifications(withPrefix: "shift.rings-")

        guard let userId = try? authManager.requireUserId() else { return }

        let notificationHour = await computeNotificationHour(userId: userId)
        var scheduledCount = 0
        let maxNotifications = 50  // Leave headroom under iOS 64 limit

        // Exercise goal reminders
        if settings.notifications.exerciseGoalReminders {
            scheduledCount += await scheduleExerciseGoalReminders(
                userId: userId,
                hour: notificationHour,
                budget: maxNotifications - scheduledCount
            )
        }

        // Frequency reminders
        if settings.notifications.frequencyReminders, settings.weeklyFrequencyGoal != nil {
            scheduledCount += await scheduleFrequencyReminders(
                userId: userId,
                hour: notificationHour,
                budget: maxNotifications - scheduledCount
            )
        }

        // Step goal reminders
        if settings.notifications.frequencyReminders, let stepGoal = settings.dailyStepGoal, stepGoal > 0 {
            scheduledCount += await scheduleStepGoalReminders(
                stepGoal: stepGoal,
                hour: notificationHour,
                budget: maxNotifications - scheduledCount
            )
        }

        // Activity ring reminders (Move, Exercise, Stand)
        if settings.notifications.frequencyReminders {
            _ = await scheduleActivityRingReminders(
                budget: maxNotifications - scheduledCount
            )
        }
    }

    // MARK: - Notification Hour

    /// Computes the ideal notification hour: 1 hour before average workout time,
    /// falling back to 17 (5pm), clamped to 7-21.
    private static func computeNotificationHour(userId: String) async -> Int {
        let avgHour = try? await SessionRepository.findAverageWorkoutHour(userId: userId)
        let hour = (avgHour ?? 18) - 1  // 1 hour before workout, default 6pm → 5pm
        return min(max(hour, 7), 21)
    }

    // MARK: - Exercise Goal Reminders

    private static func scheduleExerciseGoalReminders(
        userId: String,
        hour: Int,
        budget: Int
    ) async -> Int {
        guard let goals = try? await ExerciseGoalRepository.findActiveForUser(userId),
              !goals.isEmpty else { return 0 }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var scheduled = 0

        for goal in goals {
            guard scheduled < budget else { break }

            let daysUntil = goal.daysRemaining
            guard daysUntil >= 0 else { continue }  // Skip overdue goals

            // Determine which days to schedule
            let scheduleDays: [Int]
            if daysUntil <= 3 {
                // Daily for last 3 days
                scheduleDays = Array(0...daysUntil)
            } else if daysUntil <= 7 {
                // Every other day
                scheduleDays = stride(from: 0, through: daysUntil, by: 2).map { $0 }
            } else {
                // Weekly
                scheduleDays = stride(from: 0, through: daysUntil, by: 7).map { $0 }
            }

            for dayOffset in scheduleDays {
                guard scheduled < budget else { break }
                guard let notifDate = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }
                // Don't schedule for today if the hour has already passed
                if dayOffset == 0 {
                    let currentHour = cal.component(.hour, from: Date())
                    if currentHour >= hour { continue }
                }

                let message = exerciseGoalMessage(daysRemaining: daysUntil - dayOffset)
                var comps = cal.dateComponents([.year, .month, .day], from: notifDate)
                comps.hour = hour
                comps.minute = 0

                NotificationManager.scheduleGoalNotification(
                    identifier: "shift.exercise-goal-\(goal.id)-\(dayOffset)",
                    title: message.title,
                    body: message.body,
                    at: comps
                )
                scheduled += 1
            }
        }

        return scheduled
    }

    // MARK: - Frequency Reminders

    private static func scheduleFrequencyReminders(
        userId: String,
        hour: Int,
        budget: Int
    ) async -> Int {
        guard let progress = try? await GoalService.getFrequencyProgress(),
              progress.target > 0 else { return 0 }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var scheduled = 0

        // Schedule a notification for each remaining day of the week
        for dayOffset in 0...progress.daysRemainingInWeek {
            guard scheduled < budget else { break }
            guard let notifDate = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }

            if dayOffset == 0 {
                let currentHour = cal.component(.hour, from: Date())
                if currentHour >= hour { continue }
            }

            let stage = computeFrequencyStage(progress: progress, dayOffset: dayOffset)
            let message = frequencyMessage(stage: stage, progress: progress)

            var comps = cal.dateComponents([.year, .month, .day], from: notifDate)
            comps.hour = hour
            comps.minute = 0

            NotificationManager.scheduleGoalNotification(
                identifier: "shift.frequency-\(dayOffset)",
                title: message.title,
                body: message.body,
                at: comps
            )
            scheduled += 1
        }

        return scheduled
    }

    private static func computeFrequencyStage(
        progress: FrequencyProgress,
        dayOffset: Int
    ) -> FrequencyStage {
        let completed = progress.completed
        let target = progress.target

        if completed >= target {
            return completed > target ? .exceededGoal : .hitGoal
        }

        let effectiveDay = progress.dayOfWeek + dayOffset
        let daysLeft = max(0, 7 - effectiveDay)
        let remaining = target - completed

        if daysLeft == 0 {
            return completed >= target ? .hitGoal : .missedGoal
        }

        // Running out of time: remaining workouts >= remaining days
        if remaining >= daysLeft {
            return .runningOutOfTime
        }

        return .behindPace
    }

    // MARK: - Frequency Stages

    enum FrequencyStage {
        case behindPace
        case runningOutOfTime
        case missedGoal
        case hitGoal
        case exceededGoal
    }

    // MARK: - Message Variants

    private struct Message {
        let title: String
        let body: String
    }

    /// Picks a message variant using a date-based hash so it's deterministic per day
    /// but varies across days.
    private static func pickVariant<T>(_ variants: [T]) -> T {
        let daysSinceEpoch = Int(Date().timeIntervalSince1970) / 86400
        return variants[abs(daysSinceEpoch) % variants.count]
    }

    // MARK: Exercise goal messages

    private static func exerciseGoalMessage(daysRemaining: Int) -> Message {
        if daysRemaining <= 1 {
            return pickVariant([
                Message(title: "Final push", body: "Your goal deadline is tomorrow. Time to lock in that lift."),
                Message(title: "One day left", body: "Your weight goal is due tomorrow. Give it everything you've got."),
                Message(title: "Now or never", body: "Tomorrow's the deadline. Hit the gym and crush that target."),
                Message(title: "Last chance", body: "Your goal expires tomorrow. Make today's session count."),
                Message(title: "Deadline day", body: "Your weight target is almost due. You've trained for this.")
            ])
        } else if daysRemaining <= 3 {
            return pickVariant([
                Message(title: "Goal check-in", body: "Only \(daysRemaining) days left to hit your weight target. Stay focused."),
                Message(title: "Almost there", body: "\(daysRemaining) days until your deadline. Keep pushing those limits."),
                Message(title: "Crunch time", body: "Your goal is \(daysRemaining) days away. Every rep counts now."),
                Message(title: "Close to the finish", body: "\(daysRemaining) days left. Trust your training and go heavy."),
                Message(title: "Countdown", body: "\(daysRemaining) days to hit your target. Time to dial in.")
            ])
        } else {
            return pickVariant([
                Message(title: "Stay on track", body: "You've got \(daysRemaining) days left on your goal. Keep building."),
                Message(title: "Goal reminder", body: "\(daysRemaining) days until your deadline. Consistent work pays off."),
                Message(title: "Keep it moving", body: "Your weight target is \(daysRemaining) days out. Stay the course."),
                Message(title: "Progress check", body: "How's the goal coming? \(daysRemaining) days to go. Keep grinding."),
                Message(title: "Eye on the prize", body: "\(daysRemaining) days left. Every session gets you closer.")
            ])
        }
    }

    // MARK: Frequency messages

    private static func frequencyMessage(stage: FrequencyStage, progress: FrequencyProgress) -> Message {
        let c = progress.completed
        let t = progress.target
        let left = t - c

        switch stage {
        case .behindPace:
            return pickVariant([
                Message(title: "Keep it up!", body: "You've trained \(c)/\(t) times this week. You've got this."),
                Message(title: "Stay on track", body: "You're at \(c)/\(t) sessions. A great workout is waiting."),
                Message(title: "Room to grow", body: "\(c) down, \(left) to go this week. Let's make it happen."),
                Message(title: "Build the habit", body: "\(c)/\(t) sessions done. Keep the momentum going."),
                Message(title: "Consistency wins", body: "\(c)/\(t) this week. Every session counts.")
            ])

        case .runningOutOfTime:
            return pickVariant([
                Message(title: "Time's ticking", body: "You've trained \(c)/\(t) times and the week is almost over. Let's go."),
                Message(title: "Don't let it slip", body: "Only \(progress.daysRemainingInWeek) days left to hit \(t) sessions. You can still make it."),
                Message(title: "Crunch time", body: "\(c)/\(t) sessions with \(progress.daysRemainingInWeek) days left. Time to lock in."),
                Message(title: "Almost out of time", body: "The week's wrapping up — \(left) more session\(left == 1 ? "" : "s") to hit your goal."),
                Message(title: "Now or never", body: "\(progress.daysRemainingInWeek) days left, \(left) session\(left == 1 ? "" : "s") to go. You've got this.")
            ])

        case .missedGoal:
            return pickVariant([
                Message(title: "Fresh start ahead", body: "You hit \(c)/\(t) this week. Reset and come back stronger."),
                Message(title: "It's all good", body: "\(c)/\(t) this week — not quite there, but next week is a clean slate."),
                Message(title: "Keep going", body: "You made it \(c) time\(c == 1 ? "" : "s") this week. Progress isn't always linear."),
                Message(title: "Bounce back", body: "Missed the target this week, but showing up \(c) time\(c == 1 ? "" : "s") still matters."),
                Message(title: "New week, new chance", body: "\(c)/\(t) this week. Dust yourself off and go again.")
            ])

        case .hitGoal:
            return pickVariant([
                Message(title: "Goal crushed!", body: "You hit \(t)/\(t) sessions this week. Incredible work."),
                Message(title: "Nailed it", body: "\(t) sessions done. You set a goal and you smashed it."),
                Message(title: "Target hit!", body: "You've completed your weekly goal. That's discipline right there."),
                Message(title: "Well done!", body: "\(t)/\(t) sessions. You showed up when it mattered."),
                Message(title: "Consistency king", body: "Weekly goal: achieved. Keep this energy going.")
            ])

        case .exceededGoal:
            return pickVariant([
                Message(title: "Above and beyond", body: "\(c) sessions this week — that's \(c - t) more than your target. Beast mode."),
                Message(title: "Overachiever!", body: "You went \(c - t) over your \(t)-session goal. Unstoppable."),
                Message(title: "Extra credit", body: "\(c)/\(t) sessions — you're not just meeting goals, you're shattering them."),
                Message(title: "On fire", body: "\(c) sessions this week when you aimed for \(t). That's elite dedication."),
                Message(title: "Can't be stopped", body: "Goal was \(t), you did \(c). That's how champions train.")
            ])
        }
    }

    // MARK: - Step Goal Reminders

    private static func scheduleStepGoalReminders(
        stepGoal: Int,
        hour: Int,
        budget: Int
    ) async -> Int {
        guard budget > 0 else { return 0 }
        var scheduled = 0

        // Schedule a daily evening check (at 8pm) to remind if behind
        let formattedGoal = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter.string(from: NSNumber(value: stepGoal)) ?? "\(stepGoal)"
        }()

        // Evening reminder at 8pm — "you still have time"
        for dayOffset in 0..<min(7, budget / 2) {
            var eveningComponents = DateComponents()
            eveningComponents.hour = 20
            eveningComponents.minute = 0
            if dayOffset > 0 {
                let futureDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
                let cal = Calendar.current
                eveningComponents.year = cal.component(.year, from: futureDate)
                eveningComponents.month = cal.component(.month, from: futureDate)
                eveningComponents.day = cal.component(.day, from: futureDate)
            }

            let eveningMsg = stepReminderMessage(goal: formattedGoal)
            NotificationManager.scheduleGoalNotification(
                identifier: "shift.steps-remind-\(dayOffset)",
                title: eveningMsg.title,
                body: eveningMsg.body,
                at: eveningComponents
            )
            scheduled += 1

            // Morning congratulations check at notification hour
            var morningComponents = DateComponents()
            morningComponents.hour = hour
            morningComponents.minute = 0
            if dayOffset > 0 {
                let futureDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
                let cal = Calendar.current
                morningComponents.year = cal.component(.year, from: futureDate)
                morningComponents.month = cal.component(.month, from: futureDate)
                morningComponents.day = cal.component(.day, from: futureDate)
            }

            let congratsMsg = stepCongratsMessage(goal: formattedGoal)
            NotificationManager.scheduleGoalNotification(
                identifier: "shift.steps-congrats-\(dayOffset)",
                title: congratsMsg.title,
                body: congratsMsg.body,
                at: morningComponents
            )
            scheduled += 1
        }

        return scheduled
    }

    // MARK: Step goal messages

    private static func stepReminderMessage(goal: String) -> Message {
        pickVariant([
            Message(title: "Steps check", body: "Have you hit \(goal) steps today? There's still time to get moving."),
            Message(title: "Get those steps in", body: "Your \(goal)-step goal is waiting. A quick walk could close the gap."),
            Message(title: "Almost bedtime", body: "Check your step count — you might be closer to \(goal) than you think."),
            Message(title: "Evening walk?", body: "Still time to hit your \(goal)-step target. Even a short walk helps."),
            Message(title: "Don't forget", body: "Your daily step goal is \(goal). Lace up and finish strong.")
        ])
    }

    private static func stepCongratsMessage(goal: String) -> Message {
        pickVariant([
            Message(title: "Steps crushed!", body: "You hit your \(goal)-step goal yesterday. Keep that momentum going."),
            Message(title: "Goal achieved", body: "You reached \(goal) steps. That's consistency right there."),
            Message(title: "Walking warrior", body: "Yesterday's step goal: smashed. Let's do it again today."),
            Message(title: "Nice work", body: "You nailed your \(goal)-step target. Every step adds up."),
            Message(title: "On a roll", body: "Step goal hit. Keep stacking those active days.")
        ])
    }

    // MARK: - Activity Ring Reminders

    private static func scheduleActivityRingReminders(budget: Int) async -> Int {
        guard budget > 0 else { return 0 }
        var scheduled = 0

        // Schedule evening reminders + morning congrats for each ring for the next 7 days
        // Each day uses 6 slots: 3 reminders + 3 congrats
        for dayOffset in 0..<min(7, budget / 6) {
            let cal = Calendar.current

            // Evening reminders at 8:30pm, 8:35pm, 8:40pm
            var components = DateComponents()
            components.hour = 20
            components.minute = 30
            if dayOffset > 0 {
                let futureDate = cal.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
                components.year = cal.component(.year, from: futureDate)
                components.month = cal.component(.month, from: futureDate)
                components.day = cal.component(.day, from: futureDate)
            }

            let moveMsg = ringReminderMessage(ring: "Move")
            NotificationManager.scheduleGoalNotification(
                identifier: "shift.rings-move-\(dayOffset)",
                title: moveMsg.title,
                body: moveMsg.body,
                at: components
            )
            scheduled += 1

            var exerciseComponents = components
            exerciseComponents.minute = 35
            let exerciseMsg = ringReminderMessage(ring: "Exercise")
            NotificationManager.scheduleGoalNotification(
                identifier: "shift.rings-exercise-\(dayOffset)",
                title: exerciseMsg.title,
                body: exerciseMsg.body,
                at: exerciseComponents
            )
            scheduled += 1

            var standComponents = components
            standComponents.minute = 40
            let standMsg = ringReminderMessage(ring: "Stand")
            NotificationManager.scheduleGoalNotification(
                identifier: "shift.rings-stand-\(dayOffset)",
                title: standMsg.title,
                body: standMsg.body,
                at: standComponents
            )
            scheduled += 1

            // Morning congrats at 9:00am, 9:05am, 9:10am (next day for dayOffset 0)
            let congratsDayOffset = dayOffset + 1
            let congratsDate = cal.date(byAdding: .day, value: congratsDayOffset, to: Date()) ?? Date()

            var moveCongrats = DateComponents()
            moveCongrats.hour = 9
            moveCongrats.minute = 0
            moveCongrats.year = cal.component(.year, from: congratsDate)
            moveCongrats.month = cal.component(.month, from: congratsDate)
            moveCongrats.day = cal.component(.day, from: congratsDate)

            let moveCongratsMsg = ringCongratsMessage(ring: "Move")
            NotificationManager.scheduleGoalNotification(
                identifier: "shift.rings-move-congrats-\(dayOffset)",
                title: moveCongratsMsg.title,
                body: moveCongratsMsg.body,
                at: moveCongrats
            )
            scheduled += 1

            var exerciseCongrats = moveCongrats
            exerciseCongrats.minute = 5
            let exerciseCongratsMsg = ringCongratsMessage(ring: "Exercise")
            NotificationManager.scheduleGoalNotification(
                identifier: "shift.rings-exercise-congrats-\(dayOffset)",
                title: exerciseCongratsMsg.title,
                body: exerciseCongratsMsg.body,
                at: exerciseCongrats
            )
            scheduled += 1

            var standCongrats = moveCongrats
            standCongrats.minute = 10
            let standCongratsMsg = ringCongratsMessage(ring: "Stand")
            NotificationManager.scheduleGoalNotification(
                identifier: "shift.rings-stand-congrats-\(dayOffset)",
                title: standCongratsMsg.title,
                body: standCongratsMsg.body,
                at: standCongrats
            )
            scheduled += 1
        }

        return scheduled
    }

    private static func ringReminderMessage(ring: String) -> Message {
        switch ring {
        case "Move":
            return pickVariant([
                Message(title: "Close your Move ring", body: "Still have calories to burn today. A quick workout or walk could do it."),
                Message(title: "Move ring check", body: "Have you closed your Move ring? There's still time to get active."),
                Message(title: "Keep moving", body: "Your Move ring is waiting to be closed. Even a short burst helps."),
                Message(title: "Burn it up", body: "Don't let today's Move goal slip away. Get those calories in."),
                Message(title: "Almost there?", body: "Check your Move ring — you might be closer than you think.")
            ])
        case "Exercise":
            return pickVariant([
                Message(title: "Exercise ring", body: "Have you hit 30 minutes of exercise today? Time to get moving."),
                Message(title: "Get your workout in", body: "Your Exercise ring needs attention. Even a brisk walk counts."),
                Message(title: "30 minutes", body: "That's all it takes to close your Exercise ring. You've got this."),
                Message(title: "Exercise check", body: "Don't forget your daily exercise. Your ring is counting on you."),
                Message(title: "Time to train", body: "Your Exercise ring won't close itself. Lace up and go.")
            ])
        default:
            return pickVariant([
                Message(title: "Stand up", body: "Have you stood for enough hours today? A quick stretch goes a long way."),
                Message(title: "Stand ring", body: "Check your Stand ring — getting up and moving for a minute counts."),
                Message(title: "On your feet", body: "Your Stand ring needs a few more hours. Take a break and stand up."),
                Message(title: "Break time", body: "Stand up and stretch. Your Stand ring will thank you."),
                Message(title: "Stand check", body: "How's your Stand ring looking? A minute on your feet is all it takes.")
            ])
        }
    }

    // MARK: Ring congrats messages

    private static func ringCongratsMessage(ring: String) -> Message {
        switch ring {
        case "Move":
            return pickVariant([
                Message(title: "Move ring closed!", body: "You hit your calorie goal yesterday. That's the kind of consistency that builds results."),
                Message(title: "Calories crushed", body: "Move ring: closed. You showed up and put in the work."),
                Message(title: "Move goal smashed", body: "Yesterday's Move ring is done. Keep that fire burning today."),
                Message(title: "Ring closed!", body: "You closed your Move ring. Every calorie burned is progress earned."),
                Message(title: "Active day!", body: "Move ring complete. That's what discipline looks like.")
            ])
        case "Exercise":
            return pickVariant([
                Message(title: "Exercise ring closed!", body: "You hit your exercise minutes yesterday. Strong work."),
                Message(title: "30 minutes done", body: "Exercise ring: closed. You made time for your health and it shows."),
                Message(title: "Workout complete", body: "Yesterday's Exercise ring is sealed. Keep the streak alive."),
                Message(title: "Ring closed!", body: "Exercise goal hit. Showing up every day is what separates you."),
                Message(title: "Exercise crushed", body: "You closed your Exercise ring. That's another win in the books.")
            ])
        default:
            return pickVariant([
                Message(title: "Stand ring closed!", body: "You stayed active throughout the day yesterday. Well done."),
                Message(title: "On your feet", body: "Stand ring: closed. Those breaks add up to better health."),
                Message(title: "Standing strong", body: "Yesterday's Stand ring is complete. Small moves, big impact."),
                Message(title: "Ring closed!", body: "Stand goal hit. Staying mobile throughout the day matters."),
                Message(title: "All stood up", body: "You closed your Stand ring. Keep breaking up those long sits.")
            ])
        }
    }
}
