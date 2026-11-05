import Fluent
import SQLKit

struct CreateSchema: AsyncMigration {
    func prepare(on db: Database) async throws {
        try await db.schema(Device.schema)
            .id()
            .field("token_hash", .string, .required)
            .field("display_name", .string, .required)
            .field("created_at", .datetime, .required)
            .field("last_seen_at", .datetime, .required)
            .unique(on: "token_hash")
            .create()

        try await db.schema(GroupRecord.schema)
            .field("ruz_id", .int, .identifier(auto: false))
            .field("name", .string, .required)
            .field("faculty_id", .int, .required)
            .field("faculty_name", .string, .required)
            .field("faculty_abbr", .string)
            .field("last_checked_at", .datetime)
            .create()

        try await db.schema(Subscription.schema)
            .id()
            .field("device_id", .uuid, .required, .references(Device.schema, .id, onDelete: .cascade))
            .field("group_id", .int, .required, .references(GroupRecord.schema, "ruz_id", onDelete: .cascade))
            .field("created_at", .datetime, .required)
            .unique(on: "device_id", "group_id")
            .create()

        try await db.schema(Assignment.schema)
            .id()
            .field("group_id", .int, .required, .references(GroupRecord.schema, "ruz_id", onDelete: .cascade))
            .field("subject", .string, .required)
            .field("lesson_kind", .string)
            .field("title", .string, .required)
            .field("details", .string, .required)
            .field("due_at", .datetime, .required)
            .field("due_lesson_start", .datetime)
            .field("author_id", .uuid, .required, .references(Device.schema, .id, onDelete: .cascade))
            .field("hidden", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .field("deleted_at", .datetime)
            .create()

        for table in [Completion.schema, Report.schema] {
            try await db.schema(table)
                .id()
                .field("assignment_id", .uuid, .required, .references(Assignment.schema, .id, onDelete: .cascade))
                .field("device_id", .uuid, .required, .references(Device.schema, .id, onDelete: .cascade))
                .field(table == Completion.schema ? "completed_at" : "created_at", .datetime, .required)
                .unique(on: "assignment_id", "device_id")
                .create()
        }

        try await db.schema(ScheduleSnapshot.schema)
            .id()
            .field("group_id", .int, .required, .references(GroupRecord.schema, "ruz_id", onDelete: .cascade))
            .field("week_start", .string, .required)
            .field("lessons", .json, .required)
            .field("fetched_at", .datetime, .required)
            .unique(on: "group_id", "week_start")
            .create()

        try await db.schema(ChangeRecord.schema)
            .id()
            .field("group_id", .int, .required, .references(GroupRecord.schema, "ruz_id", onDelete: .cascade))
            .field("fingerprint", .string, .required)
            .field("kind", .string, .required)
            .field("subject", .string, .required)
            .field("relevant_start", .datetime, .required)
            .field("detected_at", .datetime, .required)
            .field("payload", .json, .required)
            .unique(on: "group_id", "fingerprint")
            .create()

        if let sql = db as? any SQLDatabase {
            try await sql.raw("CREATE INDEX assignments_group_updated ON assignments (group_id, updated_at)").run()
            try await sql.raw("CREATE INDEX changes_group_detected ON schedule_changes (group_id, detected_at)").run()
        }
    }

    func revert(on db: Database) async throws {
        for table in [ChangeRecord.schema, ScheduleSnapshot.schema, Report.schema, Completion.schema,
                      Assignment.schema, Subscription.schema, GroupRecord.schema, Device.schema] {
            try await db.schema(table).delete()
        }
    }
}
