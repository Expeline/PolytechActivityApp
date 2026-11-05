import Foundation

// All schedule dates belong to Saint Petersburg, regardless of the phone's timezone.
public enum StudyClock {
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        calendar.firstWeekday = 2
        return calendar
    }

    public static func date(_ day: String, time: String = "00:00") -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.isLenient = false
        return formatter.date(from: "\(day) \(time)")
    }

    public static func string(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    public static func monday(_ date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }

    public static func addDays(_ count: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: count, to: date)!
    }
}

public struct Faculty: Codable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let abbr: String?
    public init(id: Int, name: String, abbr: String?) { self.id = id; self.name = name; self.abbr = abbr }
}

public struct StudyGroup: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let faculty: Faculty
    public init(id: Int, name: String, faculty: Faculty) { self.id = id; self.name = name; self.faculty = faculty }

    public static let `default` = StudyGroup(id: 45602, name: "5130904/40102", faculty: Faculty(
        id: 125, name: "Институт компьютерных наук и кибербезопасности", abbr: "ИКНК"))

    public var sourceURL: URL {
        URL(string: "https://ruz.spbstu.ru/faculty/\(faculty.id)/groups/\(id)")!
    }

    public static func ids(from text: String) -> (faculty: Int, group: Int)? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host == "ruz.spbstu.ru" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 4, parts[0] == "faculty", parts[2] == "groups",
              let faculty = Int(parts[1]), let group = Int(parts[3]), faculty > 0, group > 0 else { return nil }
        return (faculty, group)
    }
}

public struct ScheduleResponse: Codable, Sendable {
    public let week: Week
    public let days: [ScheduleDay]
    public let group: StudyGroup

    public struct Week: Codable, Sendable {
        public let date_start: String
        public let date_end: String
        public let is_odd: Bool
    }

    public var lessons: [Lesson] {
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

public struct ScheduleDay: Codable, Sendable {
    public let date: String
    public let lessons: [ScheduleEntry]
}

public struct ScheduleEntry: Codable, Sendable {
    public let subject: String
    public let time_start: String
    public let time_end: String
    public let typeObj: LessonKind?
    public let teachers: [Teacher]?
    public let auditories: [Room]?
    public let additional_info: String?
    public let webinar_url: String?
    public let lms_url: String?

    public struct LessonKind: Codable, Sendable { public let name: String }
    public struct Teacher: Codable, Sendable { public let full_name: String }
}

public struct Room: Codable, Hashable, Sendable {
    public let name: String
    public let building: Building?
    public init(name: String, building: Building?) { self.name = name; self.building = building }
    public struct Building: Codable, Hashable, Sendable {
        public let name: String
        public let abbr: String?
        public let address: String?
        public init(name: String, abbr: String?, address: String?) { self.name = name; self.abbr = abbr; self.address = address }
    }
    public var label: String {
        if name.localizedCaseInsensitiveContains("дистанц") { return "Дистанционно" }
        return [name, building?.abbr ?? building?.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public struct Lesson: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let subject: String
    public let kind: String
    public let start: Date
    public let end: Date
    public let teachers: [String]
    public let rooms: [Room]
    public let additionalInfo: String
    public let webinarURL: String?
    public let lmsURL: String?

    public init(id: String, subject: String, kind: String, start: Date, end: Date, teachers: [String], rooms: [Room],
                additionalInfo: String = "", webinarURL: String? = nil, lmsURL: String? = nil) {
        self.id = id; self.subject = subject; self.kind = kind; self.start = start; self.end = end
        self.teachers = teachers; self.rooms = rooms; self.additionalInfo = additionalInfo
        self.webinarURL = webinarURL; self.lmsURL = lmsURL
    }

    public var isMilitary: Bool {
        let value = subject.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
        return value.contains("военн") || value.contains("воинск")
    }
    public var location: String { rooms.isEmpty ? "Аудитория не указана" : rooms.map(\.label).joined(separator: ", ") }
    public var timeRange: String { "\(StudyClock.string(start, format: "HH:mm"))–\(StudyClock.string(end, format: "HH:mm"))" }

    public static func next(in lessons: [Lesson], after now: Date, skipMilitary: Bool) -> Lesson? {
        lessons.filter { $0.start > now && (!skipMilitary || !$0.isMilitary) }
            .min { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    public static func current(in lessons: [Lesson], at now: Date, skipMilitary: Bool) -> Lesson? {
        lessons.filter { $0.start <= now && now < $0.end && (!skipMilitary || !$0.isMilitary) }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start > $1.start }.first
    }

    public static func activeOrNext(in lessons: [Lesson], at now: Date, skipMilitary: Bool) -> Lesson? {
        current(in: lessons, at: now, skipMilitary: skipMilitary)
            ?? next(in: lessons, after: now, skipMilitary: skipMilitary)
    }
}

public struct CachedWeek: Codable, Sendable {
    public let response: ScheduleResponse
    public let fetchedAt: Date
    public init(response: ScheduleResponse, fetchedAt: Date) { self.response = response; self.fetchedAt = fetchedAt }
}
