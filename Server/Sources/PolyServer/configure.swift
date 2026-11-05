import Fluent
import FluentPostgresDriver
import Foundation
import PolytechCore
import Vapor

@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = try await Application.make(env)
        do {
            try await configure(app)
            try await app.execute()
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}

func configure(_ app: Application) async throws {
    // Same JSON format as the apps (dates in milliseconds).
    ContentConfiguration.global.use(encoder: PolyCoding.encoder(), for: .json)
    ContentConfiguration.global.use(decoder: PolyCoding.decoder(), for: .json)

    let database = app.environment == .testing ? "polytech_test" : "polytech"
    let user = Environment.get("USER") ?? "postgres"
    let url = Environment.get("DATABASE_URL") ?? "postgres://\(user)@localhost:5432/\(database)?sslmode=disable"
    try app.databases.use(.postgres(url: url), as: .psql)
    app.migrations.add(CreateSchema())

    app.http.server.configuration.hostname = Environment.get("HOST") ?? "0.0.0.0"
    app.http.server.configuration.port = Environment.get("PORT").flatMap(Int.init) ?? 8080
    app.routes.defaultMaxBodySize = "64kb"

    if app.storage[ScheduleSourceKey.self] == nil { app.scheduleSource = ScheduleAPI() }
    let interval = Environment.get("WATCH_INTERVAL").flatMap(Double.init) ?? 900
    // Only the HTTP server watches schedules, not `migrate` or other commands.
    let command = app.environment.arguments.dropFirst().first ?? "serve"
    app.lifecycle.use(ScheduleWatcher(interval: interval, enabled: app.environment != .testing && command == "serve"))

    try routes(app)
}

// MARK: - Application storage

protocol ScheduleSource: Sendable {
    func week(groupID: Int, date: Date) async throws -> ScheduleResponse
}
extension ScheduleAPI: ScheduleSource {}

struct ScheduleSourceKey: StorageKey { typealias Value = any ScheduleSource }
struct LiveHubKey: StorageKey { typealias Value = LiveHub }

extension Application {
    var scheduleSource: any ScheduleSource {
        get { storage[ScheduleSourceKey.self] ?? ScheduleAPI() }
        set { storage[ScheduleSourceKey.self] = newValue }
    }
    var live: LiveHub {
        if let hub = storage[LiveHubKey.self] { return hub }
        let hub = LiveHub()
        storage[LiveHubKey.self] = hub
        return hub
    }
}
