import EventKit
import Foundation
import Combine

// MARK: - EventKitManager

/// Manages calendar access via EventKit for meeting-related health insights.
class EventKitManager: ObservableObject {

    // MARK: - Singleton

    static let shared = EventKitManager()

    // MARK: - Properties

    private let store = EKEventStore()

    private init() {}

    // MARK: - Authorization

    /// Requests full access to calendar events (iOS 17+).
    func requestAuthorization() async throws {
        let granted = try await store.requestFullAccessToEvents()
        guard granted else {
            throw EventKitError.accessDenied
        }
    }

    // MARK: - Fetch Events

    /// Fetches all calendar events for the given day.
    /// - Parameter date: Any date within the desired day.
    /// - Returns: An array of `CalendarEvent` for that day.
    func fetchEvents(for date: Date) async throws -> [CalendarEvent] {
        let calendar = Calendar.current
        guard let startOfDay = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date),
              let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        return ekEvents.map { event in
            CalendarEvent(
                title: event.title ?? "Untitled",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay
            )
        }
    }

    // MARK: - Meeting Count

    /// Returns the number of meetings overlapping with the given hour on the specified date.
    /// - Parameters:
    ///   - date: Any date within the desired day.
    ///   - hour: The hour (0–23) to check for overlapping meetings.
    /// - Returns: The count of overlapping meetings.
    func meetingCount(for date: Date, hour: Int) async throws -> Int {
        let calendar = Calendar.current
        guard let hourStart = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date),
              let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) else {
            return 0
        }

        let events = try await fetchEvents(for: date)

        return events.filter { event in
            !event.isAllDay && event.startDate < hourEnd && event.endDate > hourStart
        }.count
    }

    // MARK: - Back-to-Back Meetings

    /// Counts meetings that have less than 15 minutes gap between them.
    /// A pair of meetings with <15 min gap counts once per adjacent pair.
    /// - Parameter date: Any date within the desired day.
    /// - Returns: The number of back-to-back meeting pairs.
    func backToBackMeetingCount(for date: Date) async throws -> Int {
        let events = try await fetchEvents(for: date)

        // Filter out all-day events and sort by start date
        let sorted = events
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        guard sorted.count >= 2 else { return 0 }

        let fifteenMinutes: TimeInterval = 15 * 60
        var count = 0

        for i in 0..<(sorted.count - 1) {
            let gap = sorted[i + 1].startDate.timeIntervalSince(sorted[i].endDate)
            if gap < fifteenMinutes {
                count += 1
            }
        }

        return count
    }
}

// MARK: - Errors

enum EventKitError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access was denied. Please enable it in Settings."
        }
    }
}
