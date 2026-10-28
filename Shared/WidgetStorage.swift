import Foundation
#if os(iOS)
import Security
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

struct WidgetSnapshot: Codable {
    var group: StudyGroup
    var lessons: [Lesson]
    var preferences: StudyPreferences
    var updatedAt: Date
    var accent: StudyAccent? = nil
    var theme: String? = nil

    func currentLesson(at date: Date) -> Lesson? {
        Lesson.current(in: preferences.eligible(lessons, groupID: group.id, now: date), at: date, skipMilitary: false)
    }
}

enum WidgetStorage {
    #if os(iOS)
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Polytech.WidgetSnapshot",
         kSecAttrAccount as String: "schedule",
         kSecAttrAccessGroup as String: Bundle.main.object(forInfoDictionaryKey: "WidgetKeychainGroup") as? String ?? ""]
    }
    #else
    private static var sharedURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "ZJ5493ZDP5.ru.arthur.Polytech.shared")?.appendingPathComponent("snapshot.json")
    }
    #endif

    @discardableResult static func save(_ snapshot: WidgetSnapshot) -> Bool {
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        #if os(iOS)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { return false }
        #else
        guard let url = sharedURL else { return false }
        do { try data.write(to: url, options: .atomic) } catch { return false }
        #endif
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return true
    }
    static func read() -> WidgetSnapshot? {
        #if os(iOS)
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        #else
        guard let url = sharedURL, let data = try? Data(contentsOf: url) else { return nil }
        #endif
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
