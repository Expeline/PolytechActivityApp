import SwiftUI

struct SettingsView: View {
    @Environment(\.studyAccent) private var accent
    @Bindable var store: ScheduleStore
    @Environment(\.dismiss) private var dismiss
    @State private var showGroups = false
    @State private var nameDraft = ""
    @State private var addressDraft = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack { Text("Настройки").font(.system(size: 29, weight: .medium)).tracking(-1); Spacer(); CloseControl { dismiss() } }
                section("Учёба") {
                    Button { showGroups = true } label: {
                        HStack { VStack(alignment: .leading, spacing: 5) { Text(store.group.name).font(.headline); Text(store.group.faculty.name).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.right") }
                    }.buttonStyle(.plain)
                }
                section("Задания и изменения") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ваше имя в группе").font(.system(size: 14))
                        TextField("Как вас увидят одногруппники", text: $nameDraft)
                            .textFieldStyle(.plain).padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 10))
                            .onSubmit(saveName)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Сервер группы").font(.system(size: 14))
                        TextField("http://MacBook-Pro-Arthur.local:8080", text: $addressDraft)
                            .studySearchInput().autocorrectionDisabled()
                            .textFieldStyle(.plain).padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 10))
                            .onSubmit(saveAddress)
                    }
                    HStack {
                        ServerBadge(study: store.study)
                        Spacer()
                        Button("Подключить") { saveName(); saveAddress() }.buttonStyle(SoftButton())
                    }
                    if case .offline(let reason) = store.study.status { Text(reason).font(.caption).foregroundStyle(.secondary) }
                    ToggleRow(title: "Уведомлять об изменениях", subtitle: "Переносы, отмены и новые пары на ближайшую неделю.", value: Bindable(store.study).notifyChanges)
                    ToggleRow(title: "Напоминать о сроках", subtitle: "За день и за 3 часа до срока невыполненного задания.", value: Bindable(store.study).notifyDeadlines)
                    Text("Изменения расписания приложение находит само при каждом обновлении. Сервер добавляет общие задания группы и проверяет расписание каждые 15 минут, даже когда приложение закрыто. Задания открыты всем, кто выбрал эту группу.").font(.caption).foregroundStyle(.secondary)
                }
                section("Оформление") {
                    HStack(spacing: 7) {
                        ForEach(AppTheme.allCases) { theme in
                            Button { store.theme = theme } label: {
                                Text(theme.title).font(.system(size: 12, weight: .medium)).padding(.vertical, 14).frame(maxWidth: .infinity)
                                    .foregroundStyle(store.theme == theme ? Color.white : Color.primary)
                                    .background(store.theme == theme ? accent.background : Palette.canvas, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text("Акцентный цвет"); Spacer(); Text(store.accent.title).foregroundStyle(.secondary) }.font(.system(size: 14))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 12) {
                            ForEach(StudyAccent.allCases) { choice in
                                Button { store.accent = choice } label: {
                                    Circle().fill(choice.color)
                                        .overlay { if store.accent == choice { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white) } }
                                        .frame(width: 36, height: 36).padding(4)
                                        .overlay { Circle().stroke(store.accent == choice ? choice.color : .clear, lineWidth: 2) }
                                        .frame(maxWidth: .infinity)
                                }.buttonStyle(.plain).accessibilityLabel(choice.title)
                                    .accessibilityValue(store.accent == choice ? "Выбран" : "")
                            }
                        }
                    }.padding(.top, 12)
                    ToggleRow(title: "Значок в цвет акцента", subtitle: "Цвет значка приложения меняется вместе с акцентом.", value: $store.useAccentIcon)
                    if let message = store.iconMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                    HStack { Text("Масштаб текста"); Spacer(); Text("\(Int(store.preferences.scale * 100)) %").foregroundStyle(.secondary) }.font(.system(size: 14)).padding(.top, 12)
                    HStack {
                        Button { store.preferences.scale = max(0.85, store.preferences.scale - 0.05) } label: { Image(systemName: "minus") }.buttonStyle(SoftButton())
                        Slider(value: $store.preferences.scale, in: 0.85...1.35, step: 0.05).tint(accent.color)
                        Button { store.preferences.scale = min(1.35, store.preferences.scale + 0.05) } label: { Image(systemName: "plus") }.buttonStyle(SoftButton())
                    }
                    ToggleRow(title: "Компактные карточки", value: $store.preferences.compact)
                    ToggleRow(title: "Показывать преподавателей", value: $store.preferences.showTeachers)
                    ToggleRow(title: "Показывать прошедшие пары", value: $store.preferences.showPast)
                }
                section("Посещение и активности") {
                    ToggleRow(title: "Активность текущей и следующей пары", value: $store.liveEnabled)
                    ToggleRow(title: "Пропускать военную подготовку", value: $store.preferences.skipMilitary)
                    ToggleRow(title: "Пропускать все лекции", subtitle: "Практики остаются. Исключения — в карточке занятия.", value: $store.preferences.skipLectures)
                    Text("Пропуски не скрывают пары из расписания. Откройте занятие, чтобы разрешить или пропустить его один раз либо всегда для этого предмета и типа.").font(.caption).foregroundStyle(.secondary)
                    if let message = store.activityMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
                section("Без интернета") {
                    HStack { Text("Недель вперёд"); Spacer(); Text("\(store.preferences.weeksAhead)").foregroundStyle(accent.color) }.font(.system(size: 14))
                    HStack(spacing: 8) {
                        ForEach([4, 6, 8, 12], id: \.self) { count in
                            Button { store.preferences.weeksAhead = count; Task { await store.refresh() } } label: {
                                Text("\(count)").frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .background(count == store.preferences.weeksAhead ? accent.color.opacity(0.2) : Palette.canvas, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }
                    Text("Сначала показываем сохранённое расписание. При открытии тихо проверяем изменения. Загруженные недели остаются на устройстве.").font(.caption).foregroundStyle(.secondary)
                    Button(store.isRefreshing ? "Обновляем…" : "Обновить сейчас") { Task { await store.refresh() } }.buttonStyle(SoftButton()).disabled(store.isRefreshing)
                }
                section("Виджеты") {
                    Text("Добавьте «Политех» из галереи виджетов iPhone, iPad или Mac. Виджеты показывают текущую пару или свободное время, без перехода на следующий день. На экране блокировки iPhone доступен компактный вариант.").font(.system(size: 13)).foregroundStyle(.secondary)
                    Text("Группа, пропуски, завершение дня, тема и акцент берутся из приложения. Виджет показывает только текущую пару; после завершения дня — отдых.").font(.caption).foregroundStyle(.secondary)
                }
                if store.widgetSyncFailed { StatusNote(text: "Не удалось передать данные виджету. Откройте приложение повторно после разблокировки устройства.") }
                section("Как обновляется таймер") {
                    #if os(iOS)
                    Text("Таймер до конца пары работает системно. Для переключения между разными предметами при закрытом приложении нужен фоновый запуск iOS; он не гарантирован по секундам. Нажмите на активность для обновления. Завершение дня немедленно убирает активность до следующего дня.").font(.caption).foregroundStyle(.secondary)
                    #else
                    Text("Строка меню работает, пока запущено приложение, в том числе при закрытом окне. Полный выход — ⌘Q. Время занятий всегда московское.").font(.caption).foregroundStyle(.secondary)
                    #endif
                }
                Link("Расписание СПбПУ ↗", destination: store.group.sourceURL).font(.caption).foregroundStyle(accent.color)
            }.padding(26).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.background(Palette.canvas).studySheetSize()
            .sheet(isPresented: $showGroups) { GroupPicker(store: store).studyAppearance(store) }
            .onAppear { nameDraft = store.study.displayName; addressDraft = store.study.serverAddress }
            .onDisappear { saveName(); saveAddress() }
    }
    private func saveName() {
        let name = String(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard name != store.study.displayName else { return }
        store.study.displayName = name
        Task { await store.study.renameOnServer() }
    }
    private func saveAddress() {
        let address = addressDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if address != store.study.serverAddress { store.study.serverAddress = address }
        Task { await store.study.sync() }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) { Eyebrow(text: title); VStack(alignment: .leading, spacing: 12, content: content).padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 18)) }
    }
}

struct GroupPicker: View {
    @Environment(\.studyAccent) private var accent
    let store: ScheduleStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [StudyGroup] = []
    @State private var error: String?
    @State private var searching = false
    @State private var didSearch = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Моя группа").font(.title2.weight(.medium)); Spacer(); CloseControl { dismiss() } }.padding(22)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Номер группы или ссылка ruz.spbstu.ru", text: $query)
                        .studySearchInput().autocorrectionDisabled()
                        .submitLabel(.search).onSubmit { search() }
                        .textFieldStyle(.plain).padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Номер группы или ссылка на расписание")
                    Button("Найти группу", systemImage: "magnifyingglass", action: search).buttonStyle(SoftButton(emphasized: true))
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searching)
                    Text("Например, 5130904/40102 или полная ссылка на группу.").font(.caption).foregroundStyle(.secondary)
                }
                if searching { ProgressView("Ищем группу…") }
                if let error { Text(error).foregroundStyle(.secondary) }
                if didSearch && results.isEmpty && !searching && error == nil { Text("Групп не найдено. Проверьте номер.").foregroundStyle(.secondary) }
                ForEach(results) { group in
                    Button {
                        Task { await store.choose(group); dismiss() }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(group.name).font(.headline)
                            Text(group.faculty.name).font(.caption).foregroundStyle(.secondary)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Сейчас выбрана")
                    Label(store.group.name, systemImage: "checkmark.circle.fill").foregroundStyle(accent.color)
                }
                }.padding(24)
            }
            .onDisappear { searchTask?.cancel() }
        }
        .tint(accent.color).background(Palette.canvas)
        .studySheetSize()
    }

    private func search() {
        searchTask?.cancel()
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searching = true
        didSearch = true
        error = nil
        results = []
        searchTask = Task { @MainActor in
            defer { searching = false }
            do {
                if input.contains("://") {
                    guard let ids = StudyGroup.ids(from: input) else {
                        error = "Нужна ссылка вида https://ruz.spbstu.ru/faculty/125/groups/45602"
                        return
                    }
                    let response = try await ScheduleAPI().week(groupID: ids.group, date: .now)
                    guard response.group.id == ids.group, response.group.faculty.id == ids.faculty else {
                        error = "Группа или институт в ссылке не совпадает с ответом сервиса."
                        return
                    }
                    guard !Task.isCancelled else { return }
                    results = [response.group]
                } else {
                    let groups = try await ScheduleAPI().search(input)
                    guard !Task.isCancelled else { return }
                    results = groups
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
}
