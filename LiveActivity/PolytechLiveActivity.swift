import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PolytechWidgets: WidgetBundle {
    var body: some Widget {
        PolytechLiveActivity()
        ScheduleWidget()
    }
}

struct PolytechLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LessonAttributes.self) { context in
            LiveActivityView(context: context)
                .widgetURL(URL(string: "polytech://schedule"))
        } dynamicIsland: { context in
            let accent = (context.state.accent ?? .green).highlight
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(context.state.subject).font(.system(size: 16, weight: .medium)).lineLimit(3)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(context.state.location).lineLimit(1)
                                Text("\(StudyClock.string(context.state.start, format: "HH:mm"))–\(StudyClock.string(context.state.end, format: "HH:mm"))")
                            }.font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            timer(context).frame(width: 102, alignment: .trailing).font(.system(size: 22, weight: .light)).foregroundStyle(accent)
                        }
                    }.padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 8)
                }
            } compactLeading: {
                Image(systemName: "square.grid.2x2.fill").font(.system(size: 13)).foregroundStyle(accent).frame(width: 22)
            } compactTrailing: {
                timer(context).font(.system(size: 12, weight: .medium)).foregroundStyle(accent).frame(width: 70, height: 24, alignment: .center)
            } minimal: {
                Image(systemName: "square.grid.2x2.fill").foregroundStyle(accent)
            }
            .widgetURL(URL(string: "polytech://schedule"))
            .keylineTint(accent)
        }
    }
    private func timer(_ context: ActivityViewContext<LessonAttributes>) -> some View {
        let start = context.state.updatedAt
        let end = max(context.state.end, start)
        return Text(timerInterval: start...end, countsDown: true)
            .monospacedDigit().multilineTextAlignment(.trailing).minimumScaleFactor(0.75)
    }
}

private struct LiveActivityView: View {
    let context: ActivityViewContext<LessonAttributes>
    @Environment(\.colorScheme) private var systemScheme
    private var scheme: ColorScheme {
        context.state.theme == "light" ? .light : context.state.theme == "dark" ? .dark : systemScheme
    }
    private var accent: StudyAccent { context.state.accent ?? .green }
    private var ink: Color { scheme == .dark ? .white : .black }
    private var highlight: Color { scheme == .dark ? accent.highlight : accent.background }
    private var canvas: Color { scheme == .dark ? accent.background : .white }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("ЗАНЯТИЕ · \(context.state.kind.uppercased())").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(highlight)
                    Spacer()
                    Text(context.attributes.groupName).font(.system(size: 10)).foregroundStyle(ink.opacity(0.5))
                }
                Text(context.state.subject).font(.system(size: 19, weight: .medium)).lineLimit(2)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.location).lineLimit(1)
                        Text("\(StudyClock.string(context.state.start, format: "HH:mm")) — \(StudyClock.string(context.state.end, format: "HH:mm"))")
                    }.font(.system(size: 12)).foregroundStyle(ink.opacity(0.65))
                    Spacer(minLength: 10)
                    timer.frame(width: 118, alignment: .trailing).font(.system(size: 28, weight: .light)).foregroundStyle(highlight)
                }
                ProgressView(timerInterval: context.state.start...context.state.end, countsDown: false)
                    .labelsHidden().tint(highlight)
        }.padding(20).foregroundStyle(ink)
            .environment(\.colorScheme, scheme)
            .activityBackgroundTint(canvas)
            .activitySystemActionForegroundColor(highlight)
    }

    private var timer: some View {
        let start = context.state.updatedAt
        let end = max(context.state.end, start)
        return Text(timerInterval: start...end, countsDown: true)
            .monospacedDigit().multilineTextAlignment(.trailing).minimumScaleFactor(0.75)
    }
}
