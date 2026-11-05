import Foundation
import Security

enum PolyServerError: LocalizedError {
    case badAddress, unauthorized, unreachable, rejected(String)
    var errorDescription: String? {
        switch self {
        case .badAddress: "Адрес сервера должен начинаться с http:// или https://"
        case .unauthorized: "Сервер не узнал это устройство."
        case .unreachable: "Сервер группы недоступен. Изменения сохранятся и отправятся позже."
        case .rejected(let reason): reason
        }
    }
    /// Network trouble: keep queued actions and retry later.
    var isTransient: Bool {
        if case .unreachable = self { return true }
        return false
    }
}

/// Talks to PolyServer. Stateless; the caller provides the token.
struct PolyServerClient: Sendable {
    let base: URL
    var token: String?

    init(address: String, token: String? = nil) throws {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme ?? ""), url.host() != nil else {
            throw PolyServerError.badAddress
        }
        base = url
        self.token = token
    }

    func send<Response: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [],
                                   body: (any Encodable)? = nil, as: Response.Type = Response.self) async throws -> Response {
        let data = try await raw(method, path, query: query, body: body)
        do { return try PolyCoding.decoder().decode(Response.self, from: data) }
        catch { throw PolyServerError.rejected("Сервер ответил в неизвестном формате. Обновите приложение и сервер.") }
    }

    func perform(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws {
        _ = try await raw(method, path, query: [], body: body)
    }

    private func raw(_ method: String, _ path: String, query: [URLQueryItem], body: (any Encodable)?) async throws -> Data {
        var components = URLComponents(url: base.appending(path: "v1/" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try PolyCoding.encoder().encode(body)
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw PolyServerError.unreachable }
        guard let http = response as? HTTPURLResponse else { throw PolyServerError.unreachable }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw PolyServerError.unauthorized
        case 500..<600 where http.statusCode != 502: throw PolyServerError.unreachable
        default:
            let reason = (try? JSONDecoder().decode(ServerProblem.self, from: data))?.reason
            throw PolyServerError.rejected(reason ?? "Сервер отклонил запрос (\(http.statusCode)).")
        }
    }

    /// Opens the live channel of a group. Messages are `LiveEvent` JSON.
    func liveSocket(groupID: Int) -> URLSessionWebSocketTask? {
        guard var components = URLComponents(url: base.appending(path: "v1/groups/\(groupID)/live"), resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return URLSession.shared.webSocketTask(with: request)
    }
}

/// The device session lives in the Keychain, never in UserDefaults.
enum SessionKeychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Polytech.Server",
         kSecAttrAccount as String: account]
    }
    static func load(server: String) -> DeviceSession? {
        var request = query(server)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(DeviceSession.self, from: data)
    }
    static func save(_ session: DeviceSession?, server: String) {
        SecItemDelete(query(server) as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var item = query(server)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
