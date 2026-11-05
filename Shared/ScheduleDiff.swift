import Foundation

public enum ScheduleChangeKind: String, Codable, CaseIterable, Sendable {
    case added, cancelled, moved, roomChanged, teacherChanged

    public var title: String {
        switch self {
        case .added: "Добавлено"
        case .cancelled: "Отменено"
        case .moved: "Перенесено"
        case .roomChanged: "Другая аудитория"
        case .teacherChanged: "Другой преподаватель"
        }
    }
    public var tag: String {
        switch self {
        case .added: "НОВАЯ"
        case .cancelled: "ОТМЕНЕНО"
        case .moved: "ПЕРЕНЕСЕНО"
        case .roomChanged: "АУДИТОРИЯ"
        case .teacherChanged: "ПРЕПОДАВАТЕЛЬ"
        }
    }
}

/// The parts of a lesson that matter when explaining a change.
public struct LessonSlot: Codable, Hashable, Sendable {
    public let start: Date
    public let end: Date
    public let rooms: [String]
    public let teachers: [String]

    public init(start: Date, end: Date, rooms: [String], teachers: [String]) {
        self.start = start; self.end = end; self.rooms = rooms; self.teachers = teachers
    }
    public init(_ lesson: Lesson) {
        self.init(start: lesson.start, end: lesson.end, rooms: lesson.rooms.map(\.label), teachers: lesson.teachers)
    }
    public var timeRange: String {
        "\(StudyClock.string(start, format: "HH:mm"))–\(StudyClock.string(end, format: "HH:mm"))"
    }
    public var location: String { rooms.isEmpty ? "Аудитория не указана" : rooms.joined(separator: ", ") }
}

public struct ScheduleChange: Codable, Hashable, Identifiable, Sendable {
    public let kind: ScheduleChangeKind
    public let subject: String
    public let lessonKind: String
    public let old: LessonSlot?
    public let new: LessonSlot?
    public let detectedAt: Date

    public init(kind: ScheduleChangeKind, subject: String, lessonKind: String, old: LessonSlot?, new: LessonSlot?, detectedAt: Date) {
        self.kind = kind; self.subject = subject; self.lessonKind = lessonKind
        self.old = old; self.new = new; self.detectedAt = detectedAt
    }

    public var id: String { fingerprint }

    /// Same on every device and on the server for the same change, so histories can be merged.
    public var fingerprint: String {
        func slot(_ value: LessonSlot?) -> String {
            guard let value else { return "-" }
            return "\(Int(value.start.timeIntervalSince1970)),\(Int(value.end.timeIntervalSince1970)),\(value.rooms.sorted().joined(separator: "+")),\(value.teachers.sorted().joined(separator: "+"))"
        }
        let text = [kind.rawValue, subject, lessonKind, slot(old), slot(new)].joined(separator: "|")
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }

    /// When the lesson takes place now (or used to take place, for cancellations).
    public var relevantStart: Date { new?.start ?? old?.start ?? detectedAt }

    /// True when this change describes the lesson as it is in the current schedule.
    public func describes(_ lesson: Lesson) -> Bool {
        guard let new, kind != .cancelled else { return false }
        return new.start == lesson.start && subject == lesson.subject && lessonKind == lesson.kind
    }
}

public enum ScheduleDiff {
    /// Compares two versions of the same period. Only lessons starting after `now` count:
    /// changes to lessons that already happened are not interesting.
    public static func changes(old: [Lesson], new: [Lesson], after now: Date, detectedAt: Date = .now) -> [ScheduleChange] {
        var removed = old.filter { $0.start > now }
        var added = new.filter { $0.start > now }
        var result: [ScheduleChange] = []

        // 1. Identical lessons cancel out.
        for lesson in added {
            if let index = removed.firstIndex(where: { same($0, lesson) && LessonSlot($0) == LessonSlot(lesson) }) {
                removed.remove(at: index)
                added.removeAll { $0 == lesson }
            }
        }
        // 2. Same subject, type and time: something inside changed.
        for lesson in added {
            guard let index = removed.firstIndex(where: { same($0, lesson) && $0.start == lesson.start && $0.end == lesson.end }) else { continue }
            let before = removed.remove(at: index)
            added.removeAll { $0 == lesson }
            let roomsChanged = Set(before.rooms.map(\.label)) != Set(lesson.rooms.map(\.label))
            let teachersChanged = Set(before.teachers) != Set(lesson.teachers)
            guard roomsChanged || teachersChanged else { continue }
            result.append(change(roomsChanged ? .roomChanged : .teacherChanged, before, lesson, detectedAt))
        }
        // 3. A lesson disappeared and the same subject/type appeared nearby: a move.
        let window: TimeInterval = 14 * 86_400
        var candidates: [(old: Lesson, new: Lesson, distance: TimeInterval)] = []
        for before in removed {
            for after in added where same(before, after) {
                let distance = abs(after.start.timeIntervalSince(before.start))
                if distance <= window { candidates.append((before, after, distance)) }
            }
        }
        candidates.sort { $0.distance == $1.distance ? $0.old.start < $1.old.start : $0.distance < $1.distance }
        for candidate in candidates where removed.contains(candidate.old) && added.contains(candidate.new) {
            removed.removeAll { $0 == candidate.old }
            added.removeAll { $0 == candidate.new }
            result.append(change(.moved, candidate.old, candidate.new, detectedAt))
        }
        // 4. Whatever is left.
        result += removed.map { change(.cancelled, $0, nil, detectedAt) }
        result += added.map { change(.added, nil, $0, detectedAt) }
        return result.sorted { $0.relevantStart == $1.relevantStart ? $0.fingerprint < $1.fingerprint : $0.relevantStart < $1.relevantStart }
    }

    /// Adds new changes to a history, keeps the earliest detection of each change and drops old records.
    public static func merge(_ history: [ScheduleChange], _ incoming: [ScheduleChange], keepAfter cutoff: Date) -> [ScheduleChange] {
        var byID: [String: ScheduleChange] = [:]
        for change in history + incoming {
            if let existing = byID[change.id], existing.detectedAt <= change.detectedAt { continue }
            byID[change.id] = change
        }
        return byID.values.filter { $0.detectedAt >= cutoff }
            .sorted { $0.detectedAt == $1.detectedAt ? $0.relevantStart < $1.relevantStart : $0.detectedAt > $1.detectedAt }
    }

    private static func same(_ a: Lesson, _ b: Lesson) -> Bool { a.subject == b.subject && a.kind == b.kind }

    private static func change(_ kind: ScheduleChangeKind, _ old: Lesson?, _ new: Lesson?, _ date: Date) -> ScheduleChange {
        let lesson = (new ?? old)!
        return ScheduleChange(kind: kind, subject: lesson.subject, lessonKind: lesson.kind,
                              old: old.map(LessonSlot.init), new: new.map(LessonSlot.init), detectedAt: date)
    }
}
