import Foundation
@preconcurrency import UserNotifications

/// Local notifications only: a free developer account cannot use push (APNs).
enum StudyNotifications {
    private static let deadlinePrefix = "deadline-"

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// Announces changes to lessons in the coming week right away.
    static func announce(_ changes: [ScheduleChange], now: Date = .now) async {
        let soon = changes.filter { $0.relevantStart > now && $0.relevantStart < now.addingTimeInterval(7 * 86_400) }
        guard !soon.isEmpty, await requestPermission() else { return }
        let center = UNUserNotificationCenter.current()
        for change in soon.prefix(5) {
            let content = UNMutableNotificationContent()
            content.title = "\(change.kind.title): \(change.subject)"
            content.body = describe(change)
            content.sound = .default
            content.threadIdentifier = "schedule-changes"
            try? await center.add(UNNotificationRequest(identifier: "change-\(change.fingerprint)", content: content, trigger: nil))
        }
        if soon.count > 5 {
            let content = UNMutableNotificationContent()
            content.title = "Расписание изменилось"
            content.body = "Ещё \(soon.count - 5) изменений. Откройте «Изменения» в Политехе."
            content.threadIdentifier = "schedule-changes"
            try? await center.add(UNNotificationRequest(identifier: "change-more-\(Int(now.timeIntervalSince1970))", content: content, trigger: nil))
        }
    }

    static func describe(_ change: ScheduleChange) -> String {
        func when(_ slot: LessonSlot) -> String { "\(StudyClock.string(slot.start, format: "EE, d MMM")) \(slot.timeRange)" }
        switch change.kind {
        case .moved:
            guard let old = change.old, let new = change.new else { return "" }
            return "\(when(old)) → \(when(new)), \(new.location)"
        case .cancelled: return change.old.map { "Не будет: \(when($0))" } ?? ""
        case .added: return change.new.map { "\(when($0)), \($0.location)" } ?? ""
        case .roomChanged: return change.new.map { "\(when($0)): \(change.old?.location ?? "") → \($0.location)" } ?? ""
        case .teacherChanged:
            return change.new.map { "\(when($0)): \($0.teachers.joined(separator: ", "))" } ?? ""
        }
    }

    /// Replaces all deadline reminders: a day and three hours before each open assignment.
    static func scheduleDeadlines(_ assignments: [AssignmentDTO], enabled: Bool, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(deadlinePrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let open = assignments.filter { !$0.completedByMe && $0.deletedAt == nil && $0.dueAt > now }.sorted { $0.dueAt < $1.dueAt }
        guard enabled, !open.isEmpty, await requestPermission() else { return }
        var budget = 40 // iOS keeps at most 64 pending notifications per app.
        for item in open {
            for (offset, label) in [(86_400.0, "Завтра"), (3 * 3_600.0, "Через 3 часа")] {
                let fire = item.dueAt.addingTimeInterval(-offset)
                guard fire > now, budget > 0 else { continue }
                budget -= 1
                let content = UNMutableNotificationContent()
                content.title = "\(label) срок: \(item.title)"
                content.body = "\(item.subject) · до \(StudyClock.string(item.dueAt, format: "d MMM, HH:mm"))"
                content.sound = .default
                content.threadIdentifier = "deadlines"
                // An interval, not calendar components: those would be read in the device's time zone.
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fire.timeIntervalSince(now)), repeats: false)
                try? await center.add(UNNotificationRequest(identifier: "\(deadlinePrefix)\(item.id)-\(Int(offset))", content: content, trigger: trigger))
            }
        }
    }
}
