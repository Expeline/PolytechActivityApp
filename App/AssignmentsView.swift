import SwiftUI

struct EditorContext: Identifiable {
    let id = UUID()
    var draft: AssignmentDraft
    let isNew: Bool
}

extension ScheduleStore {
    /// A new draft for a subject, due at its next lesson when there is one.
    func newDraft(subject: String? = nil, lesson: Lesson? = nil) -> AssignmentDraft {
        let subject = subject ?? lesson?.subject ?? subjects.first ?? ""
        let target = lesson.flatMap { $0.start > .now ? $0 : nil } ?? nextLesson(of: subject)
        return AssignmentDraft(subject: subject, lessonKind: target?.kind ?? lesson?.kind, title: "",
                               dueAt: target?.start ?? StudyClock.addDays(7, to: StudyClock.calendar.startOfDay(for: .now)),
                               dueLessonStart: target?.start)
    }
}

struct AssignmentsView: View {
    @Environment(\.studyAccent) private var accent
    let store: ScheduleStore
    @State private var subjectFilter: String?
    @State private var showDone = false
    @State private var editing: EditorContext?
    private var study: StudyStore { store.study }

    private var items: [AssignmentDTO] {
        study.assignments(groupID: store.group.id).filter { subjectFilter == nil || $0.subject == subjectFilter }
    }
    private var buckets: [(String, [AssignmentDTO])] {
        let now = Date.now
        let open = items.filter { !$0.completedByMe }
        let weekEnd = now.addingTimeInterval(7 * 86_400)
        return [
            ("Просрочено", open.filter { $0.dueAt < now }),
            ("Сегодня", open.filter { $0.dueAt >= now && StudyClock.calendar.isDate($0.dueAt, inSameDayAs: now) }),
            ("Ближайшие 7 дней", open.filter { $0.dueAt >= now && !StudyClock.calendar.isDate($0.dueAt, inSameDayAs: now) && $0.dueAt < weekEnd }),
            ("Позже", open.filter { $0.dueAt >= weekEnd }),
        ].filter { !$0.1.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center) {
                ServerBadge(study: study)
                Spacer()
                Button { editing = EditorContext(draft: store.newDraft(subject: subjectFilter), isNew: true) } label: {
                    Label("Новое", systemImage: "plus")
                }.buttonStyle(SoftButton(emphasized: true)).disabled(store.subjects.isEmpty)
            }
            if let error = study.lastError { StatusNote(text: error) }
            subjectChips
            if buckets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(items.isEmpty ? "Заданий пока нет" : "Всё сделано").font(.system(size: 25, weight: .medium))
                    Text(store.subjects.isEmpty ? "Загрузите расписание, чтобы привязывать задания к предметам."
                         : "Опубликуйте задание — его увидят все, кто выбрал группу \(store.group.name).")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(28).background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
            }
            ForEach(buckets, id: \.0) { title, list in
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Eyebrow(text: title); Spacer(); Text("\(list.count)").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary) }
                    ForEach(list) { AssignmentRow(item: $0, store: store, edit: { editing = $0 }) }
                }
            }
            let done = items.filter(\.completedByMe)
            if !done.isEmpty {
                Button { withAnimation { showDone.toggle() } } label: {
                    HStack { Eyebrow(text: "Выполнено · \(done.count)"); Spacer(); Image(systemName: showDone ? "chevron.up" : "chevron.down").font(.caption) }
                }.buttonStyle(.plain)
                if showDone { ForEach(done.reversed()) { AssignmentRow(item: $0, store: store, edit: { editing = $0 }) } }
            }
        }
        .sheet(item: $editing) { AssignmentEditor(store: store, context: $0).studyAppearance(store) }
    }

    private var subjectChips: some View {
        let used = Array(Set(study.assignments(groupID: store.group.id).map(\.subject))).sorted()
        return Group {
            if used.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        chip("Все", selected: subjectFilter == nil) { subjectFilter = nil }
                        ForEach(used, id: \.self) { subject in chip(subject, selected: subjectFilter == subject) { subjectFilter = subject } }
                    }
                }
            }
        }
    }
    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).padding(.horizontal, 13).padding(.vertical, 9)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? accent.background : Palette.card, in: Capsule())
        }.buttonStyle(.plain)
    }
}

struct ServerBadge: View {
    let study: StudyStore
    var body: some View {
        let pending = study.state.outbox.count
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(pending > 0 ? "\(short) · ждут отправки: \(pending)" : short).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
    private var short: String {
        switch study.status {
        case .online: "Группа онлайн"
        case .connecting: "Подключаемся…"
        case .off: "Только на этом устройстве"
        case .offline: "Нет связи с сервером"
        }
    }
    private var color: Color {
        switch study.status {
        case .online: .green
        case .connecting: .yellow
        case .off: .secondary
        case .offline: .orange
        }
    }
}

struct AssignmentRow: View {
    @Environment(\.studyAccent) private var accent
    let item: AssignmentDTO
    let store: ScheduleStore
    let edit: (EditorContext) -> Void
    @State private var confirmDelete = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button { store.study.setDone(item, !item.completedByMe) } label: {
                Image(systemName: item.completedByMe ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(item.completedByMe ? accent.color : (item.isOverdue ? .red : .secondary))
                    .contentTransition(.symbolEffect(.replace))
            }.buttonStyle(.plain).sensoryFeedback(.success, trigger: item.completedByMe) { _, done in done }.accessibilityLabel(item.completedByMe ? "Отметить невыполненным" : "Отметить выполненным")
            VStack(alignment: .leading, spacing: 7) {
                Text(item.subject.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(accent.color).lineLimit(1)
                Text(item.title).font(.system(size: 15, weight: .medium)).strikethrough(item.completedByMe).multilineTextAlignment(.leading)
                if !item.details.isEmpty { Text(item.details).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3) }
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 10))
                    Text(dueText).font(.system(size: 11, weight: item.isOverdue ? .semibold : .regular))
                }.foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
                HStack(spacing: 6) {
                    Text(item.isMine ? "Вы" : item.authorName)
                    if item.completedCount > 0 { Text("· выполнили \(item.completedCount)") }
                    if store.study.pending(item.id) { Image(systemName: "clock.arrow.circlepath").accessibilityLabel("Ждёт отправки") }
                }.font(.system(size: 10)).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                if item.isMine {
                    Button("Изменить", systemImage: "pencil") { edit(EditorContext(draft: item.draft, isNew: false)) }
                    Button("Удалить", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } else if !item.reportedByMe {
                    Button("Пожаловаться", systemImage: "exclamationmark.bubble") { store.study.report(item) }
                } else {
                    Text("Жалоба отправлена")
                }
            } label: { Image(systemName: "ellipsis").frame(width: 30, height: 30) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Действия")
        }
        .padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
        .opacity(item.completedByMe ? 0.65 : 1)
        .confirmationDialog("Удалить задание для всей группы?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { store.study.delete(item) }
        }
    }

    private var dueText: String {
        let date = StudyClock.string(item.dueAt, format: "EE, d MMM, HH:mm")
        return item.dueLessonStart != nil ? "\(date) · на паре" : date
    }
}

struct AssignmentEditor: View {
    @Environment(\.studyAccent) private var accent
    @Environment(\.dismiss) private var dismiss
    let store: ScheduleStore
    @State private var draft: AssignmentDraft
    @State private var atLesson: Bool
    @State private var problem: String?
    private let isNew: Bool

    init(store: ScheduleStore, context: EditorContext) {
        self.store = store
        isNew = context.isNew
        _draft = State(initialValue: context.draft)
        _atLesson = State(initialValue: context.draft.dueLessonStart != nil)
    }

    private var lessons: [Lesson] {
        Array(store.upcomingLessons.filter { $0.subject == draft.subject && $0.start > .now }.prefix(8))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Text(isNew ? "Новое задание" : "Задание").font(.system(size: 27, weight: .medium)).tracking(-0.8); Spacer(); CloseControl { dismiss() } }
                field("Предмет") {
                    Picker("Предмет", selection: $draft.subject) {
                        ForEach(subjectChoices, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().pickerStyle(.menu).tint(accent.color)
                        .onChange(of: draft.subject) { _, subject in
                            let next = store.nextLesson(of: subject)
                            draft.lessonKind = next?.kind
                            if atLesson, let next { draft.dueLessonStart = next.start; draft.dueAt = next.start }
                            else if atLesson { atLesson = false; draft.dueLessonStart = nil }
                        }
                }
                field("Что сделать") {
                    TextField("Например, лабораторная № 3", text: $draft.title).textFieldStyle(.plain).font(.system(size: 16))
                }
                field("Подробности") {
                    TextField("Номера задач, требования, ссылка", text: $draft.details, axis: .vertical)
                        .lineLimit(3...8).textFieldStyle(.plain).font(.system(size: 14))
                }
                field("Срок сдачи") {
                    ToggleRow(title: "Сдать на паре", subtitle: lessons.isEmpty ? "Ближайших пар по предмету нет в загруженном расписании." : "", value: $atLesson)
                        .disabled(lessons.isEmpty)
                        .onChange(of: atLesson) { _, value in
                            if value, let first = lessons.first { draft.dueLessonStart = first.start; draft.dueAt = first.start; draft.lessonKind = first.kind }
                            else { draft.dueLessonStart = nil }
                        }
                    if atLesson {
                        ForEach(lessons) { lesson in
                            Button { draft.dueLessonStart = lesson.start; draft.dueAt = lesson.start; draft.lessonKind = lesson.kind } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(StudyClock.string(lesson.start, format: "EEEE, d MMMM")) · \(lesson.timeRange)").font(.system(size: 13))
                                        Text(lesson.kind).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: draft.dueLessonStart == lesson.start ? "checkmark.circle.fill" : "circle").foregroundStyle(accent.color)
                                }.padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                        }
                    } else {
                        DatePicker("Дата и время", selection: $draft.dueAt, in: Date.now.addingTimeInterval(-86_400)...)
                            .datePickerStyle(.compact).font(.system(size: 14))
                    }
                }
                if let problem { StatusNote(text: problem) }
                Button(isNew ? "Опубликовать для группы" : "Сохранить") { save() }
                    .buttonStyle(SoftButton(emphasized: true)).frame(maxWidth: .infinity, alignment: .leading)
                Text("Задание увидят все, кто выбрал группу \(store.group.name) в Политехе. Отметка «выполнено» — личная, группа видит только их количество.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(26)
        }.background(Palette.canvas).studySheetSize()
    }

    private var subjectChoices: [String] {
        let list = store.subjects
        return list.contains(draft.subject) || draft.subject.isEmpty ? list : [draft.subject] + list
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: title)
            VStack(alignment: .leading, spacing: 10, content: content).padding(14)
                .frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func save() {
        if !atLesson { draft.dueLessonStart = nil }
        if let issue = draft.problem { problem = issue; return }
        if isNew { store.study.create(draft, groupID: store.group.id) }
        else { store.study.update(draft, groupID: store.group.id) }
        dismiss()
    }
}
