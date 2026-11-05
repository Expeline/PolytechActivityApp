import Fluent
import Foundation
import NIOConcurrencyHelpers
import PolytechCore
import Vapor

/// Re-downloads the schedule of every followed group and records what changed.
final class ScheduleWatcher: LifecycleHandler, Sendable {
    static let weeksAhead = 5 // current week + 4
    let interval: TimeInterval
    let enabled: Bool
    private let task = NIOLockedValueBox<Task<Void, Never>?>(nil)

    init(interval: TimeInterval, enabled: Bool) {
        self.interval = interval
        self.enabled = enabled
    }

    func didBootAsync(_ app: Application) async throws {
        guard enabled else { return }
        let interval = interval
        task.withLockedValue { $0 = Task {
            while !Task.isCancelled {
                await Self.checkAll(app: app)
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            }
        } }
    }

    func shutdownAsync(_ app: Application) async {
        task.withLockedValue { $0?.cancel(); $0 = nil }
    }

    static func checkAll(app: Application) async {
        do {
            let followed = Set(try await Subscription.query(on: app.db).all(\.$groupID))
            for groupID in followed.sorted() {
                guard !Task.isCancelled else { return }
                do {
                    let changes = try await check(groupID: groupID, db: app.db, source: app.scheduleSource, logger: app.logger)
                    if !changes.isEmpty { await app.live.broadcast(LiveEvent(kind: .changes, groupID: groupID)) }
                } catch {
                    app.logger.warning("Schedule check failed for \(groupID): \(String(reflecting: error))")
                }
            }
        } catch {
            app.logger.error("Schedule watcher: \(String(reflecting: error))")
        }
    }

    /// Fetches the coming weeks, compares them with stored snapshots and saves new changes.
    /// A week that fails to download keeps its old snapshot.
    @discardableResult
    static func check(groupID: Int, db: any Database, source: any ScheduleSource, logger: Logger,
                      now: Date = .now) async throws -> [ScheduleChange] {
        var detected: [ScheduleChange] = []
        var latestGroup: StudyGroup?
        for offset in 0..<weeksAhead {
            let monday = StudyClock.monday(StudyClock.addDays(offset * 7, to: now))
            let weekKey = StudyClock.string(monday, format: "yyyy-MM-dd")
            let response: ScheduleResponse
            do { response = try await source.week(groupID: groupID, date: monday) }
            catch {
                logger.info("Week \(weekKey) of \(groupID) unavailable: \(error)")
                continue
            }
            guard response.group.id == groupID else { continue }
            latestGroup = response.group
            let lessons = response.lessons
            if let snapshot = try await ScheduleSnapshot.query(on: db)
                .filter(\.$groupID == groupID).filter(\.$weekStart == weekKey).first() {
                detected += ScheduleDiff.changes(old: snapshot.lessons, new: lessons, after: now, detectedAt: now)
                snapshot.lessons = lessons
                snapshot.fetchedAt = now
                try await snapshot.save(on: db)
            } else {
                // First time we see this week: nothing to compare with yet.
                try await ScheduleSnapshot(groupID: groupID, weekStart: weekKey, lessons: lessons, fetchedAt: now).save(on: db)
            }
        }

        var fresh: [ScheduleChange] = []
        if !detected.isEmpty {
            var known = Set(try await ChangeRecord.query(on: db).filter(\.$groupID == groupID)
                .filter(\.$fingerprint ~~ detected.map(\.fingerprint)).all(\.$fingerprint))
            for change in detected where known.insert(change.fingerprint).inserted {
                try await ChangeRecord(groupID: groupID, change: change).save(on: db)
                fresh.append(change)
            }
        }
        if let record = try await GroupRecord.find(groupID, on: db) {
            if let latestGroup { record.update(from: latestGroup) }
            record.lastCheckedAt = now
            try await record.save(on: db)
        }
        return fresh
    }
}
