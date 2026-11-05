import Fluent
import Foundation
import PolytechCore
import Vapor

/// An installed app. Anonymous: identified only by a random token kept in the device Keychain.
final class Device: Model, Authenticatable, @unchecked Sendable {
    static let schema = "devices"
    @ID(key: .id) var id: UUID?
    @Field(key: "token_hash") var tokenHash: String
    @Field(key: "display_name") var displayName: String
    @Field(key: "created_at") var createdAt: Date
    @Field(key: "last_seen_at") var lastSeenAt: Date
    init() {}
    init(tokenHash: String, displayName: String, now: Date = .now) {
        self.tokenHash = tokenHash; self.displayName = displayName; self.createdAt = now; self.lastSeenAt = now
    }
}

/// A RUZ group that at least one device follows. The primary key is the RUZ group id.
final class GroupRecord: Model, @unchecked Sendable {
    static let schema = "groups"
    @ID(custom: "ruz_id", generatedBy: .user) var id: Int?
    @Field(key: "name") var name: String
    @Field(key: "faculty_id") var facultyID: Int
    @Field(key: "faculty_name") var facultyName: String
    @OptionalField(key: "faculty_abbr") var facultyAbbr: String?
    @OptionalField(key: "last_checked_at") var lastCheckedAt: Date?
    init() {}
    init(_ group: StudyGroup) {
        id = group.id
        update(from: group)
    }
    func update(from group: StudyGroup) {
        name = group.name; facultyID = group.faculty.id; facultyName = group.faculty.name; facultyAbbr = group.faculty.abbr
    }
    var studyGroup: StudyGroup {
        StudyGroup(id: id ?? 0, name: name, faculty: Faculty(id: facultyID, name: facultyName, abbr: facultyAbbr))
    }
}

final class Subscription: Model, @unchecked Sendable {
    static let schema = "subscriptions"
    @ID(key: .id) var id: UUID?
    @Parent(key: "device_id") var device: Device
    @Field(key: "group_id") var groupID: Int
    @Field(key: "created_at") var createdAt: Date
    init() {}
    init(deviceID: UUID, groupID: Int) {
        self.$device.id = deviceID; self.groupID = groupID; self.createdAt = .now
    }
}

final class Assignment: Model, @unchecked Sendable {
    static let schema = "assignments"
    @ID(key: .id) var id: UUID?
    @Field(key: "group_id") var groupID: Int
    @Field(key: "subject") var subject: String
    @OptionalField(key: "lesson_kind") var lessonKind: String?
    @Field(key: "title") var title: String
    @Field(key: "details") var details: String
    @Field(key: "due_at") var dueAt: Date
    @OptionalField(key: "due_lesson_start") var dueLessonStart: Date?
    @Parent(key: "author_id") var author: Device
    @Field(key: "hidden") var hidden: Bool
    @Field(key: "created_at") var createdAt: Date
    // Bumped on every change, including completions by others, for delta sync.
    @Field(key: "updated_at") var updatedAt: Date
    @OptionalField(key: "deleted_at") var deletedAt: Date?
    init() {}
    init(draft: AssignmentDraft, groupID: Int, authorID: UUID, now: Date = .now) {
        id = draft.id; self.groupID = groupID; $author.id = authorID
        hidden = false; createdAt = now; updatedAt = now
        apply(draft)
    }
    func apply(_ draft: AssignmentDraft) {
        subject = draft.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        lessonKind = draft.lessonKind
        title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        details = draft.details.trimmingCharacters(in: .whitespacesAndNewlines)
        dueAt = draft.dueAt
        dueLessonStart = draft.dueLessonStart
    }
}

final class Completion: Model, @unchecked Sendable {
    static let schema = "assignment_completions"
    @ID(key: .id) var id: UUID?
    @Parent(key: "assignment_id") var assignment: Assignment
    @Parent(key: "device_id") var device: Device
    @Field(key: "completed_at") var completedAt: Date
    init() {}
    init(assignmentID: UUID, deviceID: UUID) {
        $assignment.id = assignmentID; $device.id = deviceID; completedAt = .now
    }
}

final class Report: Model, @unchecked Sendable {
    static let schema = "assignment_reports"
    @ID(key: .id) var id: UUID?
    @Parent(key: "assignment_id") var assignment: Assignment
    @Parent(key: "device_id") var device: Device
    @Field(key: "created_at") var createdAt: Date
    init() {}
    init(assignmentID: UUID, deviceID: UUID) {
        $assignment.id = assignmentID; $device.id = deviceID; createdAt = .now
    }
}

/// The last schedule the server saw for one group and week.
final class ScheduleSnapshot: Model, @unchecked Sendable {
    static let schema = "schedule_snapshots"
    @ID(key: .id) var id: UUID?
    @Field(key: "group_id") var groupID: Int
    @Field(key: "week_start") var weekStart: String
    // Wrapped so PostgreSQL stores one jsonb document, not a jsonb[] array.
    @Field(key: "lessons") var stored: StoredLessons
    @Field(key: "fetched_at") var fetchedAt: Date
    struct StoredLessons: Codable, Sendable { var lessons: [Lesson] }
    var lessons: [Lesson] {
        get { stored.lessons }
        set { stored = StoredLessons(lessons: newValue) }
    }
    init() {}
    init(groupID: Int, weekStart: String, lessons: [Lesson], fetchedAt: Date) {
        self.groupID = groupID; self.weekStart = weekStart; self.stored = StoredLessons(lessons: lessons); self.fetchedAt = fetchedAt
    }
}

final class ChangeRecord: Model, @unchecked Sendable {
    static let schema = "schedule_changes"
    @ID(key: .id) var id: UUID?
    @Field(key: "group_id") var groupID: Int
    @Field(key: "fingerprint") var fingerprint: String
    @Field(key: "kind") var kind: String
    @Field(key: "subject") var subject: String
    @Field(key: "relevant_start") var relevantStart: Date
    @Field(key: "detected_at") var detectedAt: Date
    @Field(key: "payload") var payload: ScheduleChange
    init() {}
    init(groupID: Int, change: ScheduleChange) {
        self.groupID = groupID; fingerprint = change.fingerprint; kind = change.kind.rawValue
        subject = change.subject; relevantStart = change.relevantStart; detectedAt = change.detectedAt; payload = change
    }
}
