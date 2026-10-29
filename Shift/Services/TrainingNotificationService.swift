import Foundation
import UserNotifications

struct TrainingReminder: Equatable {
    var sessionID: String
    var fireAt: Date
}
enum TrainingReminderPolicy {
    static func reminders(sessions: [TrainingSession], userID: String, completedIDs: Set<String>, leadMinutes: Int, now: Date, limit: Int = 24) -> [TrainingReminder] {
        guard [15, 30, 60].contains(leadMinutes), limit > 0 else { return [] }
        return Array(sessions.filter { $0.userId == userID && $0.status == .scheduled && !completedIDs.contains($0.id) }
            .map { TrainingReminder(sessionID: $0.id, fireAt: $0.scheduledAt.addingTimeInterval(-Double(leadMinutes * 60))) }
            .filter { $0.fireAt > now }.sorted { $0.fireAt < $1.fireAt }.prefix(limit))
    }
}

@MainActor
enum TrainingNotificationService {
    private static let center = UNUserNotificationCenter.current()
    private static let prefix = "shift.training.reminder."
    private static var generation = UUID()

    static func reconcile() async {
        let pass = UUID(); generation = pass
        guard let owner = authManager.currentUserId else { return }
        let settings = (try? await ProfileRepository.findById(owner))?.settings ?? authManager.user?.settings ?? .default
        let pending = await center.pendingNotificationRequests()
        guard generation == pass, authManager.currentUserId == owner else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix(prefix + owner + ".") }.map(\.identifier))
        guard settings.notifications.trainingReminders, await NotificationManager.permissionState() == .enabled else { return }
        do {
            async let planned = EnduranceStore.shared.all(TrainingSession.self, userID: owner)
            async let activities = EnduranceStore.shared.all(EnduranceActivity.self, userID: owner)
            async let workouts = SessionRepository.findCompleted(userId: owner)
            async let inProgress = SessionRepository.findInProgress(userId: owner)
            async let draft = EnduranceStore.shared.draft(userID: owner)
            let (sessions, completed, strength, active, recording) = try await (planned, activities, workouts, inProgress, draft)
            let completedIDs = Set(completed.compactMap(\.trainingSessionID)).union(strength.map(\.id)).union(active.map(\.id)).union([recording?.trainingSessionID].compactMap { $0 })
            let reminders = TrainingReminderPolicy.reminders(sessions: sessions, userID: owner, completedIDs: completedIDs,
                leadMinutes: settings.notifications.trainingReminderMinutes, now: Date())
            for reminder in reminders {
                guard generation == pass, authManager.currentUserId == owner else { return }
                guard let item = sessions.first(where: { $0.id == reminder.sessionID }), reminder.fireAt > Date() else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Your session starts soon"
                content.body = "\(item.title) · in \(settings.notifications.trainingReminderMinutes) minutes"
                content.sound = .default
                content.userInfo = ["shiftNotificationKind": "training", "ownerId": owner,
                    "trainingDate": TrainingScheduleSettings.dateKey(item.scheduledAt), "trainingSessionId": item.id]
                let id = prefix + owner + "." + pass.uuidString + "." + item.id
                var parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireAt)
                parts.timeZone = Calendar.current.timeZone
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
                if generation != pass || authManager.currentUserId != owner { center.removePendingNotificationRequests(withIdentifiers: [id]); return }
            }
        } catch { print("[Training reminders] Could not schedule: \(error.localizedDescription)") }
    }
    static func clear(userID: String?) async {
        generation = UUID()
        guard let userID else { return }
        await NotificationManager.removeNotifications(withPrefixes: [prefix + userID + ".", "shift.endurance.achievement." + userID + "."])
    }
    static func activitySaved(_ activity: EnduranceActivity, before: [EnduranceActivity]) async {
        guard activity.userId == authManager.currentUserId,
              EnduranceAchievementPolicy.shouldCelebrate(activity, previousIDs: Set(before.map(\.id))) else { return }
        let owner = activity.userId
        let settings = (try? await ProfileRepository.findById(owner))?.settings ?? authManager.user?.settings ?? .default
        guard settings.notifications.enduranceAchievements else { return }
        let all = before + [activity]
        let prior = EnduranceInsights.records(before, userID: owner)
        let bests = EnduranceInsights.records(all, userID: owner).filter { next in
            guard next.activityID == activity.id else { return false }
            guard let old = prior.first(where: { $0.id == next.id }) else { return true }
            return next.isTime ? next.value < old.value : next.value > old.value
        }
        let goals = (try? await EnduranceStore.shared.all(EnduranceGoal.self, userID: owner)) ?? []
        var calendar = Calendar.current; calendar.firstWeekday = settings.weekStartsOn == "sunday" ? 1 : 2
        let achieved = goals.filter { $0.progress(in: before, calendar: calendar) < $0.target && $0.progress(in: all, calendar: calendar) >= $0.target }.sorted { $0.id < $1.id }
        let priorMilestones = Set(EnduranceInsights.milestones(before, userID: owner))
        let milestones = EnduranceInsights.milestones(all, userID: owner).filter { !priorMilestones.contains($0) }
        guard !bests.isEmpty || !achieved.isEmpty || !milestones.isEmpty, owner == authManager.currentUserId else { return }
        let title = !achieved.isEmpty ? "Endurance goal reached" : !milestones.isEmpty ? "A new milestone" : "New personal best"
        let body = [achieved.isEmpty ? nil : "\(achieved.count) \(achieved.count == 1 ? "goal" : "goals") completed",
            bests.first?.title, milestones.first].compactMap { $0 }.joined(separator: " · ")
        let event: String
        if let goal = achieved.first { event = "goal.\(goal.id).\(goal.interval(at: Date(), calendar: calendar)?.start.timeIntervalSince1970 ?? 0)" }
        else { event = "activity.\(activity.id)" }
        _ = await NotificationEventLedger.shared.deliverOnce(eventKey: owner + ".endurance." + event,
            identifier: "shift.endurance.achievement." + owner + "." + activity.id, title: title, body: body, kind: "achievement",
            userInfo: ["ownerId": owner, "enduranceActivityId": activity.id])
    }
}
