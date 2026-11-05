import Fluent
import Foundation
import PolytechCore
import Vapor

extension DeviceRegistration: @retroactive Content {}
extension DeviceSession: @retroactive Content {}
extension GroupInfo: @retroactive Content {}
extension AssignmentDTO: @retroactive Content {}
extension AssignmentsPage: @retroactive Content {}
extension ChangesPage: @retroactive Content {}

/// Writes per device per hour; the group space is open, so this limits spam.
let assignmentHourlyLimit = 30

func routes(_ app: Application) throws {
    let v1 = app.grouped("v1")
    v1.get("health") { _ in ["status": "ok"] }
    v1.post("devices", use: registerDevice)

    let auth = v1.grouped(DeviceAuthenticator(), Device.guardMiddleware())
    auth.patch("devices", "me", use: renameDevice)
    auth.put("groups", ":groupID", "subscription", use: subscribe)
    auth.delete("groups", ":groupID", "subscription", use: unsubscribe)
    auth.get("groups", ":groupID", use: groupInfo)
    auth.get("groups", ":groupID", "assignments", use: listAssignments)
    auth.post("groups", ":groupID", "assignments", use: createAssignment)
    auth.patch("assignments", ":id", use: updateAssignment)
    auth.delete("assignments", ":id", use: deleteAssignment)
    auth.put("assignments", ":id", "completion") { try await setCompletion($0, done: true) }
    auth.delete("assignments", ":id", "completion") { try await setCompletion($0, done: false) }
    auth.post("assignments", ":id", "report", use: reportAssignment)
    auth.get("groups", ":groupID", "changes", use: listChanges)
    auth.webSocket("groups", ":groupID", "live", shouldUpgrade: { req in
        _ = try await requireSubscription(req)
        return [:]
    }, onUpgrade: { req, socket async in
        guard let groupID = req.parameters.get("groupID", as: Int.self) else { try? await socket.close(); return }
        socket.pingInterval = .seconds(25)
        let id = await req.application.live.add(socket, groupID: groupID)
        let hub = req.application.live
        socket.onClose.whenComplete { _ in Task { await hub.remove(id, groupID: groupID) } }
    })
}

// MARK: - Devices

private func cleanName(_ text: String) throws -> String {
    let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...40).contains(name.count) else { throw Abort(.badRequest, reason: "Имя должно быть от 1 до 40 символов.") }
    return name
}

@Sendable func registerDevice(_ req: Request) async throws -> DeviceSession {
    let body = try req.content.decode(DeviceRegistration.self)
    let token = Token.make()
    let device = Device(tokenHash: Token.hash(token), displayName: try cleanName(body.displayName))
    try await device.save(on: req.db)
    return DeviceSession(deviceID: try device.requireID(), token: token, displayName: device.displayName)
}

@Sendable func renameDevice(_ req: Request) async throws -> HTTPStatus {
    let device = try req.auth.require(Device.self)
    device.displayName = try cleanName(try req.content.decode(DeviceRegistration.self).displayName)
    try await device.save(on: req.db)
    return .noContent
}

// MARK: - Groups

private func groupID(_ req: Request) throws -> Int {
    guard let id = req.parameters.get("groupID", as: Int.self), id > 0 else { throw Abort(.badRequest, reason: "Неверный номер группы.") }
    return id
}

/// Anyone may join any group, but must subscribe first so the server watches its schedule.
@discardableResult
private func requireSubscription(_ req: Request, groupID explicit: Int? = nil) async throws -> (Device, Int) {
    let device = try req.auth.require(Device.self)
    let id = try explicit ?? groupID(req)
    guard try await Subscription.query(on: req.db).filter(\.$device.$id == device.requireID())
        .filter(\.$groupID == id).first() != nil else {
        throw Abort(.forbidden, reason: "Сначала подключитесь к группе.")
    }
    return (device, id)
}

private func info(_ record: GroupRecord, db: any Database) async throws -> GroupInfo {
    let id = try record.requireID()
    let count = try await Subscription.query(on: db).filter(\.$groupID == id).count()
    return GroupInfo(group: record.studyGroup, subscribers: count, lastCheckedAt: record.lastCheckedAt)
}

@Sendable func subscribe(_ req: Request) async throws -> GroupInfo {
    let device = try req.auth.require(Device.self)
    let id = try groupID(req)
    let record: GroupRecord
    if let existing = try await GroupRecord.find(id, on: req.db) {
        record = existing
    } else {
        // Validate the group with RUZ before storing it.
        let response: ScheduleResponse
        do { response = try await req.application.scheduleSource.week(groupID: id, date: .now) }
        catch { throw Abort(.badGateway, reason: "Не удалось проверить группу в РУЗ. Попробуйте позже.") }
        guard response.group.id == id else { throw Abort(.notFound, reason: "Группа не найдена.") }
        record = GroupRecord(response.group)
        try await record.create(on: req.db)
        let app = req.application
        // First snapshots in the background; changes are measured from here on.
        if app.environment != .testing { Task { try? await ScheduleWatcher.check(groupID: id, db: app.db, source: app.scheduleSource, logger: app.logger) } }
    }
    let deviceID = try device.requireID()
    if try await Subscription.query(on: req.db).filter(\.$device.$id == deviceID).filter(\.$groupID == id).first() == nil {
        try await Subscription(deviceID: deviceID, groupID: id).create(on: req.db)
    }
    return try await info(record, db: req.db)
}

@Sendable func unsubscribe(_ req: Request) async throws -> HTTPStatus {
    let device = try req.auth.require(Device.self)
    try await Subscription.query(on: req.db).filter(\.$device.$id == device.requireID())
        .filter(\.$groupID == groupID(req)).delete()
    return .noContent
}

@Sendable func groupInfo(_ req: Request) async throws -> GroupInfo {
    let (_, id) = try await requireSubscription(req)
    guard let record = try await GroupRecord.find(id, on: req.db) else { throw Abort(.notFound) }
    return try await info(record, db: req.db)
}

// MARK: - Assignments

private func since(_ req: Request) -> Date? {
    req.query[Int64.self, at: "since"].map { Date(timeIntervalSince1970: Double($0) / 1000) }
}

/// Builds responses for one viewer: counts completions, marks own items and own reports.
func dtos(_ items: [Assignment], viewer: UUID, db: any Database) async throws -> [AssignmentDTO] {
    let ids = items.compactMap(\.id)
    guard !ids.isEmpty else { return [] }
    let completions = try await Completion.query(on: db).filter(\.$assignment.$id ~~ ids).all()
    let reported = Set(try await Report.query(on: db).filter(\.$assignment.$id ~~ ids)
        .filter(\.$device.$id == viewer).all(\.$assignment.$id))
    let counts = Dictionary(grouping: completions, by: { $0.$assignment.id })
    return items.compactMap { item in
        guard let id = item.id else { return nil }
        let done = counts[id] ?? []
        let removed = item.deletedAt ?? (item.hidden ? item.updatedAt : nil)
        return AssignmentDTO(id: id, groupID: item.groupID, subject: item.subject, lessonKind: item.lessonKind,
                             title: item.title, details: item.details, dueAt: item.dueAt, dueLessonStart: item.dueLessonStart,
                             authorName: item.$author.value?.displayName ?? "Студент", isMine: item.$author.id == viewer,
                             completedCount: done.count, completedByMe: done.contains { $0.$device.id == viewer },
                             reportedByMe: reported.contains(id), createdAt: item.createdAt, updatedAt: item.updatedAt,
                             deletedAt: removed)
    }
}

@Sendable func listAssignments(_ req: Request) async throws -> AssignmentsPage {
    let serverTime = Date.now
    let (device, id) = try await requireSubscription(req)
    let query = Assignment.query(on: req.db).filter(\.$groupID == id).with(\.$author)
    if let since = since(req) {
        // Delta: everything touched since the cursor, including tombstones.
        query.filter(\.$updatedAt >= since)
    } else {
        query.filter(\.$deletedAt == nil).filter(\.$hidden == false)
            .filter(\.$dueAt >= serverTime.addingTimeInterval(-60 * 86_400))
    }
    let items = try await query.sort(\.$dueAt).limit(1000).all()
    return AssignmentsPage(items: try await dtos(items, viewer: device.requireID(), db: req.db), serverTime: serverTime)
}

private func validated(_ draft: AssignmentDraft) throws -> AssignmentDraft {
    if let problem = draft.problem { throw Abort(.badRequest, reason: problem) }
    let now = Date.now
    guard draft.dueAt > now.addingTimeInterval(-30 * 86_400), draft.dueAt < now.addingTimeInterval(400 * 86_400) else {
        throw Abort(.badRequest, reason: "Срок сдачи выглядит неверным.")
    }
    return draft
}

private func single(_ item: Assignment, viewer: UUID, db: any Database) async throws -> AssignmentDTO {
    try await item.$author.load(on: db)
    guard let dto = try await dtos([item], viewer: viewer, db: db).first else { throw Abort(.internalServerError) }
    return dto
}

@Sendable func createAssignment(_ req: Request) async throws -> AssignmentDTO {
    let (device, groupID) = try await requireSubscription(req)
    let deviceID = try device.requireID()
    let draft = try validated(try req.content.decode(AssignmentDraft.self))
    // Offline clients retry with the same id: answer with what was already saved.
    if let existing = try await Assignment.find(draft.id, on: req.db) {
        guard existing.$author.id == deviceID, existing.groupID == groupID else { throw Abort(.conflict) }
        return try await single(existing, viewer: deviceID, db: req.db)
    }
    let recent = try await Assignment.query(on: req.db).filter(\.$author.$id == deviceID)
        .filter(\.$createdAt >= Date.now.addingTimeInterval(-3600)).count()
    guard recent < assignmentHourlyLimit else { throw Abort(.tooManyRequests, reason: "Слишком много заданий за час.") }
    let item = Assignment(draft: draft, groupID: groupID, authorID: deviceID)
    try await item.create(on: req.db)
    await req.application.live.broadcast(LiveEvent(kind: .assignments, groupID: groupID))
    return try await single(item, viewer: deviceID, db: req.db)
}

/// Loads a live assignment and checks that the caller belongs to its group.
private func loadAssignment(_ req: Request) async throws -> (Assignment, UUID) {
    guard let id = req.parameters.get("id", as: UUID.self),
          let item = try await Assignment.find(id, on: req.db), item.deletedAt == nil else {
        throw Abort(.notFound, reason: "Задание не найдено или удалено.")
    }
    let (device, _) = try await requireSubscription(req, groupID: item.groupID)
    return (item, try device.requireID())
}

@Sendable func updateAssignment(_ req: Request) async throws -> AssignmentDTO {
    let (item, deviceID) = try await loadAssignment(req)
    guard item.$author.id == deviceID else { throw Abort(.forbidden, reason: "Изменять задание может только автор.") }
    var draft = try req.content.decode(AssignmentDraft.self)
    draft.id = try item.requireID()
    item.apply(try validated(draft))
    item.updatedAt = .now
    try await item.save(on: req.db)
    await req.application.live.broadcast(LiveEvent(kind: .assignments, groupID: item.groupID))
    return try await single(item, viewer: deviceID, db: req.db)
}

@Sendable func deleteAssignment(_ req: Request) async throws -> HTTPStatus {
    let (item, deviceID) = try await loadAssignment(req)
    guard item.$author.id == deviceID else { throw Abort(.forbidden, reason: "Удалить задание может только автор.") }
    item.deletedAt = .now
    item.updatedAt = .now
    try await item.save(on: req.db)
    await req.application.live.broadcast(LiveEvent(kind: .assignments, groupID: item.groupID))
    return .noContent
}

@Sendable func setCompletion(_ req: Request, done: Bool) async throws -> AssignmentDTO {
    let (item, deviceID) = try await loadAssignment(req)
    let assignmentID = try item.requireID()
    let existing = try await Completion.query(on: req.db).filter(\.$assignment.$id == assignmentID)
        .filter(\.$device.$id == deviceID).first()
    if done, existing == nil { try await Completion(assignmentID: assignmentID, deviceID: deviceID).create(on: req.db) }
    if !done, let existing { try await existing.delete(on: req.db) }
    item.updatedAt = .now
    try await item.save(on: req.db)
    await req.application.live.broadcast(LiveEvent(kind: .assignments, groupID: item.groupID))
    return try await single(item, viewer: deviceID, db: req.db)
}

/// Three reports from different devices hide an assignment for everyone.
let reportsToHide = 3

@Sendable func reportAssignment(_ req: Request) async throws -> AssignmentDTO {
    let (item, deviceID) = try await loadAssignment(req)
    let assignmentID = try item.requireID()
    guard item.$author.id != deviceID else { throw Abort(.badRequest, reason: "Нельзя пожаловаться на своё задание.") }
    if try await Report.query(on: req.db).filter(\.$assignment.$id == assignmentID).filter(\.$device.$id == deviceID).first() == nil {
        try await Report(assignmentID: assignmentID, deviceID: deviceID).create(on: req.db)
    }
    let reports = try await Report.query(on: req.db).filter(\.$assignment.$id == assignmentID).count()
    if reports >= reportsToHide, !item.hidden {
        item.hidden = true
        item.updatedAt = .now
        try await item.save(on: req.db)
        await req.application.live.broadcast(LiveEvent(kind: .assignments, groupID: item.groupID))
    }
    return try await single(item, viewer: deviceID, db: req.db)
}

// MARK: - Schedule changes

@Sendable func listChanges(_ req: Request) async throws -> ChangesPage {
    let serverTime = Date.now
    let (_, id) = try await requireSubscription(req)
    let limit = min(max(req.query[Int.self, at: "limit"] ?? 200, 1), 500)
    let query = ChangeRecord.query(on: req.db).filter(\.$groupID == id)
    if let since = since(req) { query.filter(\.$detectedAt >= since) }
    else { query.filter(\.$detectedAt >= serverTime.addingTimeInterval(-120 * 86_400)) }
    let items = try await query.sort(\.$detectedAt, .descending).limit(limit).all()
    return ChangesPage(items: items.map(\.payload), serverTime: serverTime)
}
