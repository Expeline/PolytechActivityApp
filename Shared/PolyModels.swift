import Foundation

/// JSON contract between the apps and PolyServer. Both sides compile this file.
public enum PolyCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

public struct DeviceRegistration: Codable, Sendable {
    public var displayName: String
    public init(displayName: String) { self.displayName = displayName }
}

public struct DeviceSession: Codable, Sendable {
    public let deviceID: UUID
    public let token: String
    public let displayName: String
    public init(deviceID: UUID, token: String, displayName: String) {
        self.deviceID = deviceID; self.token = token; self.displayName = displayName
    }
}

public struct GroupInfo: Codable, Sendable {
    public let group: StudyGroup
    public let subscribers: Int
    public let lastCheckedAt: Date?
    public init(group: StudyGroup, subscribers: Int, lastCheckedAt: Date?) {
        self.group = group; self.subscribers = subscribers; self.lastCheckedAt = lastCheckedAt
    }
}

public struct AssignmentDraft: Codable, Hashable, Sendable {
    /// Created on the device, so an offline create can be retried without duplicates.
    public var id: UUID
    public var subject: String
    public var lessonKind: String?
    public var title: String
    public var details: String
    public var dueAt: Date
    /// Set when the work is due at a specific lesson.
    public var dueLessonStart: Date?

    public init(id: UUID = UUID(), subject: String, lessonKind: String? = nil, title: String, details: String = "",
                dueAt: Date, dueLessonStart: Date? = nil) {
        self.id = id; self.subject = subject; self.lessonKind = lessonKind; self.title = title
        self.details = details; self.dueAt = dueAt; self.dueLessonStart = dueLessonStart
    }

    public static let titleLimit = 140
    public static let detailsLimit = 2_000

    /// Returns a user-facing problem, or nil when the draft can be published.
    public var problem: String? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return "Введите название задания." }
        if title.count > Self.titleLimit { return "Название длиннее \(Self.titleLimit) символов." }
        if details.count > Self.detailsLimit { return "Описание длиннее \(Self.detailsLimit) символов." }
        if subject.isEmpty || subject.count > 200 { return "Выберите предмет." }
        return nil
    }
}

public struct AssignmentDTO: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let groupID: Int
    public var subject: String
    public var lessonKind: String?
    public var title: String
    public var details: String
    public var dueAt: Date
    public var dueLessonStart: Date?
    public let authorName: String
    public let isMine: Bool
    public var completedCount: Int
    public var completedByMe: Bool
    public var reportedByMe: Bool
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, groupID: Int, subject: String, lessonKind: String?, title: String, details: String,
                dueAt: Date, dueLessonStart: Date?, authorName: String, isMine: Bool, completedCount: Int,
                completedByMe: Bool, reportedByMe: Bool, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.groupID = groupID; self.subject = subject; self.lessonKind = lessonKind
        self.title = title; self.details = details; self.dueAt = dueAt; self.dueLessonStart = dueLessonStart
        self.authorName = authorName; self.isMine = isMine; self.completedCount = completedCount
        self.completedByMe = completedByMe; self.reportedByMe = reportedByMe
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public var draft: AssignmentDraft {
        AssignmentDraft(id: id, subject: subject, lessonKind: lessonKind, title: title, details: details,
                        dueAt: dueAt, dueLessonStart: dueLessonStart)
    }
}

public struct AssignmentsPage: Codable, Sendable {
    /// Includes deleted or hidden items (with `deletedAt`) so clients can remove them.
    public let items: [AssignmentDTO]
    /// Pass back as `since` to receive only newer updates.
    public let serverTime: Date
    public init(items: [AssignmentDTO], serverTime: Date) { self.items = items; self.serverTime = serverTime }
}

public struct ChangesPage: Codable, Sendable {
    public let items: [ScheduleChange]
    public let serverTime: Date
    public init(items: [ScheduleChange], serverTime: Date) { self.items = items; self.serverTime = serverTime }
}

/// Sent over the group WebSocket. Clients react by running a delta sync.
public struct LiveEvent: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case assignments, changes }
    public let kind: Kind
    public let groupID: Int
    public init(kind: Kind, groupID: Int) { self.kind = kind; self.groupID = groupID }
}

public struct ServerProblem: Codable, Sendable {
    public let error: Bool
    public let reason: String
}
