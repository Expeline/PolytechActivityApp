import Foundation

// All schedule dates belong to Saint Petersburg, regardless of the phone's timezone.
enum StudyClock {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        calendar.firstWeekday = 2
        return calendar
    }

    static func date(_ day: String, time: String = "00:00") -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.isLenient = false
        return formatter.date(from: "\(day) \(time)")
    }

    static func string(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    static func monday(_ date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }

    static func addDays(_ count: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: count, to: date)!
    }
}

struct Faculty: Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let abbr: String?
}

struct StudyGroup: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let faculty: Faculty

    static let `default` = StudyGroup(id: 45602, name: "5130904/40102", faculty: Faculty(
        id: 125, name: "Институт компьютерных наук и кибербезопасности", abbr: "ИКНК"))

    var sourceURL: URL {
        URL(string: "https://ruz.spbstu.ru/faculty/\(faculty.id)/groups/\(id)")!
    }

    static func ids(from text: String) -> (faculty: Int, group: Int)? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host == "ruz.spbstu.ru" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 4, parts[0] == "faculty", parts[2] == "groups",
              let faculty = Int(parts[1]), let group = Int(parts[3]), faculty > 0, group > 0 else { return nil }
        return (faculty, group)
    }
}

struct ScheduleResponse: Codable, Sendable {
    let week: Week
    let days: [ScheduleDay]
    let group: StudyGroup

    struct Week: Codable, Sendable {
        let date_start: String
        let date_end: String
        let is_odd: Bool
    }

    var lessons: [Lesson] {
        var result: [Lesson] = []
        for day in days {
            for (index, entry) in day.lessons.enumerated() {
                guard let start = StudyClock.date(day.date, time: entry.time_start),
                      let end = StudyClock.date(day.date, time: entry.time_end), end > start else { continue }
                let teachers = entry.teachers?.map { $0.full_name } ?? []
                let lesson = Lesson(id: "\(group.id)-\(day.date)-\(index)-\(entry.time_start)",
                              subject: entry.subject, kind: entry.typeObj?.name ?? "Занятие",
                              start: start, end: end, teachers: teachers,
                              rooms: entry.auditories ?? [], additionalInfo: entry.additional_info ?? "",
                              webinarURL: entry.webinar_url, lmsURL: entry.lms_url)
                result.append(lesson)
            }
        }
        return result.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
}

struct ScheduleDay: Codable, Sendable {
    let date: String
    let lessons: [ScheduleEntry]
}

struct ScheduleEntry: Codable, Sendable {
    let subject: String
    let time_start: String
    let time_end: String
    let typeObj: LessonKind?
    let teachers: [Teacher]?
    let auditories: [Room]?
    let additional_info: String?
    let webinar_url: String?
    let lms_url: String?

    struct LessonKind: Codable, Sendable { let name: String }
    struct Teacher: Codable, Sendable { let full_name: String }
}

struct Room: Codable, Hashable, Sendable {
    let name: String
    let building: Building?
    struct Building: Codable, Hashable, Sendable {
        let name: String
        let abbr: String?
        let address: String?
    }
    var label: String {
        if name.localizedCaseInsensitiveContains("дистанц") { return "Дистанционно" }
        return [name, building?.abbr ?? building?.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct Lesson: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let subject: String
    let kind: String
    let start: Date
    let end: Date
    let teachers: [String]
    let rooms: [Room]
    let additionalInfo: String
    let webinarURL: String?
    let lmsURL: String?

    var isMilitary: Bool {
        let value = subject.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
        return value.contains("военн") || value.contains("воинск")
    }
    var location: String { rooms.isEmpty ? "Аудитория не указана" : rooms.map(\.label).joined(separator: ", ") }
    var timeRange: String { "\(StudyClock.string(start, format: "HH:mm"))–\(StudyClock.string(end, format: "HH:mm"))" }

    static func next(in lessons: [Lesson], after now: Date, skipMilitary: Bool) -> Lesson? {
        lessons.filter { $0.start > now && (!skipMilitary || !$0.isMilitary) }
            .min { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    static func current(in lessons: [Lesson], at now: Date, skipMilitary: Bool) -> Lesson? {
        lessons.filter { $0.start <= now && now < $0.end && (!skipMilitary || !$0.isMilitary) }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start > $1.start }.first
    }

    static func activeOrNext(in lessons: [Lesson], at now: Date, skipMilitary: Bool) -> Lesson? {
        current(in: lessons, at: now, skipMilitary: skipMilitary)
            ?? next(in: lessons, after: now, skipMilitary: skipMilitary)
    }
}

struct CachedWeek: Codable {
    let response: ScheduleResponse
    let fetchedAt: Date
}
