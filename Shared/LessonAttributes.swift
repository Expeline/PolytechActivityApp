import ActivityKit
import Foundation

struct LessonAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let subject: String
        let kind: String
        let location: String
        let start: Date
        let end: Date
        let updatedAt: Date
        let ongoing: Bool?
        let accent: StudyAccent?
        let theme: String?
    }
    let groupName: String
}
