import EventKit
import Foundation

/// A planner-scoped reader. No event titles, locations or attendees leave EventKit.
@MainActor @Observable
final class PlannerCalendarService {
    private let store = EKEventStore()
    var enabled = false
    var requesting = false
    var error: String?

    func connect() async {
        guard !requesting else { return }
        requesting = true
        defer { requesting = false }
        do {
            let granted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
                ? true : try await store.requestFullAccessToEvents()
            enabled = granted
            error = granted ? nil : "Calendar access is off. You can allow it in Settings, or plan using your Shift sessions only."
        } catch {
            enabled = false
            self.error = "Couldn't connect to Calendar. Try again, or continue with your Shift sessions only."
        }
    }

    func disconnect() { enabled = false; error = nil }

    func busyTimes(starting: Date, calendar: Calendar = .current) throws -> [DateInterval] {
        guard enabled else { return [] }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw CalendarError.accessChanged
        }
        let start = calendar.startOfDay(for: starting)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }
        store.refreshSourcesIfNecessary()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let intervals = store.events(matching: predicate).compactMap { event -> DateInterval? in
            guard event.status != .canceled, event.availability != .free,
                  !(event.attendees ?? []).contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }),
                  let eventStart = event.startDate, let eventEnd = event.endDate,
                  eventEnd > eventStart else { return nil }
            return DateInterval(start: eventStart, end: eventEnd)
        }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarError.accessChanged }
        return PlannerTimePolicy.mergedBusyTimes(intervals, within: DateInterval(start: start, end: end))
    }

    enum CalendarError: LocalizedError {
        case accessChanged
        var errorDescription: String? { "Calendar access has changed. Reconnect below, or turn off Calendar checking and find times again." }
    }
}
