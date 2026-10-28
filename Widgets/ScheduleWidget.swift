import AppIntents
import SwiftUI
import WidgetKit

struct ScheduleConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Расписание"
    static let description = IntentDescription("Группа, оформление и посещение синхронизируются с приложением.")
}

struct ScheduleWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let error: String?
    var lesson: Lesson? {
        snapshot?.currentLesson(at: date)
    }
    var ongoing: Bool { lesson.map { $0.start <= date && date < $0.end } == true }
}

struct ScheduleWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ScheduleWidgetEntry { ScheduleWidgetEntry(date: .now, snapshot: nil, error: nil) }
    func snapshot(for configuration: ScheduleConfiguration, in context: Context) async -> ScheduleWidgetEntry {
        ScheduleWidgetEntry(date: .now, snapshot: WidgetStorage.read(), error: nil)
    }
    func timeline(for configuration: ScheduleConfiguration, in context: Context) async -> Timeline<ScheduleWidgetEntry> {
        let snapshot = WidgetStorage.read()
        let now = Date.now
        let tomorrow = StudyClock.addDays(1, to: StudyClock.calendar.startOfDay(for: now))
        var dates: Set<Date> = [now, tomorrow]
        for lesson in snapshot?.lessons ?? [] where lesson.end > now && lesson.start < StudyClock.addDays(2, to: now) {
            if lesson.start > now { dates.insert(lesson.start) }
            dates.insert(lesson.end)
        }
        let entries = dates.sorted().prefix(48).map { ScheduleWidgetEntry(date: $0, snapshot: snapshot, error: nil) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600)))
    }
}

struct ScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PolytechSchedule", intent: ScheduleConfiguration.self, provider: ScheduleWidgetProvider()) { entry in
            ScheduleWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas(snapshot: entry.snapshot) }
                .widgetURL(URL(string: "polytech://schedule"))
        }
        .configurationDisplayName("Пары под рукой")
        .description("Только текущая пара или свободное время. Настройки — из приложения.")
        .supportedFamilies(families)
    }
    private var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

struct ScheduleWidgetView: View {
    let entry: ScheduleWidgetEntry
    var previewFamily: WidgetFamily? = nil
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.widgetFamily) private var systemFamily
    private var scheme: ColorScheme { entry.snapshot?.theme == "light" ? .light : entry.snapshot?.theme == "dark" ? .dark : systemScheme }
    private var ink: Color { scheme == .dark ? .white : .black }
    private var family: WidgetFamily { previewFamily ?? systemFamily }
    private var mint: Color { scheme == .dark ? (entry.snapshot?.accent ?? .green).highlight : (entry.snapshot?.accent ?? .green).background }
    var body: some View {
        Group {
            #if os(iOS)
            if family == .accessoryInline {
                Text(entry.lesson.map { "\(StudyClock.string($0.start, format: "HH:mm")) \($0.subject)" } ?? "Политех · \(emptyTitle)")
            } else if family == .accessoryCircular {
                if let lesson = entry.lesson {
                    Gauge(value: entry.ongoing ? max(0, min(1, entry.date.timeIntervalSince(lesson.start) / lesson.end.timeIntervalSince(lesson.start))) : 0) {
                        Image(systemName: "graduationcap.fill")
                    } currentValueLabel: { Text(StudyClock.string(entry.ongoing ? lesson.end : lesson.start, format: "HH:mm")).font(.system(size: 11)) }.gaugeStyle(.accessoryCircular)
                } else { Image(systemName: "checkmark.circle").accessibilityLabel(emptyTitle) }
            } else if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.ongoing ? "Сейчас" : "Сейчас нет пары").font(.caption)
                    Text(entry.lesson?.subject ?? emptyTitle).font(.headline).lineLimit(1)
                    if let lesson = entry.lesson { Text("\(lesson.timeRange) · \(lesson.location)").font(.caption2) }
                }
            } else { card }
            #else
            card
            #endif
        }.environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "ru_RU"))
            .environment(\.timeZone, StudyClock.calendar.timeZone)
    }
    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.ongoing ? "СЕЙЧАС" : "СЕГОДНЯ").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(mint)
                Spacer()
                Image(systemName: "graduationcap.fill").foregroundStyle(mint)
            }
            if let lesson = entry.lesson {
                Text(lesson.subject).font(.system(size: family == .systemSmall ? 15 : 20, weight: .medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text("\(StudyClock.string(lesson.start, format: "EE, HH:mm")) · \(lesson.location)").font(.system(size: 10)).foregroundStyle(ink.opacity(0.65)).lineLimit(1)
                if family != .systemLarge { Spacer(minLength: 0) }
                if family == .systemSmall {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.ongoing ? "До конца" : "До начала").font(.system(size: 10)).foregroundStyle(ink.opacity(0.55)).lineLimit(1)
                        clock(lesson).frame(width: 115, alignment: .leading)
                    }
                } else {
                    HStack {
                        Text(entry.ongoing ? "До конца" : "До начала").font(.system(size: 10)).foregroundStyle(ink.opacity(0.55))
                        Spacer()
                        clock(lesson).frame(width: 105)
                    }
                }

            } else {
                Text(emptyTitle).font(.system(size: 20, weight: .medium))
                Text(entry.snapshot == nil ? "Откройте приложение" : "Хорошего отдыха").font(.caption).foregroundStyle(ink.opacity(0.6))
            }
            if entry.error != nil { Text("Офлайн").font(.system(size: 9)).foregroundStyle(ink.opacity(0.4)) }
        }.foregroundStyle(ink)
    }
    private var emptyTitle: String {
        guard let snapshot = entry.snapshot else { return "Откройте Политех" }
        if snapshot.preferences.isFinished(entry.date, groupID: snapshot.group.id) { return "День завершён" }
        let today = snapshot.lessons.filter { StudyClock.calendar.isDate($0.start, inSameDayAs: entry.date) && snapshot.preferences.includes($0, groupID: snapshot.group.id) }
        return today.isEmpty ? "День свободен" : "Сейчас нет пары"
    }
    private func clock(_ lesson: Lesson) -> some View {
        Text(timerInterval: entry.date...max(entry.date, entry.ongoing ? lesson.end : lesson.start), countsDown: true)
            .font(.system(size: 18, weight: .light)).monospacedDigit().multilineTextAlignment(family == .systemSmall ? .leading : .trailing).foregroundStyle(mint)
    }

}

private struct WidgetCanvas: View {
    let snapshot: WidgetSnapshot?
    @Environment(\.colorScheme) private var systemScheme
    var body: some View {
        let dark = snapshot?.theme == "dark" || (snapshot?.theme != "light" && systemScheme == .dark)
        let accent = snapshot?.accent ?? .green
        if dark { accent.background }
        else { Color.white.overlay(accent.color.opacity(0.06)) }
    }
}
