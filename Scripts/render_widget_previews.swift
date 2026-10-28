import AppKit
import SwiftUI
import WidgetKit

@main struct RenderWidgetPreviews {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let response = try JSONDecoder().decode(ScheduleResponse.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let snapshot = WidgetSnapshot(group: response.group, lessons: response.lessons, preferences: StudyPreferences(), updatedAt: .now)
        let entry = ScheduleWidgetEntry(date: .now, snapshot: snapshot, error: nil)
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        for (name, family, width, height) in [("small", WidgetFamily.systemSmall, 170.0, 170.0), ("medium", .systemMedium, 360.0, 170.0), ("large", .systemLarge, 360.0, 380.0)] {
            let view = ScheduleWidgetView(entry: entry, previewFamily: family)
                .padding(16).frame(width: width, height: height)
                .background(Color(red: 0.035, green: 0.12, blue: 0.095), in: RoundedRectangle(cornerRadius: 24))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let nsImage = renderer.nsImage, let tiff = nsImage.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { fatalError("Widget preview failed") }
            try png.write(to: output.appendingPathComponent("widget-\(name)-preview.png"))
        }
    }
}
