import XCTest
@testable import PolytechCore

final class ScheduleDiffTests: XCTestCase {
    private func lessons() throws -> [Lesson] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "week", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(ScheduleResponse.self, from: Data(contentsOf: url)).lessons
    }
    private var beforeWeek: Date { StudyClock.date("2026-10-11")! }

    private func copy(_ lesson: Lesson, id: String? = nil, shift: TimeInterval = 0, rooms: [Room]? = nil, teachers: [String]? = nil) -> Lesson {
        Lesson(id: id ?? lesson.id, subject: lesson.subject, kind: lesson.kind,
               start: lesson.start.addingTimeInterval(shift), end: lesson.end.addingTimeInterval(shift),
               teachers: teachers ?? lesson.teachers, rooms: rooms ?? lesson.rooms)
    }

    func testIdenticalScheduleHasNoChangesEvenWithNewIDs() throws {
        let old = try lessons()
        let new = old.enumerated().map { copy($1, id: "renumbered-\($0)") }
        XCTAssertTrue(ScheduleDiff.changes(old: old, new: new, after: beforeWeek).isEmpty)
    }

    func testMoveCancelAddAndRoomChange() throws {
        let old = try lessons()
        let subjects = Dictionary(grouping: old, by: \.subject)
        // Lessons whose subject appears once, so the expected pairing is unambiguous.
        let unique = old.filter { subjects[$0.subject]?.count == 1 }
        XCTAssertGreaterThanOrEqual(unique.count, 3, "fixture should contain several single-lesson subjects")
        let moved = unique[0], cancelled = unique[1], roomChanged = unique[2]
        var new = old.filter { $0 != moved && $0 != cancelled && $0 != roomChanged }
        new.append(copy(moved, id: "moved", shift: 2 * 86_400))
        new.append(copy(roomChanged, rooms: [Room(name: "999", building: nil)]))
        let extra = Lesson(id: "extra", subject: "Консультация", kind: "Консультация",
                           start: StudyClock.date("2026-10-17", time: "10:00")!, end: StudyClock.date("2026-10-17", time: "11:30")!,
                           teachers: [], rooms: [])
        new.append(extra)

        let changes = ScheduleDiff.changes(old: old, new: new, after: beforeWeek)
        XCTAssertEqual(changes.count, 4)
        let move = try XCTUnwrap(changes.first { $0.kind == .moved })
        XCTAssertEqual(move.subject, moved.subject)
        XCTAssertEqual(move.old?.start, moved.start)
        XCTAssertEqual(move.new?.start, moved.start.addingTimeInterval(2 * 86_400))
        XCTAssertEqual(changes.first { $0.kind == .cancelled }?.subject, cancelled.subject)
        XCTAssertNil(changes.first { $0.kind == .cancelled }?.new)
        XCTAssertEqual(changes.first { $0.kind == .added }?.subject, "Консультация")
        let room = try XCTUnwrap(changes.first { $0.kind == .roomChanged })
        XCTAssertEqual(room.new?.rooms, ["999"])
        XCTAssertTrue(room.describes(copy(roomChanged, rooms: [Room(name: "999", building: nil)])))
    }

    func testTeacherChangeAndPastLessonsIgnored() throws {
        let old = try lessons()
        let target = try XCTUnwrap(old.last)
        let new = old.map { $0 == target ? copy($0, teachers: ["Новый Преподаватель"]) : $0 }
        XCTAssertEqual(ScheduleDiff.changes(old: old, new: new, after: beforeWeek).map(\.kind), [.teacherChanged])
        // Once the lesson has started, it is history and no longer reported.
        XCTAssertTrue(ScheduleDiff.changes(old: old, new: new, after: target.start).isEmpty)
        // A lesson that vanished from the past is not a cancellation.
        let first = try XCTUnwrap(old.first)
        XCTAssertTrue(ScheduleDiff.changes(old: old, new: old.filter { $0 != first }, after: first.end).isEmpty)
    }

    func testMoveFarAwayIsCancelPlusAdd() throws {
        let old = try lessons()
        let target = try XCTUnwrap(old.first)
        let new = old.map { $0 == target ? copy($0, id: "far", shift: 30 * 86_400) : $0 }
        XCTAssertEqual(Set(ScheduleDiff.changes(old: old, new: new, after: beforeWeek).map(\.kind)), [.added, .cancelled])
    }

    func testFingerprintIsStableAndMergeDeduplicates() throws {
        let old = try lessons()
        let target = try XCTUnwrap(old.first)
        let new = old.filter { $0 != target }
        let early = ScheduleDiff.changes(old: old, new: new, after: beforeWeek, detectedAt: Date(timeIntervalSince1970: 1_000))
        let late = ScheduleDiff.changes(old: old, new: new, after: beforeWeek, detectedAt: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(early.map(\.fingerprint), late.map(\.fingerprint))
        let merged = ScheduleDiff.merge(late, early, keepAfter: .distantPast)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.detectedAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertTrue(ScheduleDiff.merge(merged, [], keepAfter: Date(timeIntervalSince1970: 1_500)).isEmpty)
        let restored = try PolyCoding.decoder().decode([ScheduleChange].self, from: PolyCoding.encoder().encode(merged))
        XCTAssertEqual(restored, merged)
    }

    /// The Android app computes the same value (ScheduleDiffTest.fingerprintMatchesApple). Keep them in sync.
    func testFingerprintMatchesAndroid() {
        let change = ScheduleChange(kind: .moved, subject: "Физика", lessonKind: "Практика",
            old: LessonSlot(start: Date(timeIntervalSince1970: 1_793_900_000), end: Date(timeIntervalSince1970: 1_793_905_400), rooms: ["101 · ГЗ"], teachers: ["Иванов И. И."]),
            new: LessonSlot(start: Date(timeIntervalSince1970: 1_794_000_000), end: Date(timeIntervalSince1970: 1_794_005_400), rooms: ["202 · ГЗ"], teachers: ["Иванов И. И."]),
            detectedAt: .now)
        XCTAssertEqual(change.fingerprint, "b8c11e8fe1716c70")
    }

    func testDraftValidation() {
        let due = Date()
        XCTAssertNil(AssignmentDraft(subject: "Физика", title: "Лаба 3", dueAt: due).problem)
        XCTAssertNotNil(AssignmentDraft(subject: "Физика", title: "   ", dueAt: due).problem)
        XCTAssertNotNil(AssignmentDraft(subject: "", title: "Лаба", dueAt: due).problem)
        XCTAssertNotNil(AssignmentDraft(subject: "Физика", title: String(repeating: "а", count: 141), dueAt: due).problem)
    }
}
