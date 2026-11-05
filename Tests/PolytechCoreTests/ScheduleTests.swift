import XCTest
@testable import PolytechCore

final class ScheduleTests: XCTestCase {
    func response() throws -> ScheduleResponse {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "week", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(ScheduleResponse.self, from: Data(contentsOf: url))
    }

    func testRealAPIResponseAndCacheRoundTrip() throws {
        let week = try response()
        XCTAssertEqual(week.group.id, 45602)
        XCTAssertEqual(week.group.name, "5130904/40102")
        XCTAssertFalse(week.lessons.isEmpty)
        XCTAssertTrue(week.lessons.allSatisfy { $0.end > $0.start })
        XCTAssertEqual(Set(week.lessons.map(\.id)).count, week.lessons.count)
        XCTAssertTrue(week.lessons.contains { $0.isMilitary })
        let cache = CachedWeek(response: week, fetchedAt: Date())
        let restored = try JSONDecoder().decode(CachedWeek.self, from: JSONEncoder().encode(cache))
        XCTAssertEqual(restored.response.lessons, week.lessons)
    }

    func testMilitaryFilterDoesNotRemoveScheduleLessons() throws {
        let lessons = try response().lessons
        let beforeMilitaryDay = try XCTUnwrap(StudyClock.date("2026-10-13", time: "07:00"))
        let unfiltered = try XCTUnwrap(Lesson.next(in: lessons, after: beforeMilitaryDay, skipMilitary: false))
        let filtered = try XCTUnwrap(Lesson.next(in: lessons, after: beforeMilitaryDay, skipMilitary: true))
        XCTAssertTrue(unfiltered.isMilitary)
        XCTAssertFalse(filtered.isMilitary)
        XCTAssertTrue(filtered.start > unfiltered.start)
        XCTAssertTrue(lessons.contains(unfiltered))
        XCTAssertFalse(Lesson.next(in: lessons, after: unfiltered.start, skipMilitary: false)?.id == unfiltered.id)
        XCTAssertNil(Lesson.next(in: lessons, after: StudyClock.date("2026-10-19")!, skipMilitary: false))
    }

    func testMoscowDateBoundariesAndMonday() throws {
        let midnight = try XCTUnwrap(StudyClock.date("2026-10-19"))
        let utc = ISO8601DateFormatter().string(from: midnight)
        XCTAssertEqual(utc, "2026-10-18T21:00:00Z")
        XCTAssertEqual(StudyClock.string(StudyClock.monday(StudyClock.date("2026-10-18")!), format: "yyyy-MM-dd"), "2026-10-12")
        XCTAssertEqual(StudyClock.string(StudyClock.monday(midnight), format: "yyyy-MM-dd"), "2026-10-19")
        XCTAssertNil(StudyClock.date("2026-10-19", time: "25:90"))
    }

    func testGroupLinksStayOnUniversityHost() {
        XCTAssertEqual(StudyGroup.ids(from: "https://ruz.spbstu.ru/faculty/125/groups/45602?date=2026-10-17")?.group, 45602)
        XCTAssertNil(StudyGroup.ids(from: "https://ruz.spbstu.ru.evil.example/faculty/125/groups/45602"))
        XCTAssertNil(StudyGroup.ids(from: "http://ruz.spbstu.ru/faculty/125/groups/45602"))
        XCTAssertNil(StudyGroup.ids(from: "https://ruz.spbstu.ru/faculty/125/groups/0"))
        XCTAssertNil(StudyGroup.ids(from: "5130904/40102"))
    }
    func testCurrentLessonBoundariesAndPriority() throws {
        let lessons = try response().lessons
        let lesson = try XCTUnwrap(lessons.first(where: { !$0.isMilitary }))
        XCTAssertNil(Lesson.current(in: [lesson], at: lesson.start.addingTimeInterval(-1), skipMilitary: false))
        XCTAssertEqual(Lesson.current(in: [lesson], at: lesson.start, skipMilitary: false), lesson)
        XCTAssertEqual(Lesson.current(in: [lesson], at: lesson.end.addingTimeInterval(-1), skipMilitary: false), lesson)
        XCTAssertNil(Lesson.current(in: [lesson], at: lesson.end, skipMilitary: false))
        XCTAssertEqual(Lesson.activeOrNext(in: lessons, at: lesson.start, skipMilitary: false), lesson)
        let military = try XCTUnwrap(lessons.first(where: \.isMilitary))
        XCTAssertEqual(Lesson.current(in: lessons, at: military.start, skipMilitary: false), military)
        XCTAssertNil(Lesson.current(in: [military], at: military.start, skipMilitary: true))
        let filtered = Lesson.activeOrNext(in: lessons, at: military.start, skipMilitary: true)
        XCTAssertNotEqual(filtered?.id, military.id)
        XCTAssertEqual(Lesson.activeOrNext(in: lessons, at: lesson.end, skipMilitary: false),
                       Lesson.next(in: lessons, after: lesson.end, skipMilitary: false))
    }

    func testAttendanceRulePrecedenceAndFinishedDay() throws {
        let lecture = try XCTUnwrap(try response().lessons.first(where: { $0.isLecture && !$0.isMilitary }))
        var preferences = StudyPreferences()
        preferences.skipLectures = true
        XCTAssertFalse(preferences.includes(lecture, groupID: 45602))
        preferences.subjectRules[lecture.subjectRuleKey(groupID: 45602)] = .attend
        XCTAssertTrue(preferences.includes(lecture, groupID: 45602))
        preferences.lessonRules[lecture.ruleKey(groupID: 45602)] = .skip
        XCTAssertFalse(preferences.includes(lecture, groupID: 45602))
        preferences.lessonRules[lecture.ruleKey(groupID: 45602)] = .attend
        XCTAssertTrue(preferences.includes(lecture, groupID: 45602))
        XCTAssertFalse(preferences.includes(lecture, groupID: 999))
        preferences.finishedDays.insert(preferences.dayKey(lecture.start, groupID: 45602))
        XCTAssertTrue(preferences.eligible([lecture], groupID: 45602, now: lecture.start).isEmpty)
        XCTAssertFalse(preferences.isFinished(StudyClock.addDays(1, to: lecture.start), groupID: 45602))
        let restored = try JSONDecoder().decode(StudyPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(preferences, restored)
    }

    func testWidgetShowsOnlyCurrentLessonAndSharesFinishedDayAndAccent() throws {
        let response = try response()
        let lesson = try XCTUnwrap(response.lessons.first(where: { !$0.isMilitary }))
        var snapshot = WidgetSnapshot(group: response.group, lessons: response.lessons,
            preferences: StudyPreferences(), updatedAt: lesson.start, accent: .purple, theme: "dark")
        XCTAssertNil(snapshot.currentLesson(at: lesson.start.addingTimeInterval(-1)))
        XCTAssertEqual(snapshot.currentLesson(at: lesson.start), lesson)
        snapshot.preferences.finishedDays.insert(snapshot.preferences.dayKey(lesson.start, groupID: response.group.id))
        XCTAssertNil(snapshot.currentLesson(at: lesson.start))
        XCTAssertNil(snapshot.currentLesson(at: StudyClock.date("2026-10-19")!))
        let restored = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.accent, .purple)
        XCTAssertEqual(restored.theme, "dark")
        XCTAssertNil(restored.currentLesson(at: lesson.start))
    }

    func testWidgetLooksAheadOnlyWhenTodayIsDone() throws {
        let response = try response()
        var snapshot = WidgetSnapshot(group: response.group, lessons: response.lessons,
                                      preferences: StudyPreferences(), updatedAt: .now)
        XCTAssertTrue(snapshot.upcomingDays(at: StudyClock.date("2026-10-12", time: "13:00")!).isEmpty)
        XCTAssertTrue(snapshot.upcomingDays(at: StudyClock.date("2026-10-12", time: "13:45")!).isEmpty)
        let evening = snapshot.upcomingDays(at: StudyClock.date("2026-10-12", time: "18:00")!)
        // Tuesday is military only, so the next study day is Wednesday; Saturday loses its military lesson.
        XCTAssertEqual(evening.map { StudyClock.string($0[0].start, format: "yyyy-MM-dd") },
                       ["2026-10-14", "2026-10-15", "2026-10-16", "2026-10-17"])
        XCTAssertEqual(evening.last?.count, 4)
        snapshot.preferences.finishedDays.insert(snapshot.preferences.dayKey(StudyClock.date("2026-10-12")!, groupID: response.group.id))
        XCTAssertEqual(snapshot.upcomingDays(at: StudyClock.date("2026-10-12", time: "12:30")!).first?.first?.subject, "Методы оптимизации")
    }

}
