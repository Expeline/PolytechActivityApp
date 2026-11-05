import Foundation
import Observation

/// An action taken offline, sent to the server in order once it is reachable.
enum OutboxAction: Codable, Hashable, Sendable {
    case create(groupID: Int, draft: AssignmentDraft)
    case update(draft: AssignmentDraft)
    case delete(id: UUID)
    case complete(id: UUID, done: Bool)
    case report(id: UUID)

    var assignmentID: UUID {
        switch self {
        case .create(_, let draft), .update(let draft): draft.id
        case .delete(let id), .complete(let id, _), .report(let id): id
        }
    }
}

/// Everything PolyStudy and PolyChanges keep on the device.
struct StudyState: Codable {
    var changes: [Int: [ScheduleChange]] = [:]
    var changesSeenAt: [Int: Date] = [:]
    var assignments: [Int: [AssignmentDTO]] = [:]
    var assignmentsCursor: [Int: Date] = [:]
    var changesCursor: [Int: Date] = [:]
    var subscribed: Set<String> = []
    var outbox: [OutboxAction] = []
}

enum ServerStatus: Equatable {
    case off, connecting, online, offline(String)
    var title: String {
        switch self {
        case .off: "Сервер не указан — задания хранятся только здесь"
        case .connecting: "Подключаемся…"
        case .online: "Подключено"
        case .offline(let reason): reason
        }
    }
}

enum StudySection: String, CaseIterable, Identifiable {
    case schedule, assignments, changes
    var id: String { rawValue }
    var title: String {
        switch self { case .schedule: "Расписание"; case .assignments: "Задания"; case .changes: "Изменения" }
    }
}

@MainActor @Observable
final class StudyStore {
    private(set) var state: StudyState { didSet { persist() } }
    var status: ServerStatus = .off
    var lastError: String?
    var serverAddress: String { didSet { UserDefaults.standard.set(serverAddress, forKey: "serverAddress"); resetConnection() } }
    var displayName: String { didSet { UserDefaults.standard.set(displayName, forKey: "displayName") } }
    var notifyChanges: Bool { didSet { UserDefaults.standard.set(notifyChanges, forKey: "notifyChanges") } }
    var notifyDeadlines: Bool { didSet { UserDefaults.standard.set(notifyDeadlines, forKey: "notifyDeadlines"); Task { await rescheduleDeadlines() } } }

    private let fileURL: URL
    private var syncing = false
    private var syncAgain = false
    private var liveTask: Task<Void, Never>?
    private var liveGroup: Int?
    private var currentGroupID: Int?
    static let historyDays = 120.0

    static var defaultAddress: String {
        #if os(macOS) || targetEnvironment(simulator)
        "http://localhost:8080"
        #else
        ""
        #endif
    }

    init() {
        let defaults = UserDefaults.standard
        serverAddress = defaults.string(forKey: "serverAddress") ?? Self.defaultAddress
        displayName = defaults.string(forKey: "displayName") ?? ""
        notifyChanges = defaults.object(forKey: "notifyChanges") as? Bool ?? true
        notifyDeadlines = defaults.object(forKey: "notifyDeadlines") as? Bool ?? true
        let folder = URL.applicationSupportDirectory.appendingPathComponent("Polytech", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("study.json")
        state = (try? Data(contentsOf: fileURL)).flatMap { try? PolyCoding.decoder().decode(StudyState.self, from: $0) } ?? StudyState()
    }

    private func persist() {
        guard let data = try? PolyCoding.encoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - PolyChanges

    func changes(groupID: Int) -> [ScheduleChange] { state.changes[groupID] ?? [] }

    func unseenChanges(groupID: Int) -> Int {
        let seen = state.changesSeenAt[groupID] ?? .distantPast
        return changes(groupID: groupID).filter { $0.detectedAt > seen }.count
    }
    func markChangesSeen(groupID: Int) {
        guard unseenChanges(groupID: groupID) > 0 else { return }
        state.changesSeenAt[groupID] = .now
    }

    /// Called by ScheduleStore when a cached week is replaced by a fresh download.
    func recordLocal(old: [Lesson], new: [Lesson], groupID: Int, now: Date = .now) {
        let detected = ScheduleDiff.changes(old: old, new: new, after: now, detectedAt: now)
        guard !detected.isEmpty else { return }
        let known = Set(changes(groupID: groupID).map(\.id))
        let fresh = detected.filter { !known.contains($0.id) }
        merge(changes: detected, groupID: groupID)
        if notifyChanges, !fresh.isEmpty { Task { await StudyNotifications.announce(fresh) } }
    }

    private func merge(changes incoming: [ScheduleChange], groupID: Int) {
        let cutoff = Date.now.addingTimeInterval(-Self.historyDays * 86_400)
        state.changes[groupID] = ScheduleDiff.merge(changes(groupID: groupID), incoming, keepAfter: cutoff)
    }

    /// Recent change describing this lesson as it stands now (moved here, new room…).
    func change(for lesson: Lesson, groupID: Int, within days: Double = 7) -> ScheduleChange? {
        let cutoff = Date.now.addingTimeInterval(-days * 86_400)
        return changes(groupID: groupID).first { $0.detectedAt > cutoff && $0.describes(lesson) }
    }

    /// Lessons that used to be on this day but were cancelled or moved away.
    func vanished(on day: Date, current: [Lesson], groupID: Int) -> [ScheduleChange] {
        changes(groupID: groupID).filter { change in
            guard change.kind == .cancelled || change.kind == .moved, let old = change.old,
                  StudyClock.calendar.isDate(old.start, inSameDayAs: day) else { return false }
            // Still there (e.g. moved back): nothing vanished.
            return !current.contains { $0.subject == change.subject && $0.kind == change.lessonKind && $0.start == old.start }
        }
        .reduce(into: [ScheduleChange]()) { result, change in
            // Keep only the most recent record per original slot.
            if !result.contains(where: { $0.subject == change.subject && $0.old?.start == change.old?.start }) { result.append(change) }
        }
        .sorted { ($0.old?.start ?? .distantPast) < ($1.old?.start ?? .distantPast) }
    }

    // MARK: - PolyStudy (local first)

    func assignments(groupID: Int) -> [AssignmentDTO] {
        (state.assignments[groupID] ?? []).filter { $0.deletedAt == nil }.sorted { $0.dueAt < $1.dueAt }
    }

    func openAssignments(for lesson: Lesson, groupID: Int) -> [AssignmentDTO] {
        assignments(groupID: groupID).filter { !$0.completedByMe && $0.isDue(at: lesson) }
    }

    func pending(_ id: UUID) -> Bool { state.outbox.contains { $0.assignmentID == id } }

    func create(_ draft: AssignmentDraft, groupID: Int) {
        let now = Date.now
        let item = AssignmentDTO(id: draft.id, groupID: groupID, subject: draft.subject, lessonKind: draft.lessonKind,
                                 title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                 details: draft.details.trimmingCharacters(in: .whitespacesAndNewlines),
                                 dueAt: draft.dueAt, dueLessonStart: draft.dueLessonStart,
                                 authorName: displayName.isEmpty ? "Вы" : displayName, isMine: true,
                                 completedCount: 0, completedByMe: false, reportedByMe: false,
                                 createdAt: now, updatedAt: now, deletedAt: nil)
        upsert(item)
        enqueue(.create(groupID: groupID, draft: draft))
    }

    func update(_ draft: AssignmentDraft, groupID: Int) {
        guard var item = state.assignments[groupID]?.first(where: { $0.id == draft.id }) else { return }
        item.subject = draft.subject; item.lessonKind = draft.lessonKind; item.title = draft.title
        item.details = draft.details; item.dueAt = draft.dueAt; item.dueLessonStart = draft.dueLessonStart
        upsert(item)
        // Not on the server yet: fold the edit into the queued create.
        if let index = state.outbox.firstIndex(where: { if case .create(_, let queued) = $0 { queued.id == draft.id } else { false } }) {
            state.outbox[index] = .create(groupID: groupID, draft: draft)
        } else {
            enqueue(.update(draft: draft))
        }
    }

    func setDone(_ item: AssignmentDTO, _ done: Bool) {
        guard item.completedByMe != done else { return }
        var copy = item
        copy.completedByMe = done
        copy.completedCount = max(0, item.completedCount + (done ? 1 : -1))
        upsert(copy)
        state.outbox.removeAll { if case .complete(let id, _) = $0 { id == item.id } else { false } }
        enqueue(.complete(id: item.id, done: done))
    }

    func delete(_ item: AssignmentDTO) {
        state.assignments[item.groupID]?.removeAll { $0.id == item.id }
        let neverSent = state.outbox.contains { if case .create(_, let draft) = $0 { draft.id == item.id } else { false } }
        state.outbox.removeAll { $0.assignmentID == item.id }
        if !neverSent { enqueue(.delete(id: item.id)) }
        Task { await rescheduleDeadlines() }
    }

    func report(_ item: AssignmentDTO) {
        var copy = item
        copy.reportedByMe = true
        upsert(copy)
        enqueue(.report(id: item.id))
    }

    private func upsert(_ item: AssignmentDTO) {
        var list = state.assignments[item.groupID] ?? []
        if let index = list.firstIndex(where: { $0.id == item.id }) { list[index] = item } else { list.append(item) }
        state.assignments[item.groupID] = list
    }

    private func enqueue(_ action: OutboxAction) {
        state.outbox.append(action)
        Task { await rescheduleDeadlines(); await sync() }
    }

    func rescheduleDeadlines() async {
        let all = state.assignments.values.flatMap { $0 }
        await StudyNotifications.scheduleDeadlines(all.filter { $0.groupID == currentGroupID }, enabled: notifyDeadlines)
    }

    // MARK: - Server sync

    private var client: PolyServerClient? {
        guard !serverAddress.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return try? PolyServerClient(address: serverAddress, token: SessionKeychain.load(server: serverKey)?.token)
    }
    private var serverKey: String { serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private func resetConnection() {
        stopLive()
        status = serverAddress.isEmpty ? .off : .connecting
    }

    /// Switches to another group; the previous group's data stays cached.
    func select(groupID: Int) {
        guard currentGroupID != groupID else { return }
        currentGroupID = groupID
        stopLive()
        Task { await sync(); await rescheduleDeadlines() }
    }

    func renameOnServer() async {
        guard let client, client.token != nil, !displayName.isEmpty else { return }
        try? await client.perform("PATCH", "devices/me", body: DeviceRegistration(displayName: displayName))
    }

    /// Sends queued actions, then pulls new assignments and changes. Safe to call often.
    func sync() async {
        guard let groupID = currentGroupID else { return }
        guard var client else {
            status = serverAddress.isEmpty ? .off : .offline(PolyServerError.badAddress.localizedDescription)
            return
        }
        guard !syncing else { syncAgain = true; return }
        syncing = true
        defer { syncing = false }
        if status != .online { status = .connecting }
        do {
            client = try await authorized(client)
            try await ensureSubscribed(groupID, client: client)
            try await flushOutbox(client: client)
            try await pull(groupID, client: client)
            status = .online
            lastError = nil
            startLive(groupID: groupID, client: client)
        } catch PolyServerError.unauthorized {
            // The server forgot us (e.g. database reset): register again next time.
            SessionKeychain.save(nil, server: serverKey)
            state.subscribed = state.subscribed.filter { !$0.hasPrefix(serverKey + "#") }
            status = .offline("Переподключаемся к серверу…")
            syncAgain = true
        } catch {
            status = .offline((error as? PolyServerError)?.errorDescription ?? error.localizedDescription)
        }
        if syncAgain {
            syncAgain = false
            Task { await sync() }
        }
    }

    private func authorized(_ client: PolyServerClient) async throws -> PolyServerClient {
        if client.token != nil { return client }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let session: DeviceSession = try await client.send("POST", "devices", body: DeviceRegistration(displayName: name.isEmpty ? "Студент" : name))
        SessionKeychain.save(session, server: serverKey)
        var copy = client
        copy.token = session.token
        return copy
    }

    private func ensureSubscribed(_ groupID: Int, client: PolyServerClient) async throws {
        let key = "\(serverKey)#\(groupID)"
        guard !state.subscribed.contains(key) else { return }
        let _: GroupInfo = try await client.send("PUT", "groups/\(groupID)/subscription")
        state.subscribed.insert(key)
    }

    private func flushOutbox(client: PolyServerClient) async throws {
        while let action = state.outbox.first {
            do {
                switch action {
                case .create(let groupID, let draft):
                    upsert(try await client.send("POST", "groups/\(groupID)/assignments", body: draft, as: AssignmentDTO.self))
                case .update(let draft):
                    upsert(try await client.send("PATCH", "assignments/\(draft.id)", body: draft, as: AssignmentDTO.self))
                case .delete(let id):
                    try await client.perform("DELETE", "assignments/\(id)")
                case .complete(let id, let done):
                    upsert(try await client.send(done ? "PUT" : "DELETE", "assignments/\(id)/completion", as: AssignmentDTO.self))
                case .report(let id):
                    upsert(try await client.send("POST", "assignments/\(id)/report", as: AssignmentDTO.self))
                }
            } catch PolyServerError.rejected(let reason) {
                // The server will never accept this action: drop it and tell the user.
                lastError = reason
                if case .create(let groupID, let draft) = action {
                    state.assignments[groupID]?.removeAll { $0.id == draft.id }
                }
            }
            state.outbox.removeFirst()
        }
    }

    private func pull(_ groupID: Int, client: PolyServerClient) async throws {
        func cursor(_ date: Date?) -> [URLQueryItem] {
            date.map { [URLQueryItem(name: "since", value: String(Int64($0.timeIntervalSince1970 * 1000)))] } ?? []
        }
        let page: AssignmentsPage = try await client.send("GET", "groups/\(groupID)/assignments", query: cursor(state.assignmentsCursor[groupID]))
        var list = state.assignmentsCursor[groupID] == nil ? [] : (state.assignments[groupID] ?? [])
        for item in page.items {
            list.removeAll { $0.id == item.id }
            if item.deletedAt == nil { list.append(item) }
        }
        // Keep local items that are still waiting in the outbox.
        for local in state.assignments[groupID] ?? [] where pending(local.id) && !list.contains(where: { $0.id == local.id }) {
            list.append(local)
        }
        state.assignments[groupID] = list.filter { $0.dueAt > Date.now.addingTimeInterval(-60 * 86_400) }
        state.assignmentsCursor[groupID] = page.serverTime

        let firstPull = state.changesCursor[groupID] == nil
        let changes: ChangesPage = try await client.send("GET", "groups/\(groupID)/changes", query: cursor(state.changesCursor[groupID]))
        let known = Set(self.changes(groupID: groupID).map(\.id))
        let fresh = changes.items.filter { !known.contains($0.id) }
        merge(changes: changes.items, groupID: groupID)
        state.changesCursor[groupID] = changes.serverTime
        // The first download is history, not news.
        if notifyChanges, !firstPull, !fresh.isEmpty { await StudyNotifications.announce(fresh) }
        await rescheduleDeadlines()
    }

    // MARK: - Live updates while the app is open

    private func startLive(groupID: Int, client: PolyServerClient) {
        guard liveTask == nil || liveGroup != groupID else { return }
        stopLive()
        liveGroup = groupID
        liveTask = Task { [weak self] in
            var delay: Duration = .seconds(2)
            while !Task.isCancelled {
                guard let socket = client.liveSocket(groupID: groupID) else { return }
                socket.resume()
                do {
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        delay = .seconds(2)
                        if case .string(let text) = message,
                           let event = try? PolyCoding.decoder().decode(LiveEvent.self, from: Data(text.utf8)),
                           event.groupID == groupID {
                            await self?.sync()
                        }
                    }
                } catch {
                    socket.cancel(with: .goingAway, reason: nil)
                }
                try? await Task.sleep(for: delay)
                delay = min(delay * 2, .seconds(60))
            }
        }
    }

    func stopLive() {
        liveTask?.cancel()
        liveTask = nil
        liveGroup = nil
    }
}

extension AssignmentDTO {
    /// Due at this lesson: either linked to it, or due the same day for the same subject.
    func isDue(at lesson: Lesson) -> Bool {
        guard subject == lesson.subject else { return false }
        if let start = dueLessonStart { return start == lesson.start }
        return StudyClock.calendar.isDate(dueAt, inSameDayAs: lesson.start) && dueAt >= lesson.start.addingTimeInterval(-3600)
    }
    var isOverdue: Bool { !completedByMe && dueAt < .now }
}
