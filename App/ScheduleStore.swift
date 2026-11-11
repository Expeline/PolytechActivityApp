import Foundation
import Observation
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor @Observable
final class ScheduleStore {
    var preferences: StudyPreferences {
        didSet { save(preferences, key: "studyPreferences"); publishWidgets() }
    }
    var group: StudyGroup {
        didSet { save(group, key: "group") }
    }
    var iconMessage: String?
    var useAccentIcon: Bool {
        didSet { UserDefaults.standard.set(useAccentIcon, forKey: "useAccentIcon") }
    }
    var widgetSyncFailed = false
    var showSettings = false
    var section: StudySection = .schedule
    let study = StudyStore()
    var accent: StudyAccent {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent"); publishWidgets() }
    }
    var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme"); publishWidgets() }
    }
    var skipMilitary: Bool {
        didSet { UserDefaults.standard.set(skipMilitary, forKey: "skipMilitary") }
    }
    var liveEnabled: Bool {
        didSet { UserDefaults.standard.set(liveEnabled, forKey: "liveEnabled") }
    }
    var activityDate = Date.now
    var selectedDate = StudyClock.calendar.startOfDay(for: .now)
    var isLoading = false
    var errorMessage: String?
    var activityMessage: String?
    var cache: [String: CachedWeek]
    private var normalizedWeeks: [String: [Lesson]] = [:]
    var isRefreshing = false
    let activity = LiveActivityController()
    private let api = ScheduleAPI()
    private var refreshQueued = false
    private var refreshID = UUID()
    private
    
    let cacheURL: URL

    init() {
        let defaults = UserDefaults.standard
        var loadedPreferences = defaults.data(forKey: "studyPreferences").flatMap { try? JSONDecoder().decode(StudyPreferences.self, from: $0) } ?? StudyPreferences()
        if defaults.data(forKey: "studyPreferences") == nil {
            loadedPreferences.skipMilitary = defaults.object(forKey: "skipMilitary") as? Bool ?? true
        }
        preferences = loadedPreferences
        group = defaults.data(forKey: "group").flatMap { try? JSONDecoder().decode(StudyGroup.self, from: $0) } ?? .default
        useAccentIcon = defaults.bool(forKey: "useAccentIcon")
        accent = StudyAccent(rawValue: defaults.string(forKey: "accent") ?? "green") ?? .green
        theme = AppTheme(rawValue: defaults.string(forKey: "theme") ?? "system") ?? .system
        skipMilitary = defaults.object(forKey: "skipMilitary") as? Bool ?? true
        liveEnabled = defaults.object(forKey: "liveEnabled") as? Bool ?? true
        let folder = URL.applicationSupportDirectory.appendingPathComponent("Polytech", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        cacheURL = folder.appendingPathComponent("schedule.json")
        cache = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode([String: CachedWeek].self, from: $0) } ?? [:]
        normalizedWeeks = cache.mapValues { $0.response.lessons }
        study.select(groupID: group.id)
    }

    var weekStart: Date { StudyClock.monday(selectedDate) }
    func key(_ date: Date, groupID: Int? = nil) -> String {
        "\(groupID ?? group.id)-\(StudyClock.string(StudyClock.monday(date), format: "yyyy-MM-dd"))"
    }
    var displayedWeek: CachedWeek? { cache[key(selectedDate)] }
    var dayLessons: [Lesson] {
        (normalizedWeeks[key(selectedDate)] ?? []).filter { StudyClock.calendar.isDate($0.start, inSameDayAs: selectedDate) }
    }
    var upcomingLessons: [Lesson] {
        normalizedWeeks.filter { $0.key.hasPrefix("\(group.id)-") }.flatMap { $0.value }
            .sorted { $0.start < $1.start }
    }
    var dayFinished: Bool { preferences.isFinished(.now, groupID: group.id) }
    func finishDay() async {
        preferences.finishedDays.insert(preferences.dayKey(.now, groupID: group.id))
        await activity.stop()
        publishWidgets()
    }
    func resumeDay() async {
        preferences.finishedDays.remove(preferences.dayKey(.now, groupID: group.id))
        await syncActivity()
    }
    func setRule(_ rule: AttendanceRule, lesson: Lesson, wholeSubject: Bool) {
        if wholeSubject { preferences.subjectRules[lesson.subjectRuleKey(groupID: group.id)] = rule }
        else { preferences.lessonRules[lesson.ruleKey(groupID: group.id)] = rule }
        Task { await syncActivity() }
    }
    func nextLesson(at now: Date = .now) -> Lesson? {
        Lesson.next(in: preferences.eligible(upcomingLessons, groupID: group.id, now: now), after: now, skipMilitary: false)
    }
    func activityLesson(at now: Date = .now) -> Lesson? {
        Lesson.activeOrNext(in: preferences.eligible(upcomingLessons, groupID: group.id, now: now), at: now, skipMilitary: false)
    }
    var loadedWeekCount: Int {
        (0..<preferences.weeksAhead).filter { cache[key(StudyClock.addDays($0 * 7, to: .now))] != nil }.count
    }
    var nextWeeksAvailable: Bool {
        cache[key(.now)] != nil && cache[key(StudyClock.addDays(7, to: .now))] != nil
    }

    /// Every subject seen in the cached schedule of this group, for assignment pickers.
    var subjects: [String] {
        Set(normalizedWeeks.filter { $0.key.hasPrefix("\(group.id)-") }.values.flatMap { $0.map(\.subject) }).sorted()
    }
    /// The next lesson of a subject, used as the default deadline ("hand in at the lesson").
    func nextLesson(of subject: String, after date: Date = .now) -> Lesson? {
        upcomingLessons.first { $0.subject == subject && $0.start > date }
    }

    func shiftWeek(_ offset: Int) { selectedDate = StudyClock.addDays(offset * 7, to: selectedDate) }

    func refresh(allowActivityStart: Bool = true) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--qa-offline") || ProcessInfo.processInfo.environment["POLYTECH_QA_OFFLINE"] == "1" {
            await syncActivity(allowStart: allowActivityStart)
            return
        }
        #endif
        guard !isRefreshing else { refreshQueued = true; return }
        let token = UUID()
        refreshID = token
        let requestedGroup = group
        let requestedDate = selectedDate
        let dates = Set([weekStart] + (0..<preferences.weeksAhead).map { StudyClock.monday(StudyClock.addDays($0 * 7, to: .now)) })
        isLoading = displayedWeek == nil
        isRefreshing = true
        errorMessage = nil
        var failures: [String] = []
        await withTaskGroup(of: (Date, Result<ScheduleResponse, Error>).self) { tasks in
            for date in dates {
                tasks.addTask { [api] in
                    do { return (date, .success(try await api.week(groupID: requestedGroup.id, date: date))) }
                    catch { return (date, .failure(error)) }
                }
            }
            for await (date, result) in tasks {
                guard refreshID == token, group.id == requestedGroup.id else { continue }
                switch result {
                case .success(let response):
                    guard response.group.id == requestedGroup.id else {
                        failures.append("Сервис вернул другую группу.")
                        continue
                    }
                    // PolyChanges: compare with the copy we had before replacing it.
                    if let previous = normalizedWeeks[key(date, groupID: requestedGroup.id)] {
                        study.recordLocal(old: previous, new: response.lessons, groupID: requestedGroup.id)
                    }
                    cache[key(date, groupID: requestedGroup.id)] = CachedWeek(response: response, fetchedAt: .now)
                    normalizedWeeks[key(date, groupID: requestedGroup.id)] = response.lessons
                    if StudyClock.calendar.isDate(date, inSameDayAs: StudyClock.monday(requestedDate)) { group = response.group }
                case .failure(let error):
                    if !(error is CancellationError) { failures.append(error.localizedDescription) }
                }
            }
        }
        guard refreshID == token, group.id == requestedGroup.id else { return }
        isLoading = false
        isRefreshing = false
        if !failures.isEmpty {
            errorMessage = displayedWeek == nil ? failures[0] : "Не всё удалось обновить. Показываем сохранённые данные."
        }
        do { try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic) }
        catch { errorMessage = "Расписание загружено, но не удалось сохранить его на устройстве." }
        publishWidgets()
        await syncActivity(allowStart: allowActivityStart)
        if refreshQueued {
            refreshQueued = false
            Task { await self.refresh(allowActivityStart: allowActivityStart) }
        }
    }

    func choose(_ newGroup: StudyGroup) async {
        await activity.stop()
        refreshID = UUID()
        isRefreshing = false
        group = newGroup
        selectedDate = StudyClock.calendar.startOfDay(for: .now)
        activityMessage = nil
        study.select(groupID: newGroup.id)
    }

    func syncActivity(allowStart: Bool = true) async {
        activityMessage = await activity.sync(lesson: activityLesson(), group: group,
                                               accent: accent, theme: theme.rawValue,
                                               enabled: liveEnabled && !dayFinished, allowStart: allowStart,
                                               dataIsFresh: cache[key(.now)].map { Date.now.timeIntervalSince($0.fetchedAt) < 86_400 } ?? false)
    }

    func updateIcon() async {
        let name = useAccentIcon && accent != .green ? "Accent-\(accent.rawValue)" : nil
        #if os(iOS)
        guard UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != name else { return }
        do { try await UIApplication.shared.setAlternateIconName(name); iconMessage = nil }
        catch { iconMessage = "Не удалось изменить значок: \(error.localizedDescription)" }
        #else
        NSApplication.shared.applicationIconImage = name.flatMap { NSImage(named: $0) } ?? NSImage(named: "MacAppIcon")
        #endif
    }

    func publishWidgets() {
        let snapshot = WidgetSnapshot(group: group, lessons: upcomingLessons, preferences: preferences,
                                      updatedAt: cache[key(.now)]?.fetchedAt ?? .distantPast, accent: accent, theme: theme.rawValue)
        widgetSyncFailed = !WidgetStorage.save(snapshot)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "Как на устройстве"; case .light: "Светлая"; case .dark: "Тёмная" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}
