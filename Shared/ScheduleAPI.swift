import Foundation

public struct ScheduleAPI: Sendable {
    public init() {}
    private let base = URL(string: "https://ruz.spbstu.ru/api/v1/ruz/")!

    public func week(groupID: Int, date: Date) async throws -> ScheduleResponse {
        try await get("scheduler/\(groupID)", query: [URLQueryItem(name: "date", value: StudyClock.string(date, format: "yyyy-MM-dd"))])
    }

    public func search(_ text: String) async throws -> [StudyGroup] {
        struct SearchResponse: Decodable { let groups: [StudyGroup] }
        let result: SearchResponse = try await get("search/groups", query: [URLQueryItem(name: "q", value: text)])
        return result.groups
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ScheduleError.unavailable
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw ScheduleError.invalidResponse }
    }
}

public enum ScheduleError: LocalizedError {
    case unavailable, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Сервис расписания временно недоступен. Попробуйте ещё раз."
        case .invalidResponse: "Не удалось прочитать расписание. Возможно, формат сервиса изменился."
        }
    }
}
