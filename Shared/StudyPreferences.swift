import Foundation

enum AttendanceRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, skip, attend
    var id: String { rawValue }
    var title: String {
        switch self { case .automatic: "По общему правилу"; case .skip: "Пропускать"; case .attend: "Посещать" }
    }
}

struct StudyPreferences: Codable, Equatable, Sendable {
    var skipMilitary = true
    var skipLectures = false
    var subjectRules: [String: AttendanceRule] = [:]
    var lessonRules: [String: AttendanceRule] = [:]
    var finishedDays: Set<String> = []
    var scale = 1.0
    var compact = false
    var showTeachers = true
    var showPast = true
    var weeksAhead = 6

    func includes(_ lesson: Lesson, groupID: Int) -> Bool {
        let individual = lessonRules[lesson.ruleKey(groupID: groupID)] ?? .automatic
        if individual != .automatic { return individual == .attend }
        let subject = subjectRules[lesson.subjectRuleKey(groupID: groupID)] ?? .automatic
        if subject != .automatic { return subject == .attend }
        if skipMilitary && lesson.isMilitary { return false }
        return !(skipLectures && lesson.isLecture)
    }

    func isFinished(_ date: Date, groupID: Int) -> Bool {
        finishedDays.contains(dayKey(date, groupID: groupID))
    }
    func dayKey(_ date: Date, groupID: Int) -> String {
        "\(groupID):\(StudyClock.string(date, format: "yyyy-MM-dd"))"
    }
    func eligible(_ lessons: [Lesson], groupID: Int, now: Date) -> [Lesson] {
        let finishedRanges = finishedDays.compactMap { key -> Range<Date>? in
            let parts = key.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0] == String(groupID), let start = StudyClock.date(String(parts[1])) else { return nil }
            return start..<StudyClock.addDays(1, to: start)
        }
        return lessons.filter { lesson in
            lesson.end > now && includes(lesson, groupID: groupID)
                && !finishedRanges.contains(where: { $0.contains(lesson.start) })
        }
    }
}

extension Lesson {
    var isLecture: Bool { kind.localizedCaseInsensitiveContains("лек") }
    func ruleKey(groupID: Int) -> String {
        "\(groupID)|\(subject)|\(kind)|\(start.timeIntervalSince1970)"
    }
    func subjectRuleKey(groupID: Int) -> String { "\(groupID)|\(subject)|\(kind)" }
}
