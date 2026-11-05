import Fluent
import Foundation
import PolytechCore
import Vapor

/// Bearer token → device. Tokens are stored only as SHA-256 hashes.
struct DeviceAuthenticator: AsyncBearerAuthenticator {
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        guard let device = try await Device.query(on: request.db)
            .filter(\.$tokenHash == Token.hash(bearer.token)).first() else { return }
        if Date.now.timeIntervalSince(device.lastSeenAt) > 3600 {
            device.lastSeenAt = .now
            try await device.save(on: request.db)
        }
        request.auth.login(device)
    }
}

enum Token {
    static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Open WebSockets per group. Events only say "something changed"; clients then sync.
actor LiveHub {
    private var sockets: [Int: [UUID: WebSocket]] = [:]

    func add(_ socket: WebSocket, groupID: Int) -> UUID {
        let id = UUID()
        sockets[groupID, default: [:]][id] = socket
        return id
    }
    func remove(_ id: UUID, groupID: Int) {
        sockets[groupID]?[id] = nil
        if sockets[groupID]?.isEmpty == true { sockets[groupID] = nil }
    }
    func count(groupID: Int) -> Int { sockets[groupID]?.count ?? 0 }

    func broadcast(_ event: LiveEvent) async {
        guard let targets = sockets[event.groupID]?.values,
              let data = try? PolyCoding.encoder().encode(event),
              let text = String(data: data, encoding: .utf8) else { return }
        for socket in targets where !socket.isClosed {
            try? await socket.send(text)
        }
    }
}
