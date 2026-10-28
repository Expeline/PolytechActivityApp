import Foundation
#if os(iOS)
@preconcurrency import ActivityKit

@MainActor
final class LiveActivityController {
    private var operationID = UUID()
    func sync(lesson: Lesson?, group: StudyGroup, accent: StudyAccent, theme: String,
              enabled: Bool, allowStart: Bool, dataIsFresh: Bool) async -> String? {
        let token = UUID()
        operationID = token
        guard enabled else { await stop(); return nil }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await stop()
            return "Разрешите Live Activities для Политеха в настройках iPhone."
        }
        guard dataIsFresh else {
            await stop()
            return "Для активности обновите расписание через интернет."
        }
        guard let lesson else { await stop(); return nil }
        // ActivityKit limits a session to 8 hours. Do not pin a countdown for a class days away.
        guard lesson.start.timeIntervalSinceNow < 8 * 60 * 60 else {
            await stop()
            return "Активность появится, когда до следующей пары останется меньше 8 часов."
        }
        let state = LessonAttributes.ContentState(subject: lesson.subject, kind: lesson.kind,
            location: lesson.location, start: lesson.start, end: lesson.end, updatedAt: .now,
            ongoing: lesson.start <= .now, accent: accent, theme: theme)
        let content = ActivityContent(state: state, staleDate: lesson.end)
        let activities = Activity<LessonAttributes>.activities
        if let current = activities.first(where: { $0.attributes.groupName == group.name }) {
            for extra in activities where extra.id != current.id { await extra.end(nil, dismissalPolicy: .immediate) }
            guard operationID == token else { return nil }
            let old = current.content.state
            if old.subject != state.subject || old.start != state.start || old.end != state.end
                || old.location != state.location || old.ongoing != state.ongoing
                || old.accent != state.accent || old.theme != state.theme {
                await current.update(content)
            }
            return nil
        }
        await endAll()
        guard operationID == token, allowStart else { return nil }
        do {
            _ = try Activity.request(attributes: LessonAttributes(groupName: group.name), content: content, pushType: nil)
            return nil
        } catch { return "Не удалось запустить активность: \(error.localizedDescription)" }
    }

    func stop() async {
        operationID = UUID()
        await endAll()
    }

    private func endAll() async {
        for activity in Activity<LessonAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
#else
// macOS presents the same lesson in a native MenuBarExtra, without ActivityKit.
@MainActor
final class LiveActivityController {
    func sync(lesson: Lesson?, group: StudyGroup, accent: StudyAccent, theme: String,
              enabled: Bool, allowStart: Bool, dataIsFresh: Bool) async -> String? { nil }
    func stop() async {}
}
#endif
