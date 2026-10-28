import SwiftUI

struct ScheduleView: View {
    @Environment(\.studyAccent) private var accent
    @Bindable var store: ScheduleStore
    @State private var selectedLesson: Lesson?
    @State private var weekDrag: CGFloat = 0
    private var scale: CGFloat { store.preferences.scale }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    NextLessonCard(lesson: store.activityLesson(at: context.date), now: context.date,
                                   available: store.nextWeeksAvailable, finished: store.dayFinished) { selectedLesson = $0 }
                }
                dayAction
                weekPicker
                daySection
                footer
            }
            .padding(.horizontal, 24).padding(.vertical, 24)
            .frame(maxWidth: 860).frame(maxWidth: .infinity)
        }
        .background(Palette.canvas)
        #if os(macOS)
        .background(MacWeekSwipe { changeWeek($0) })
        #endif
        .refreshable { await store.refresh() }
        .sheet(item: $selectedLesson) { LessonDetail(lesson: $0, store: store).studyAppearance(store) }
        .sheet(isPresented: $store.showSettings) { SettingsView(store: store).studyAppearance(store) }
    }
    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Eyebrow(text: "\(store.group.faculty.abbr ?? "СПбПУ") / \(store.group.name)")
                Text("Расписание").font(.system(size: 31 * scale, weight: .semibold)).tracking(-1.2)
            }
            Spacer()
            #if os(iOS)
            Button { store.showSettings = true } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 19)).frame(width: 44, height: 44) }
                .buttonStyle(.plain).accessibilityLabel("Настройки")
            #endif
        }
    }
    private var dayAction: some View {
        Button {
            Task { if store.dayFinished { await store.resumeDay() } else { await store.finishDay() } }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: store.dayFinished ? "arrow.uturn.backward" : "checkmark.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(accent.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.dayFinished ? "Вернуться к занятиям" : "Завершить учебный день")
                        .font(.system(size: 14, weight: .semibold))
                    Text(store.dayFinished ? "Снова показывать сегодняшние пары" : "Убрать активность до следующего дня")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 17))
            .overlay { RoundedRectangle(cornerRadius: 17).stroke(accent.color.opacity(0.22), lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain).padding(.bottom, 10)
    }

    private var weekPicker: some View {
        VStack(spacing: 18) {
            HStack {
                Text(StudyClock.string(store.weekStart, format: "LLLL yyyy").capitalized)
                    .font(.system(size: 17, weight: .medium))
                Spacer()
                Button("Сегодня") { withAnimation { store.selectedDate = StudyClock.calendar.startOfDay(for: .now) } }
                    .font(.system(size: 12, weight: .medium)).buttonStyle(.plain).foregroundStyle(accent.color)
                Button { changeWeek(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }.buttonStyle(.plain).accessibilityLabel("Предыдущая неделя")
                Button { changeWeek(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }.buttonStyle(.plain).accessibilityLabel("Следующая неделя")
            }
            HStack(spacing: 6) {
                ForEach(0..<7) { i in
                    let date = StudyClock.addDays(i, to: store.weekStart)
                    let selected = StudyClock.calendar.isDate(date, inSameDayAs: store.selectedDate)
                    Button { withAnimation(.easeOut(duration: 0.18)) { store.selectedDate = date } } label: {
                        VStack(spacing: 10) {
                            Text(StudyClock.string(date, format: "EE").uppercased()).font(.system(size: 10, weight: .medium)).opacity(0.6)
                            Text(StudyClock.string(date, format: "d")).font(.system(size: 20 * scale, weight: .medium))
                            Circle().fill(StudyClock.calendar.isDate(date, inSameDayAs: .now) ? (selected ? accent.highlight : accent.color) : .clear).frame(width: 4, height: 4)
                        }.frame(maxWidth: .infinity).padding(.vertical, 13)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(selected ? accent.background : .clear, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).accessibilityLabel(StudyClock.string(date, format: "EEEE, d MMMM"))
                }
            }
            .offset(x: weekDrag * 0.2).clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 25).onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) { weekDrag = value.translation.width }
            }.onEnded { value in
                if abs(value.translation.width) > 45 && abs(value.translation.width) > abs(value.translation.height) { changeWeek(value.translation.width < 0 ? 1 : -1) }
                withAnimation(.spring(duration: 0.25)) { weekDrag = 0 }
            })
            Rectangle().fill(Color.secondary.opacity(0.12)).frame(height: 1)
        }
    }
    private func changeWeek(_ offset: Int) { withAnimation(.easeInOut(duration: 0.2)) { store.shiftWeek(offset) } }
    private var daySection: some View {
        VStack(alignment: .leading, spacing: store.preferences.compact ? 10 : 16) {
            HStack {
                Text(StudyClock.string(store.selectedDate, format: "EEEE, d MMMM").capitalized).font(.system(size: 16 * scale, weight: .medium))
                Spacer()
                Text("\(store.dayLessons.count)").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }.padding(.bottom, 4)
            if store.isLoading { ProgressView().frame(maxWidth: .infinity).padding(40) }
            else if store.displayedWeek == nil {
                StatusNote(text: store.errorMessage ?? "Расписание ещё не загружено")
                Button("Загрузить расписание") { Task { await store.refresh() } }.buttonStyle(SoftButton())
            } else if visibleLessons.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Свободное время").font(.system(size: 25, weight: .medium))
                    Text("Здесь больше нет занятий на сегодня.").font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(28).background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
            } else {
                ForEach(visibleLessons) { lesson in
                    Button { selectedLesson = lesson } label: {
                        LessonRow(lesson: lesson, excluded: !store.preferences.includes(lesson, groupID: store.group.id),
                                  scale: scale, compact: store.preferences.compact, showTeachers: store.preferences.showTeachers)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private var visibleLessons: [Lesson] { store.dayLessons.filter { store.preferences.showPast || $0.end > .now } }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.secondary) }
            if let updated = store.displayedWeek?.fetchedAt {
                Text("МСК · Обновлено \(StudyClock.string(updated, format: "d MMM, HH:mm")) · \(store.loadedWeekCount) нед. офлайн")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }
}

struct NextLessonCard: View {
    @Environment(\.studyAccent) private var accent
    let lesson: Lesson?
    let now: Date
    let available: Bool
    var finished = false
    let select: (Lesson) -> Void
    private var ongoing: Bool { !finished && lesson.map { $0.start <= now && now < $0.end } == true }
    var body: some View {
        Button { if let lesson { select(lesson) } } label: {
            VStack(alignment: .leading, spacing: 19) {
                HStack {
                    Text(finished ? "ДЕНЬ ЗАВЕРШЁН" : (ongoing ? "СЕЙЧАС НА ПАРЕ" : "СЛЕДУЮЩАЯ ПАРА"))
                        .font(.system(size: 10, weight: .semibold)).tracking(1.8)
                    Spacer()
                    Image(systemName: ongoing ? "circle.lefthalf.filled" : "arrow.up.right").font(.system(size: 16))
                }.foregroundStyle(accent.highlight)
                if let lesson {
                    Text(lesson.subject).font(.system(size: 24, weight: .medium)).tracking(-0.6).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(StudyClock.string(lesson.start, format: "EE, d MMM")) · \(lesson.timeRange)")
                            Text(lesson.location).foregroundStyle(.white.opacity(0.55))
                        }.font(.system(size: 12))
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 4) {
                            if ongoing { Text(lesson.end, style: .timer).monospacedDigit().font(.system(size: 27, weight: .light)).fixedSize() }
                            else { Text(remaining(lesson.start)).font(.system(size: 24, weight: .light)).monospacedDigit() }
                            Text(ongoing ? "до конца" : "до начала").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    if ongoing {
                        ProgressView(value: max(0, min(1, now.timeIntervalSince(lesson.start) / lesson.end.timeIntervalSince(lesson.start)))).tint(accent.highlight)
                    }
                } else {
                    Text(finished ? "На сегодня всё" : (available ? "Пока без занятий" : "Подключаем расписание"))
                        .font(.system(size: 27, weight: .medium))
                    Text("Следующая пара появится здесь.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
            }.padding(24).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.background, in: RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(.plain)
    }
    private func remaining(_ date: Date) -> String {
        let m = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        return m >= 1440 ? "\(m / 1440) д" : (m >= 60 ? "\(m / 60) ч \(m % 60) м" : "\(m) мин")
    }
}

struct LessonRow: View {
    @Environment(\.studyAccent) private var accent
    let lesson: Lesson
    let excluded: Bool
    var scale: CGFloat = 1
    var compact = false
    var showTeachers = true
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(StudyClock.string(lesson.start, format: "HH:mm")).font(.system(size: 16 * scale, weight: .medium)).monospacedDigit()
                Text(StudyClock.string(lesson.end, format: "HH:mm")).font(.system(size: 11)).foregroundStyle(.tertiary)
            }.frame(width: 50 * scale, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(excluded ? Color.secondary.opacity(0.2) : accent.color.opacity(0.6)).frame(width: 2)
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                HStack {
                    Text(lesson.kind.uppercased()).tracking(1).foregroundStyle(accent.color)
                    if excluded { Text("ПРОПУСК").foregroundStyle(.secondary) }
                }.font(.system(size: 9, weight: .semibold))
                Text(lesson.subject).font(.system(size: 16 * scale, weight: .medium)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Text(lesson.location).font(.system(size: 12)).foregroundStyle(.secondary)
                if showTeachers && !compact && !lesson.teachers.isEmpty { Text(lesson.teachers.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(.tertiary).multilineTextAlignment(.leading) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(compact ? 15 : 20).fixedSize(horizontal: false, vertical: true)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 19))
            .opacity(lesson.end < .now ? 0.75 : 1)
    }
}

struct LessonDetail: View {
    @Environment(\.studyAccent) private var accent
    let lesson: Lesson
    let store: ScheduleStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { Eyebrow(text: lesson.kind); Spacer(); CloseControl { dismiss() } }
                Text(lesson.subject).font(.system(size: 28, weight: .medium)).tracking(-0.8)
                Text("\(StudyClock.string(lesson.start, format: "EEEE, d MMMM"))\n\(lesson.timeRange) · МСК").lineSpacing(8).foregroundStyle(.secondary)
                Text(lesson.location).font(.headline)
                Text(lesson.teachers.joined(separator: "\n")).font(.subheadline).foregroundStyle(.secondary)
                if !lesson.additionalInfo.isEmpty { Text(lesson.additionalInfo).font(.caption).foregroundStyle(.secondary) }
                ruleSection("Это занятие", wholeSubject: false)
                ruleSection("Все такие занятия по предмету", wholeSubject: true)
                Text("Разрешение для одного занятия важнее правила предмета. Правило предмета важнее общего пропуска лекций и военной подготовки.").font(.caption).foregroundStyle(.secondary)
                if let url = safeURL(lesson.lmsURL) { Link("Материалы курса ↗", destination: url).buttonStyle(SoftButton()) }
                if let url = safeURL(lesson.webinarURL) { Link("Открыть вебинар ↗", destination: url).buttonStyle(SoftButton()) }
            }.padding(28)
        }.background(Palette.canvas).studySheetSize()
    }
    private func ruleSection(_ title: String, wholeSubject: Bool) -> some View {
        let selected = wholeSubject ? store.preferences.subjectRules[lesson.subjectRuleKey(groupID: store.group.id)] : store.preferences.lessonRules[lesson.ruleKey(groupID: store.group.id)]
        return VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: title)
            ForEach(AttendanceRule.allCases) { rule in
                Button { store.setRule(rule, lesson: lesson, wholeSubject: wholeSubject) } label: {
                    HStack { Text(rule.title); Spacer(); Image(systemName: (selected ?? .automatic) == rule ? "checkmark.circle.fill" : "circle").foregroundStyle(accent.color) }
                        .font(.system(size: 14)).padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
        }
    }
    private func safeURL(_ text: String?) -> URL? { guard let text, let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }; return url }
}
