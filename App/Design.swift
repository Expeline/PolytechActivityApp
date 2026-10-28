import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum Palette {
    static let green = Color("AccentColor")
    static let canvas = Color("Canvas")
    static let card = Color("Card")
    static let forest = Color(red: 0.055, green: 0.25, blue: 0.18)
    static let mint = Color(red: 0.76, green: 0.94, blue: 0.54)
}

private struct StudyAccentKey: EnvironmentKey { static let defaultValue = StudyAccent.green }
extension EnvironmentValues {
    var studyAccent: StudyAccent {
        get { self[StudyAccentKey.self] }
        set { self[StudyAccentKey.self] = newValue }
    }
}
private struct StudyAppearance: ViewModifier {
    let store: ScheduleStore
    @Environment(\.colorScheme) private var inheritedScheme
    @State private var detectedSystemScheme: ColorScheme?
    private var systemScheme: ColorScheme {
        // A sheet can retain its old inherited scheme after preferredColorScheme
        // returns to nil. Read the display's traits, not a window's override.
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        #else
        return NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        #endif
    }
    func body(content: Content) -> some View {
        let _ = inheritedScheme // Re-evaluate system traits when the host appearance changes.
        content
            .environment(\.colorScheme, store.theme.colorScheme ?? detectedSystemScheme ?? systemScheme)
            .environment(\.studyAccent, store.accent)
            .preferredColorScheme(store.theme.colorScheme)
            .tint(store.accent.color)
            .task(id: "\(store.accent.rawValue)-\(store.useAccentIcon)") { await store.updateIcon() }
            .task(id: store.theme) {
                detectedSystemScheme = systemScheme
                guard store.theme == .system else { return }
                // The hosting sheet can keep its old environment even when the
                // screen changes. Sample only while visible in system mode.
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    detectedSystemScheme = systemScheme
                }
            }
    }
}
extension View {
    func studyAppearance(_ store: ScheduleStore) -> some View { modifier(StudyAppearance(store: store)) }
}

struct Eyebrow: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.7).foregroundStyle(.secondary) }
}
struct StatusNote: View {
    let text: String
    var body: some View { Text(text).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 16)) }
}
struct SoftButton: ButtonStyle {
    @Environment(\.studyAccent) private var accent
    var emphasized = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 12)
            .foregroundStyle(emphasized ? Color.white : Color.primary)
            .background(emphasized ? accent.background : Palette.card, in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
struct CloseControl: View {
    let action: () -> Void
    var body: some View { Button(action: action) { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: 36, height: 36).background(Palette.card, in: Circle()) }.buttonStyle(.plain).accessibilityLabel("Закрыть") }
}
struct ToggleRow: View {
    @Environment(\.studyAccent) private var accent
    let title: String
    var subtitle: String = ""
    @Binding var value: Bool
    var body: some View {
        Button { value.toggle() } label: {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 15, weight: .medium))
                    if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Capsule().fill(value ? accent.color : Color.secondary.opacity(0.2)).frame(width: 44, height: 26)
                    .overlay(alignment: value ? .trailing : .leading) { Circle().fill(.white).frame(width: 20, height: 20).padding(3) }
            }.contentShape(Rectangle()).padding(.vertical, 10)
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(value ? "Включено" : "Выключено")
    }
}
extension View {
    func studyCard() -> some View { padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 20)) }
    @ViewBuilder func studySearchInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
    @ViewBuilder func studySheetSize() -> some View {
        #if os(macOS)
        frame(minWidth: 540, minHeight: 620)
        #else
        self
        #endif
    }
}
