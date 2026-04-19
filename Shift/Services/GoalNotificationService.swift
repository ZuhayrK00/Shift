import Foundation
import UserNotifications

// MARK: - GoalNotificationService

enum GoalNotificationService {

    // MARK: - Public

    /// Clears all existing goal notifications and reschedules based on current state.
    /// Called on app launch, after finishing a workout, and after goal changes.
    static func scheduleAllNotifications() async {
        // Read settings from auth manager, or fall back to local profile cache
        // (auth manager may not be fully loaded when woken in the background by HealthKit)
        let settings: UserSettings
        if let userSettings = authManager.user?.settings {
            settings = userSettings
        } else if let userId = authManager.currentUserId,
                  let profile = try? await ProfileRepository.findById(userId) {
            settings = profile.settings
        } else {
            settings = .default
        }

        // Clear existing
        NotificationManager.cancelNotifications(withPrefix: "shift.exercise-goal-")
        NotificationManager.cancelNotifications(withPrefix: "shift.frequency-")
        NotificationManager.cancelNotifications(withPrefix: "shift.steps-")
        NotificationManager.cancelNotifications(withPrefix: "shift.progress-")

        guard let userId = authManager.currentUserId else { return }

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

        // Step goal reminders (separate toggle from frequency reminders)
        if settings.notifications.stepGoalReminders, let stepGoal = settings.dailyStepGoal, stepGoal > 0 {
            scheduledCount += await scheduleStepGoalReminders(
                stepGoal: stepGoal,
                hour: notificationHour,
                budget: maxNotifications - scheduledCount
            )
        }

        // Progress tracking reminders (measurements & photos)
        if settings.notifications.progressReminders {
            scheduledCount += await scheduleProgressReminders(
                userId: userId,
                hour: notificationHour,
                budget: maxNotifications - scheduledCount
            )
        }
    }

    /// Checks current HealthKit data and fires immediate congrats / cancels stale reminders.
    /// Called on every app foreground event and from HealthKit background delivery.
    static func checkAndNotifyGoalCompletion() async {
        // Read settings from auth manager, or fall back to local profile cache
        // (auth manager may not be loaded when woken in the background by HealthKit)
        let settings: UserSettings
        if let userSettings = authManager.user?.settings {
            settings = userSettings
        } else if let userId = authManager.currentUserId,
                  let profile = try? await ProfileRepository.findById(userId) {
            settings = profile.settings
        } else {
            settings = .default
        }
        guard HealthKitService.isAvailable else { return }

        // Fetch today's activity
        guard let activity = await HealthKitService.fetchTodayActivity() else { return }

        // Check step goal (only if step notifications are enabled)
        if settings.notifications.stepGoalReminders,
           let stepGoal = settings.dailyStepGoal, stepGoal > 0, activity.steps >= stepGoal {
            // Cancel today's evening reminder — already hit
            NotificationManager.cancelNotifications(withPrefix: "shift.steps-remind-0")
            // Fire immediate congrats if not already sent today
            fireOnceToday(
                id: "shift.steps-completed",
                title: "Steps crushed!",
                body: "You hit your \(formatNumber(stepGoal))-step goal. Keep it up!"
            )
        }
    }

    /// Serial queue to prevent concurrent fireOnceToday calls from racing on UserDefaults.
    private static let fireOnceLock = NSLock()

    /// Fires a notification immediately, but only once per calendar day.
    /// Uses UserDefaults to track which notifications were already sent.
    /// Thread-safe: uses a lock to prevent duplicate notifications from concurrent calls.
    private static func fireOnceToday(id: String, title: String, body: String) {
        fireOnceLock.lock()
        defer { fireOnceLock.unlock() }

        let todayKey = toLocalDateKey(Date())
        let fullId = "\(id)-\(todayKey)"

        // Check if we already fired this notification today
        let sentKey = "shift.notification.sent.\(fullId)"
        guard !UserDefaults.standard.bool(forKey: sentKey) else { return }

        // Mark as sent BEFORE scheduling to prevent duplicates
        UserDefaults.standard.set(true, forKey: sentKey)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: fullId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)

        // Clean up old sent keys from previous days
        cleanupOldSentKeys(currentKey: todayKey, prefix: id)
    }

    /// Removes sent-tracking keys from previous days to prevent UserDefaults bloat.
    private static func cleanupOldSentKeys(currentKey: String, prefix: String) {
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        let oldKeys = allKeys.filter {
            $0.hasPrefix("shift.notification.sent.\(prefix)-") && !$0.hasSuffix(currentKey)
        }
        for key in oldKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
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

        let formattedGoal = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter.string(from: NSNumber(value: stepGoal)) ?? "\(stepGoal)"
        }()

        // Check if today's goal is already hit — skip today's reminder if so
        let todayAlreadyHit: Bool
        if let activity = await HealthKitService.fetchTodayActivity() {
            todayAlreadyHit = activity.steps >= stepGoal
        } else {
            todayAlreadyHit = false
        }

        // Evening reminder at 8pm — "you still have time"
        // Only schedule for days when the goal hasn't been reached yet.
        // Real-time congrats are handled by checkAndNotifyGoalCompletion
        // via HealthKit background delivery — no pre-scheduled congrats needed.
        let cal = Calendar.current
        for dayOffset in 0..<min(7, budget) {
            // Skip today's reminder if already hit
            if dayOffset == 0 && todayAlreadyHit { continue }
            // Skip today if it's already past 8pm
            if dayOffset == 0 && cal.component(.hour, from: Date()) >= 20 { continue }

            let targetDate = cal.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            var comps = DateComponents()
            comps.year = cal.component(.year, from: targetDate)
            comps.month = cal.component(.month, from: targetDate)
            comps.day = cal.component(.day, from: targetDate)
            comps.hour = 20
            comps.minute = 0

            let msg = stepReminderMessage(goal: formattedGoal)
            NotificationManager.scheduleGoalNotification(
                identifier: "shift.steps-remind-\(dayOffset)",
                title: msg.title,
                body: msg.body,
                at: comps
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

    // MARK: - Progress Tracking Reminders

    /// Schedules a reminder if the user hasn't logged measurements or photos recently.
    /// Checks the most recent measurement and photo date; if both are older than 7 days
    /// (or never logged), schedules a nudge for 3 days from now to give them time.
    private static func scheduleProgressReminders(
        userId: String,
        hour: Int,
        budget: Int
    ) async -> Int {
        guard budget > 0 else { return 0 }

        let lastMeasurement = try? await BodyMeasurementRepository.findMostRecentDate(userId: userId)
        let lastPhoto = try? await ProgressPhotoRepository.findMostRecentDate(userId: userId)

        // Use the more recent of the two as the "last progress update"
        let lastUpdate: Date? = [lastMeasurement, lastPhoto].compactMap { $0 }.max()

        let cal = Calendar.current
        let now = Date()

        // If they logged something within the last 7 days, no reminder needed
        if let lastUpdate, cal.dateComponents([.day], from: lastUpdate, to: now).day ?? 0 < 7 {
            return 0
        }

        // Schedule a reminder 3 days from now (gives breathing room, not immediately nagging)
        // If they've never logged anything, remind in 3 days (gentle onboarding nudge)
        let daysOut = 3
        guard let notifDate = cal.date(byAdding: .day, value: daysOut, to: cal.startOfDay(for: now)) else {
            return 0
        }

        var comps = cal.dateComponents([.year, .month, .day], from: notifDate)
        comps.hour = hour
        comps.minute = 0

        let msg: Message
        if lastUpdate == nil {
            // Never logged — onboarding nudge
            msg = pickVariant([
                Message(title: "Track your progress", body: "Log a measurement or snap a progress photo to start tracking your transformation."),
                Message(title: "Start tracking", body: "Measurements and photos help you see changes you can't feel day to day."),
                Message(title: "See your progress", body: "Add your first body measurement or progress photo — future you will thank you.")
            ])
        } else {
            // Haven't logged in a while
            let daysSince = cal.dateComponents([.day], from: lastUpdate!, to: now).day ?? 7
            msg = pickVariant([
                Message(title: "Progress check-in", body: "It's been \(daysSince) days since your last update. Time to log a measurement or photo."),
                Message(title: "Update your progress", body: "Your last measurement was \(daysSince) days ago. A quick update keeps you on track."),
                Message(title: "How's the progress?", body: "Haven't logged in \(daysSince) days. Take a moment to track where you're at."),
                Message(title: "Time for an update", body: "Regular tracking reveals trends you'd otherwise miss. Log a quick measurement today."),
                Message(title: "Stay consistent", body: "\(daysSince) days since your last progress entry. Consistency is key to seeing results.")
            ])
        }

        NotificationManager.scheduleGoalNotification(
            identifier: "shift.progress-remind",
            title: msg.title,
            body: msg.body,
            at: comps
        )

        return 1
    }

    // MARK: Progress messages (used by scheduleProgressReminders above)

}
