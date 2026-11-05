import SwiftUI

extension ScheduleChangeKind {
    var color: Color {
        switch self {
        case .cancelled: .red
        case .moved, .added: .blue
        case .roomChanged, .teacherChanged: .orange
        }
    }
    var symbol: String {
        switch self {
        case .added: "plus.circle"
        case .cancelled: "xmark.circle"
        case .moved: "arrow.right.circle"
        case .roomChanged: "door.left.hand.open"
        case .teacherChanged: "person.crop.circle"
        }
    }
}

struct ChangeTag: View {
    let kind: ScheduleChangeKind
    var body: some View {
        Text(kind.tag).font(.system(size: 9, weight: .semibold)).tracking(0.8)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .foregroundStyle(kind.color).background(kind.color.opacity(0.13), in: Capsule())
    }
}

/// "Было → стало" for one change.
struct ChangeRow: View {
    let change: ScheduleChange
    var showSubject = true

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: change.kind.symbol).font(.system(size: 19)).foregroundStyle(change.kind.color).frame(width: 24)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    ChangeTag(kind: change.kind)
                    Text(change.lessonKind.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                }
                if showSubject { Text(change.subject).font(.system(size: 15, weight: .medium)).fixedSize(horizontal: false, vertical: true) }
                if let old = change.old {
                    slot(old, label: "Было", strike: change.kind != .added).foregroundStyle(.secondary)
                }
                if let new = change.new, change.kind != .cancelled {
                    slot(new, label: change.old == nil ? "Когда" : "Стало", strike: false)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func slot(_ slot: LessonSlot, label: String, strike: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(.tertiary)
            Text("\(StudyClock.string(slot.start, format: "EE, d MMM")) · \(slot.timeRange)").strikethrough(strike && change.kind != .roomChanged && change.kind != .teacherChanged)
            Text(change.kind == .teacherChanged ? slot.teachers.joined(separator: ", ") : slot.location)
                .strikethrough(strike && (change.kind == .roomChanged || change.kind == .teacherChanged))
                .foregroundStyle(.secondary)
        }.font(.system(size: 12))
    }
}

struct ChangesView: View {
    @Environment(\.studyAccent) private var accent
    let store: ScheduleStore
    @State private var filter: ScheduleChangeKind?
    @State private var upcomingOnly = true

    private var items: [ScheduleChange] {
        store.study.changes(groupID: store.group.id).filter {
            (filter == nil || $0.kind == filter) && (!upcomingOnly || $0.relevantStart > .now)
        }
    }
    private var days: [(Date, [ScheduleChange])] {
        Dictionary(grouping: items) { StudyClock.calendar.startOfDay(for: $0.detectedAt) }
            .sorted { $0.key > $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { ServerBadge(study: store.study); Spacer() }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    chip("Все", selected: filter == nil) { filter = nil }
                    ForEach(ScheduleChangeKind.allCases, id: \.self) { kind in chip(kind.title, selected: filter == kind) { filter = kind } }
                }
            }
            ToggleRow(title: "Только предстоящие пары", value: $upcomingOnly)
            if days.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Изменений нет").font(.system(size: 25, weight: .medium))
                    Text("Политех сравнивает расписание при каждом обновлении, а сервер группы — каждые 15 минут. Переносы, отмены и новые пары появятся здесь.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(28).background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
            }
            ForEach(days, id: \.0) { day, list in
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Обнаружено " + dayTitle(day))
                    ForEach(list) { ChangeRow(change: $0) }
                }
            }
        }
        .onAppear { store.study.markChangesSeen(groupID: store.group.id) }
    }

    private func dayTitle(_ day: Date) -> String {
        if StudyClock.calendar.isDateInToday(day) { return "сегодня" }
        if StudyClock.calendar.isDateInYesterday(day) { return "вчера" }
        return StudyClock.string(day, format: "d MMMM")
    }
    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).padding(.horizontal, 13).padding(.vertical, 9)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? accent.background : Palette.card, in: Capsule())
        }.buttonStyle(.plain)
    }
}
