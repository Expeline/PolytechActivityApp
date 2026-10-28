import AppKit
import SwiftUI

@main
struct PolytechMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    private var store: ScheduleStore { appDelegate.store }
    @State private var menuVisible = true

    var body: some Scene {
        WindowGroup("Политех", id: "schedule") {
            MacRootView(store: store)
                .studyAppearance(store)
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .environment(\.timeZone, StudyClock.calendar.timeZone)
        }
        .defaultSize(width: 1000, height: 800)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Настройки…") { store.showSettings = true; NSApplication.shared.activate(ignoringOtherApps: true) }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .toolbar) {}
            CommandMenu("Учёба") {
                Button("Завершить учебный день") { Task { await store.finishDay() } }
                Button("Вернуться к занятиям") { Task { await store.resumeDay() } }
                Divider()
                Button("Обновить расписание") { Task { await store.refresh() } }.keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra(isInserted: $menuVisible) {
            MacActivityView(store: store)
                .studyAppearance(store)
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .environment(\.timeZone, StudyClock.calendar.timeZone)
        } label: {
            Label(menuTitle, systemImage: store.liveEnabled && store.activityLesson(at: store.activityDate).map { $0.start <= store.activityDate } == true ? "square.grid.2x2.fill" : "square.grid.2x2")
        }
        .menuBarExtraStyle(.window)
    }

    private var menuTitle: String {
        guard store.liveEnabled, !store.dayFinished, let lesson = store.activityLesson(at: store.activityDate) else { return "Политех" }
        let ongoing = lesson.start <= store.activityDate
        let remaining = Int(ceil((ongoing ? lesson.end : lesson.start).timeIntervalSince(store.activityDate) / 60))
        return "\(ongoing ? "До конца" : "Пара через") \(max(0, remaining)) мин"
    }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    let store = ScheduleStore()
    private var refreshTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshTask = Task { @MainActor [store] in
            await store.refresh()
            var refreshed = Date.now
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                store.activityDate = .now
                if Date.now.timeIntervalSince(refreshed) >= 900 {
                    await store.refresh()
                    refreshed = .now
                }
            }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { refreshTask?.cancel() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct MacRootView: View {
    @Bindable var store: ScheduleStore
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ScheduleView(store: store)
            .frame(minWidth: 560, minHeight: 620)
            .task(id: "\(store.group.id)-\(store.key(store.selectedDate))") { await store.refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh() } } }
            .onOpenURL { _ in store.selectedDate = StudyClock.calendar.startOfDay(for: .now) }
    }
}

struct MacActivityView: View {
    let store: ScheduleStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if store.liveEnabled {
                    NextLessonCard(lesson: store.activityLesson(at: context.date), now: context.date,
                                   available: store.nextWeeksAvailable, finished: store.dayFinished) { _ in showApp() }
                } else {
                    Label("Активность выключена", systemImage: "eye.slash").padding(18)
                }
            }
            if let lesson = store.activityLesson(), lesson.start <= .now, let next = store.nextLesson() {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow(text: "Дальше")
                    Text(next.subject).font(.subheadline.weight(.medium)).lineLimit(2)
                    Text("\(StudyClock.string(next.start, format: "EE, HH:mm")) · \(next.location)")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 8)
            }
            if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Открыть расписание", action: showApp).buttonStyle(.borderedProminent)
                Spacer()
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Обновить расписание").disabled(store.isRefreshing)
            }
            Button(store.dayFinished ? "Возобновить учебный день" : "Завершить учебный день") {
                Task { if store.dayFinished { await store.resumeDay() } else { await store.finishDay() } }
            }.buttonStyle(SoftButton())
            Divider()
            Button("Завершить Политех") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(width: 410).background(Palette.canvas)
    }

    private func showApp() {
        openWindow(id: "schedule")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
