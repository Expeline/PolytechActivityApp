import BackgroundTasks
import SwiftUI

@main
struct PolytechApp: App {
    @State private var store = ScheduleStore()
    @Environment(\.scenePhase) private var scenePhase
    private static let backgroundID = "ru.polytech.schedule.refresh"

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .studyAppearance(store)
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .environment(\.timeZone, StudyClock.calendar.timeZone)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { Task { await scheduleRefresh() } }
                }
        }
        .backgroundTask(.appRefresh(Self.backgroundID)) {
            await store.refresh(allowActivityStart: false)
            await store.study.sync()
            store.study.stopLive()
            await scheduleRefresh()
        }
    }

    private func scheduleRefresh() async {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundID)
        let lesson = store.activityLesson()
        let next = lesson.map { $0.start <= .now ? $0.end : $0.start } ?? Date.now.addingTimeInterval(3600)
        request.earliestBeginDate = max(Date.now.addingTimeInterval(60), next)
        try? await BGTaskScheduler.shared.submitTaskRequest(request)
    }
}

struct RootView: View {
    @Bindable var store: ScheduleStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScheduleView(store: store)
        .task(id: "\(store.group.id)-\(store.key(store.selectedDate))-\(scenePhase)") {
            guard scenePhase == .active else { store.study.stopLive(); return }
            await store.syncActivity()
            await store.refresh()
            await store.study.sync()
            var lastRefresh = Date.now
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                if Date.now.timeIntervalSince(lastRefresh) >= 900 {
                    await store.refresh()
                    await store.study.sync()
                    lastRefresh = .now
                } else { await store.syncActivity() }
            }
        }
        .onChange(of: store.preferences) { _, _ in Task { await store.syncActivity() } }
        .onChange(of: store.liveEnabled) { _, _ in Task { await store.syncActivity() } }
        .onChange(of: store.accent) { _, _ in Task { await store.syncActivity() } }
        .onChange(of: store.theme) { _, _ in Task { await store.syncActivity() } }
        .onOpenURL { url in
            store.selectedDate = StudyClock.calendar.startOfDay(for: .now)
            if url.host == "finish-day" { Task { await store.finishDay() } }
            else { Task { await store.refresh() } }
        }
    }
}
