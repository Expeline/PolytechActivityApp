import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum StudyAccent: String, CaseIterable, Identifiable, Codable, Sendable {
    case green, blue, purple, pink, red, orange, yellow, teal, graphite
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .green: "Зелёный"; case .blue: "Синий"; case .purple: "Фиолетовый"
        case .pink: "Розовый"; case .red: "Красный"; case .orange: "Оранжевый"
        case .yellow: "Жёлтый"; case .teal: "Бирюзовый"; case .graphite: "Графитовый"
        }
    }
    var hue: Double {
        switch self {
        case .green: 0.39; case .blue: 0.60; case .purple: 0.75; case .pink: 0.91
        case .red: 0.0; case .orange: 0.075; case .yellow: 0.13; case .teal: 0.49; case .graphite: 0.60
        }
    }
}

#if canImport(SwiftUI)
extension StudyAccent {
    var color: Color { self == .green ? Color(red: 0.13, green: 0.45, blue: 0.30) : Color(hue: hue, saturation: self == .graphite ? 0.08 : 0.72, brightness: 0.78) }
    var background: Color { self == .green ? Color(red: 0.055, green: 0.25, blue: 0.18) : Color(hue: hue, saturation: self == .graphite ? 0.12 : 0.67, brightness: 0.30) }
    var highlight: Color { self == .green ? Color(red: 0.76, green: 0.94, blue: 0.54) : Color(hue: hue, saturation: self == .graphite ? 0.06 : 0.30, brightness: 0.98) }
}
#endif
