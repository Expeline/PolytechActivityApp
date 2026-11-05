import Fluent
import Foundation
import NIOConcurrencyHelpers
@testable import PolyServer
import PolytechCore
import XCTVapor

/// Serves the fixture week for any date; tests can edit the JSON to simulate RUZ changes.
final class FixtureSource: ScheduleSource, @unchecked Sendable {
    let json: NIOLockedValueBox<[String: Any]>
    init() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "week", withExtension: "json", subdirectory: "Fixtures"))
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json = NIOLockedValueBox(object)
    }
    func week(groupID: Int, date: Date) async throws -> ScheduleResponse {
        let data = try json.withLockedValue { try JSONSerialization.data(withJSONObject: $0) }
        let response = try JSONDecoder().decode(ScheduleResponse.self, from: data)
        guard response.group.id == groupID else { throw Abort(.notFound) }
        return response
    }
    /// Moves the first lesson of the first day to a new time on the same day.
    func moveFirstLesson(to start: String, end: String) {
        json.withLockedValue { object in
            var days = object["days"] as! [[String: Any]]
            var lessons = days[0]["lessons"] as! [[String: Any]]
            lessons[0]["time_start"] = start
            lessons[0]["time_end"] = end
            days[0]["lessons"] = lessons
            object["days"] = days
        }
    }
}

final class PolyServerTests: XCTestCase {
    let group = 45602
    var app: Application!
    var source: FixtureSource!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        source = try FixtureSource()
        app.scheduleSource = source
        try await configure(app)
        try await app.autoRevert()
        try await app.autoMigrate()
    }
    override func tearDown() async throws {
        try await app.autoRevert()
        try await app.asyncShutdown()
        app = nil
    }

    private func register(_ name: String) async throws -> DeviceSession {
        var session: DeviceSession?
        try await app.test(.POST, "v1/devices", beforeRequest: { try $0.content.encode(DeviceRegistration(displayName: name)) }) { res async throws in
            XCTAssertEqual(res.status, .ok)
            session = try res.content.decode(DeviceSession.self)
        }
        return try XCTUnwrap(session)
    }
    private func headers(_ session: DeviceSession) -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: session.token)
        return headers
    }
    private func subscribe(_ session: DeviceSession) async throws {
        try await app.test(.PUT, "v1/groups/\(group)/subscription", headers: headers(session)) { res async throws in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(try res.content.decode(GroupInfo.self).group.name, "5130904/40102")
        }
    }
    private func send<T: Decodable>(_ method: HTTPMethod, _ path: String, as session: DeviceSession,
                                    body: (any Encodable & Sendable)? = nil, expect status: HTTPStatus = .ok) async throws -> T? {
        var result: T?
        try await app.test(method, path, headers: headers(session), beforeRequest: { req in
            if let body { try req.content.encode(AnyEncodable(body), as: .json) }
        }) { res async throws in
            XCTAssertEqual(res.status, status, res.body.string)
            if res.status == .ok, status == .ok { result = try res.content.decode(T.self) }
        }
        return result
    }

    private func must<T: Decodable>(_ method: HTTPMethod, _ path: String, as session: DeviceSession,
                                    body: (any Encodable & Sendable)? = nil) async throws -> T {
        let value: T? = try await send(method, path, as: session, body: body)
        return try XCTUnwrap(value)
    }

    func testAssignmentsLifecycle() async throws {
        let alice = try await register("Алиса"), bob = try await register("Боб")
        let carol = try await register("Катя"), dan = try await register("Дима"), stranger = try await register("Чужой")
        for session in [alice, bob, carol, dan] { try await subscribe(session) }

        let draft = AssignmentDraft(subject: "Физика", lessonKind: "Практика", title: "Лабораторная 3",
                                    details: "Отчёт в LMS", dueAt: .now.addingTimeInterval(3 * 86_400))
        let created: AssignmentDTO = try await must(.POST, "v1/groups/\(group)/assignments", as: alice, body: draft)
        XCTAssertTrue(created.isMine)
        XCTAssertEqual(created.authorName, "Алиса")
        // Offline retry with the same id does not duplicate.
        let retried: AssignmentDTO = try await must(.POST, "v1/groups/\(group)/assignments", as: alice, body: draft)
        XCTAssertEqual(retried.id, created.id)

        let page: AssignmentsPage = try await must(.GET, "v1/groups/\(group)/assignments", as: bob)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertFalse(page.items[0].isMine)

        let done: AssignmentDTO = try await must(.PUT, "v1/assignments/\(created.id)/completion", as: bob)
        XCTAssertEqual(done.completedCount, 1)
        XCTAssertTrue(done.completedByMe)

        // Only the author edits; strangers cannot read the group without subscribing.
        let _: AssignmentDTO? = try await send(.PATCH, "v1/assignments/\(created.id)", as: bob, body: draft, expect: .forbidden)
        let _: AssignmentsPage? = try await send(.GET, "v1/groups/\(group)/assignments", as: stranger, expect: .forbidden)
        var edited = draft
        edited.title = "Лабораторная 3 (исправлено)"
        let renamed: AssignmentDTO = try await must(.PATCH, "v1/assignments/\(created.id)", as: alice, body: edited)
        XCTAssertEqual(renamed.title, "Лабораторная 3 (исправлено)")
        XCTAssertEqual(renamed.completedCount, 1)

        // Delta sync returns only items touched after the cursor.
        let cursor = Int64(page.serverTime.timeIntervalSince1970 * 1000)
        let delta: AssignmentsPage = try await must(.GET, "v1/groups/\(group)/assignments?since=\(cursor)", as: bob)
        XCTAssertEqual(delta.items.map(\.title), ["Лабораторная 3 (исправлено)"])
        let later = Int64(delta.serverTime.timeIntervalSince1970 * 1000) + 1
        let empty: AssignmentsPage = try await must(.GET, "v1/groups/\(group)/assignments?since=\(later)", as: bob)
        XCTAssertTrue(empty.items.isEmpty)

        // Three reports hide it for everyone; delta reports it as removed.
        let _: AssignmentDTO? = try await send(.POST, "v1/assignments/\(created.id)/report", as: alice, expect: .badRequest)
        for session in [bob, carol, dan] {
            let _: AssignmentDTO? = try await send(.POST, "v1/assignments/\(created.id)/report", as: session)
        }
        let afterReports: AssignmentsPage = try await must(.GET, "v1/groups/\(group)/assignments", as: bob)
        XCTAssertTrue(afterReports.items.isEmpty)
        let tombstones: AssignmentsPage = try await must(.GET, "v1/groups/\(group)/assignments?since=\(cursor)", as: bob)
        XCTAssertNotNil(tombstones.items.first?.deletedAt)
    }

    func testValidationRateLimitAndDelete() async throws {
        let alice = try await register("Алиса")
        try await subscribe(alice)
        let bad = AssignmentDraft(subject: "Физика", title: "  ", dueAt: .now)
        let _: AssignmentDTO? = try await send(.POST, "v1/groups/\(group)/assignments", as: alice, body: bad, expect: .badRequest)
        let farFuture = AssignmentDraft(subject: "Физика", title: "x", dueAt: .now.addingTimeInterval(1000 * 86_400))
        let _: AssignmentDTO? = try await send(.POST, "v1/groups/\(group)/assignments", as: alice, body: farFuture, expect: .badRequest)

        var last: AssignmentDTO?
        for index in 0..<assignmentHourlyLimit {
            last = try await send(.POST, "v1/groups/\(group)/assignments", as: alice,
                                  body: AssignmentDraft(subject: "Физика", title: "Задание \(index)", dueAt: .now.addingTimeInterval(86_400)))
        }
        let _: AssignmentDTO? = try await send(.POST, "v1/groups/\(group)/assignments", as: alice,
                                               body: AssignmentDraft(subject: "Физика", title: "Лишнее", dueAt: .now.addingTimeInterval(86_400)),
                                               expect: .tooManyRequests)
        let id = try XCTUnwrap(last?.id)
        try await app.test(.DELETE, "v1/assignments/\(id)", headers: headers(alice)) { res async in XCTAssertEqual(res.status, .noContent) }
        let page: AssignmentsPage = try await must(.GET, "v1/groups/\(group)/assignments", as: alice)
        XCTAssertEqual(page.items.count, assignmentHourlyLimit - 1)
        XCTAssertFalse(page.items.contains { $0.id == id })
    }

    func testWatcherRecordsMoveOnceAndServesIt() async throws {
        let beforeWeek = try XCTUnwrap(StudyClock.date("2026-10-11", time: "12:00"))
        let alice = try await register("Алиса")
        try await subscribe(alice)

        // First pass stores snapshots only.
        var changes = try await ScheduleWatcher.check(groupID: group, db: app.db, source: source, logger: app.logger, now: beforeWeek)
        XCTAssertTrue(changes.isEmpty)
        let snapshots = try await ScheduleSnapshot.query(on: app.db).count()
        XCTAssertEqual(snapshots, ScheduleWatcher.weeksAhead)

        source.moveFirstLesson(to: "20:00", end: "21:30")
        changes = try await ScheduleWatcher.check(groupID: group, db: app.db, source: source, logger: app.logger, now: beforeWeek)
        XCTAssertEqual(changes.map(\.kind), [.moved])
        // Same change seen again is not stored twice.
        changes = try await ScheduleWatcher.check(groupID: group, db: app.db, source: source, logger: app.logger, now: beforeWeek)
        XCTAssertTrue(changes.isEmpty)

        let page: ChangesPage = try await must(.GET, "v1/groups/\(group)/changes?since=0", as: alice)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.kind, .moved)
        XCTAssertEqual(page.items.first.map { StudyClock.string($0.new!.start, format: "HH:mm") }, "20:00")
    }

    func testUnknownGroupAndBadToken() async throws {
        let alice = try await register("Алиса")
        try await app.test(.PUT, "v1/groups/1/subscription", headers: headers(alice)) { res async in
            // RUZ does not know the group, so it cannot be verified.
            XCTAssertEqual(res.status, .badGateway)
        }
        var bad = HTTPHeaders()
        bad.bearerAuthorization = BearerAuthorization(token: "nope")
        try await app.test(.GET, "v1/groups/\(group)/assignments", headers: bad) { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
        try await app.test(.POST, "v1/devices", beforeRequest: { try $0.content.encode(DeviceRegistration(displayName: "")) }) { res async in
            XCTAssertEqual(res.status, .badRequest)
        }
    }
}

private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: any Encoder) throws { try value.encode(to: encoder) }
}
