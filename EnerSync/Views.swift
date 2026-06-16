// Views.swift
// EnerSync — onboarding greeting, schedule, add/edit task, settings, stats.

import SwiftUI
import Combine

// Dismiss the keyboard from anywhere.
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

// MARK: - Add-task draft (lifted above the TabView so it survives page swipes
// and can be saved from the center "+" button)

final class TaskDraft: ObservableObject {
    @Published var name = ""
    @Published var detail = ""
    @Published var energy: EnergyLevel = .medium
    @Published var autoPlace = true
    @Published var dayPart: DayPart = .morning
    @Published var useCustomRange = false
    @Published var startHour = 9
    @Published var endHour = 11
    @Published var minutes = 30
    @Published var hasCompleteBy = false
    @Published var useExactTime = false
    @Published var completeByTime = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date())!
    @Published var completeByPart: DayPart = .morning
    var didInit = false

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    @discardableResult
    func save(into manager: TaskManager) -> Bool {
        guard canSave else { return false }
        let chosenPart: DayPart? = autoPlace ? nil : dayPart
        var cb: CompleteBy? = nil
        if hasCompleteBy {
            cb = CompleteBy(exactTime: useExactTime ? completeByTime : nil,
                            dayPart: useExactTime ? (chosenPart ?? manager.currentDayPart) : completeByPart)
        }
        manager.addTask(name: name, detail: detail, energyRequired: energy,
                        dayPart: chosenPart,
                        customStart: (!autoPlace && useCustomRange) ? startHour : nil,
                        customEnd: (!autoPlace && useCustomRange) ? endHour : nil,
                        estimatedTime: minutes, completeBy: cb)
        reset(currentDayPart: manager.currentDayPart)
        return true
    }
    func reset(currentDayPart: DayPart) {
        name = ""; detail = ""; energy = .medium; autoPlace = true
        dayPart = currentDayPart; useCustomRange = false; minutes = 30
        hasCompleteBy = false; useExactTime = false; completeByPart = currentDayPart
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var manager = TaskManager.shared
    @StateObject private var draft = TaskDraft()
    @State private var page = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ZStack(alignment: .bottom) {
                TabView(selection: $page) {
                    ScheduleView(page: $page).environmentObject(manager).tag(0)
                    AddTaskView(draft: draft, page: $page, onDone: { withAnimation { page = 0 } }).environmentObject(manager).tag(1)
                    SettingsView(page: $page).environmentObject(manager).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(.keyboard)

                BottomBar(manager: manager, draft: draft, page: $page)

                if let banner = manager.banner {
                    Text(banner)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Theme.baseDark)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        .padding(.horizontal, 20)
                        .frame(maxHeight: .infinity, alignment: .top).padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            if manager.needsDailyCheckIn {
                GreetingView().environmentObject(manager).transition(.opacity)
            }

            // Evening "gentle reminder" — a compact centered card, not a full sheet.
            if let task = manager.rescheduleCandidate, !manager.hasLaterSlotNow {
                GentleReminderCard(
                    task: task,
                    onDone: {
                        manager.markDone(taskIDString: task.id.uuidString)   // completed → leaves your pending list
                        withAnimation { manager.rescheduleCandidate = nil }
                    },
                    onDismiss: { withAnimation { manager.rescheduleCandidate = nil } }  // keep the task as-is
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: manager.banner)
        .animation(.easeInOut(duration: 0.3), value: manager.needsDailyCheckIn)
        .animation(.easeInOut(duration: 0.25), value: manager.rescheduleCandidate)
        .onAppear { manager.requestAuth() }
        .onChange(of: page) { _ in dismissKeyboard() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                manager.rolloverIfNeeded()
                manager.checkForMissedTasks()
                manager.refreshNotifications()
            }
        }
        // Reschedule prompt (morning/afternoon) stays a sheet — it lists slot options.
        .sheet(item: Binding(
            get: { manager.hasLaterSlotNow ? manager.rescheduleCandidate : nil },
            set: { if $0 == nil { manager.rescheduleCandidate = nil } }
        )) { task in
            RescheduleSheet(task: task).environmentObject(manager)
        }
    }
}

// MARK: - Greeting onboarding (opaque background)

struct GreetingView: View {
    @EnvironmentObject var manager: TaskManager
    @State private var selection: EnergyLevel? = nil

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Theme.dawnDiagonal.opacity(0.18).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                EnerSyncLogo(progress: manager.progress, size: 64).padding(.bottom, 20)
                VStack(spacing: 8) {
                    Text(manager.daytime.rawValue)
                        .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(Theme.text)
                    Text(manager.greetingSubtitle)
                        .font(.system(size: 15, design: .rounded)).foregroundColor(Theme.textSec)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    ForEach(EnergyLevel.allCases) { level in
                        Button { withAnimation(.easeOut(duration: 0.18)) { selection = level } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: level.icon).font(.system(size: 18)).foregroundColor(level.accent).frame(width: 24)
                                Text(level.label)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(selection == level ? level.ink : Theme.text)
                                Spacer()
                                EnergyBars(level: level)
                            }
                            .padding(.vertical, 16).padding(.horizontal, 18)
                            .background(selection == level ? level.tint : Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                                .stroke(selection == level ? level.accent : Theme.border, lineWidth: selection == level ? 2 : 1))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.top, 28).padding(.horizontal, 24)

                Spacer()
                Button { if let s = selection { manager.setDailyEnergy(s) } } label: {
                    Text("Start my day")
                        .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(selection == nil ? Theme.base.opacity(0.4) : Theme.base)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                }.buttonStyle(.plain).disabled(selection == nil)
                .padding(.horizontal, 24).padding(.bottom, 36)
            }
        }
    }
}

// MARK: - Bottom bar (center "+" doubles as Save on the Add page)

struct BottomBar: View {
    let manager: TaskManager
    @ObservedObject var draft: TaskDraft
    @Binding var page: Int

    private var addActive: Bool { page != 1 || draft.canSave }

    var body: some View {
        HStack {
            tab("Schedule", 0)
            Spacer()
            Button {
                if page == 1 {
                    if draft.canSave { draft.save(into: manager); manager.flash("Task added to your schedule."); withAnimation { page = 0 } }
                } else {
                    withAnimation { page = 1 }
                }
            } label: {
                Image(systemName: page == 1 ? "checkmark" : "plus")
                    .font(.system(size: 24, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 58, height: 58)
                    .background(addActive ? (page == 1 ? Theme.accent : Theme.base) : Theme.base.opacity(0.4))
                    .clipShape(Circle())
                    .shadow(color: Theme.base.opacity(0.4), radius: 10, y: 4)
            }
            .buttonStyle(.plain).disabled(!addActive)
            .accessibilityLabel(page == 1 ? "Save task" : "Add task")
            Spacer()
            tab("Settings", 2)
        }
        .padding(.horizontal, 36).padding(.top, 10).padding(.bottom, 22)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Theme.border), alignment: .top)
    }
    private func tab(_ title: String, _ index: Int) -> some View {
        Button { withAnimation { page = index } } label: {
            Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(page == index ? Theme.base : Theme.textTer).frame(width: 80)
        }.buttonStyle(.plain)
    }
}

// MARK: - Schedule

struct ScheduleView: View {
    @EnvironmentObject var manager: TaskManager
    @Binding var page: Int
    @State private var editingTask: EnergyTask? = nil

    var body: some View {
        Group {
            if manager.manualOverride { manualList } else { autoSchedule }
        }
        .sheet(item: $editingTask) { task in EditTaskView(task: task).environmentObject(manager) }
    }

    @ViewBuilder private func headerBlock() -> some View {
        HStack(spacing: 12) {
            EnerSyncLogo(progress: manager.progress, size: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text("EnerSync").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(Theme.text)
                Text("Today").font(.system(size: 14, design: .rounded)).foregroundColor(Theme.textSec)
            }
            Spacer()
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("Current energy").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(Theme.textSec)
            HStack(spacing: 10) {
                ForEach(EnergyLevel.allCases) { level in
                    Button { manager.setEnergyManually(level) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: level.icon).font(.system(size: 20)).foregroundColor(level.accent).frame(height: 24)
                            Text(level.label).font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(manager.currentEnergy == level ? level.ink : Theme.textSec)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(manager.currentEnergy == level ? level.tint : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                            .stroke(manager.currentEnergy == level ? level.accent : Theme.border, lineWidth: manager.currentEnergy == level ? 2 : 1))
                    }.buttonStyle(.plain)
                }
            }
        }

        ProgressCard(progress: manager.progress, done: manager.completedCount, total: manager.totalCount)

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Manual override").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundColor(Theme.text)
                Text(manager.manualOverride ? "Long-press and drag tasks to reorder freely" : "Keep your own order; pause auto-suggestions")
                    .font(.system(size: 12, design: .rounded)).foregroundColor(Theme.textTer)
            }
            Spacer()
            Toggle("", isOn: $manager.manualOverride).labelsHidden().tint(Theme.base)
        }
        .padding(14).background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private var autoSchedule: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 0).id("top")
                    headerBlock()
                    if manager.tasks.isEmpty {
                        EmptyState(page: $page)
                    } else {
                        ForEach(manager.orderedDayParts) { part in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Text(part.rawValue).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundColor(Theme.text)
                                    Text(manager.timeline.label(part)).font(.system(size: 12, design: .rounded)).foregroundColor(Theme.textTer)
                                    if part == manager.currentDayPart {
                                        Text("Now").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(.white)
                                            .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.base).clipShape(Capsule())
                                    } else if let proj = manager.projectedLevel(for: part) {
                                        HStack(spacing: 4) {
                                            EnergyBars(level: proj)
                                            Text("~\(proj.label)").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(proj.ink)
                                        }
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(proj.tint).clipShape(Capsule())
                                    }
                                }
                                ForEach(manager.tasks(in: part)) { task in
                                    TaskCard(task: task,
                                             onToggle: { manager.toggleComplete(task) },
                                             onEdit: { editingTask = task })
                                }
                                if part == manager.currentDayPart { suggestionsBlock() }
                            }
                        }
                    }
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, 20).padding(.top, 16)
            }
            .onChange(of: page) { newValue in
                if newValue == 0 { withAnimation { proxy.scrollTo("top", anchor: .top) } }
            }
        }
    }

    @ViewBuilder private func suggestionsBlock() -> some View {
        let suggestions = manager.suggestedFromLater()
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Get ahead — fits your energy now")
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(Theme.textSec)
                ForEach(suggestions) { t in
                    HStack(spacing: 10) {
                        EnergyBars(level: t.energyRequired)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(Theme.text)
                            Text("from \(t.window.dayPart.rawValue)").font(.system(size: 11, design: .rounded)).foregroundColor(Theme.textTer)
                        }
                        Spacer()
                        Button { manager.bringToNow(t) } label: {
                            Text("Do now").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.white)
                                .padding(.horizontal, 12).padding(.vertical, 7).background(Theme.base).clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                    .padding(12).background(Theme.dawnStart.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                }
            }
        }
    }

    private var manualList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 20) { headerBlock() }
                    .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 8, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.background)
            }
            Section {
                if manager.tasks.isEmpty {
                    EmptyState(page: $page)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowSeparator(.hidden).listRowBackground(Theme.background)
                } else {
                    ForEach(manager.tasks) { task in
                        TaskCard(task: task,
                                 onToggle: { manager.toggleComplete(task) },
                                 onEdit: { editingTask = task })
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                            .listRowSeparator(.hidden).listRowBackground(Theme.background)
                    }
                    .onMove { manager.moveTasks(from: $0, to: $1) }
                }
            } header: {
                Text("Long-press and drag to reorder").font(.system(size: 12, design: .rounded))
                    .foregroundColor(Theme.textTer).textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .tint(Theme.base)
    }
}

struct EmptyState: View {
    @Binding var page: Int
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist").font(.system(size: 36)).foregroundColor(Theme.textTer)
            Text("No tasks yet").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundColor(Theme.text)
            Text("Add your first task and EnerSync will organize it around your energy.")
                .font(.system(size: 14, design: .rounded)).foregroundColor(Theme.textSec).multilineTextAlignment(.center)
            Button { withAnimation { page = 1 } } label: {
                Text("Add a task").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(.white)
                    .padding(.horizontal, 22).padding(.vertical, 12).background(Theme.base).clipShape(Capsule())
            }.buttonStyle(.plain).padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50).padding(.horizontal, 20)
    }
}

// MARK: - Task card

struct TaskCard: View {
    @EnvironmentObject var manager: TaskManager
    let task: EnergyTask
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).stroke(task.isCompleted ? task.energyRequired.accent : Theme.border, lineWidth: 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(task.isCompleted ? task.energyRequired.accent : .clear))
                        .frame(width: 24, height: 24)
                    if task.isCompleted { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(.white) }
                }
            }.buttonStyle(.plain).accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(task.isCompleted ? Theme.textTer : Theme.text)
                    .strikethrough(task.isCompleted)
                HStack(spacing: 8) {
                    EnergyChip(level: task.energyRequired)
                    Text("\(task.estimatedTime) min").font(.system(size: 12, design: .rounded)).foregroundColor(Theme.textSec)
                    if let cb = task.completeBy {
                        Text("· \(cb.label(using: manager.timeline))").font(.system(size: 12, design: .rounded)).foregroundColor(Theme.textSec)
                    }
                }
                if manager.needsMoreEnergy(task) {
                    if let booster = manager.unlockSuggestion(for: task) {
                        Button { manager.toggleComplete(booster) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "bolt.heart").font(.system(size: 11))
                                Text("Do \u{201C}\(booster.name)\u{201D} first to get there")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(Theme.accent)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Theme.accent.opacity(0.12)).clipShape(Capsule())
                        }.buttonStyle(.plain)
                    } else {
                        Text("needs higher energy than now")
                            .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundColor(Theme.textTer)
                    }
                }
            }
            Spacer(minLength: 6)
            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 15)).foregroundColor(Theme.base)
            }.buttonStyle(.plain).accessibilityLabel("Edit task")
        }
        .padding(14).frame(maxWidth: .infinity)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .opacity(task.isCompleted ? 0.6 : 1)
    }
}

// MARK: - Reusable themed text field with a readable placeholder

struct ThemedField: View {
    let placeholder: String
    @Binding var text: String
    var multiline = false

    var body: some View {
        ZStack(alignment: multiline ? .topLeading : .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(Theme.textSec)
                    .padding(.top, multiline ? 2 : 0)
                    .allowsHitTesting(false)
            }
            if multiline {
                TextField("", text: $text, axis: .vertical).lineLimit(3...6)
                    .font(.system(size: 16, design: .rounded)).foregroundColor(Theme.text)
            } else {
                TextField("", text: $text)
                    .font(.system(size: 16, design: .rounded)).foregroundColor(Theme.text)
            }
        }
        .padding(14).background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - Add Task

struct AddTaskView: View {
    @EnvironmentObject var manager: TaskManager
    @ObservedObject var draft: TaskDraft
    @Binding var page: Int
    var onDone: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Color.clear.frame(height: 0).id("addtop")
                    Text("Add task").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(Theme.text)

                    field("Name") { ThemedField(placeholder: "What would you like to do?", text: $draft.name) }
                    field("Description") { ThemedField(placeholder: "Notes, context, sub-steps…", text: $draft.detail, multiline: true) }

                    field("Select energy level classification") { EnergyClassifier(selection: $draft.energy) }

                    field("Time of day") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Let EnerSync pick the best time", isOn: $draft.autoPlace.animation())
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.text).tint(Theme.base)
                            if draft.autoPlace {
                                Text("EnerSync places this into your lightest-loaded upcoming section, based on each task's effort.")
                                    .font(.system(size: 12, design: .rounded)).foregroundColor(Theme.textTer)
                            } else {
                                ForEach(DayPart.allCases) { p in
                                    let isPast = p.order < manager.currentDayPart.order
                                    dayPartButton(p, selected: draft.dayPart == p, disabled: isPast) {
                                        if !isPast {
                                            draft.dayPart = p
                                            // Keep complete-by coherent: it can't be earlier than the task itself.
                                            if draft.completeByPart.order < p.order { draft.completeByPart = p }
                                        }
                                    }
                                }
                                Toggle("Use a specific time range", isOn: $draft.useCustomRange.animation())
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundColor(Theme.text).tint(Theme.base).padding(.top, 4)
                                if draft.useCustomRange {
                                    let partStart = manager.timeline.start(draft.dayPart)
                                    let partEnd = manager.timeline.end(draft.dayPart)
                                    let lower = draft.dayPart == manager.currentDayPart ? max(currentHour, partStart) : partStart
                                    HStack(spacing: 12) {
                                        hourMenu("From", $draft.startHour, minHour: lower, maxHour: max(lower, partEnd - 1))
                                        hourMenu("To", $draft.endHour, minHour: min(draft.startHour + 1, partEnd), maxHour: partEnd)
                                    }
                                }
                            }
                        }
                    }

                    field("Estimated time") { StepControl(minutes: $draft.minutes) }

                    field("Complete by (optional)") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Set a complete-by target", isOn: $draft.hasCompleteBy.animation())
                                .font(.system(size: 15, design: .rounded)).foregroundColor(Theme.text).tint(Theme.base)
                            if draft.hasCompleteBy {
                                Text("EnerSync won't nag beforehand. If the time passes and it's still open, it'll ask whether to reschedule.")
                                    .font(.system(size: 12, design: .rounded)).foregroundColor(Theme.textTer)
                                Toggle("Use an exact time", isOn: $draft.useExactTime.animation())
                                    .font(.system(size: 14, design: .rounded)).foregroundColor(Theme.text).tint(Theme.base)
                                if draft.useExactTime {
                                    DatePicker("Time", selection: $draft.completeByTime, in: Date()..., displayedComponents: [.hourAndMinute])
                                        .font(.system(size: 15, design: .rounded)).foregroundColor(Theme.text)
                                } else {
                                    HStack(spacing: 8) {
                                        ForEach(DayPart.allCases) { p in
                                            // Earliest allowed = later of (now) and (the task's chosen part,
                                            // when scheduling manually). You can't complete-by before you start.
                                            let earliest = draft.autoPlace ? manager.currentDayPart.order
                                                                           : max(manager.currentDayPart.order, draft.dayPart.order)
                                            let isPast = p.order < earliest
                                            Button { if !isPast { draft.completeByPart = p } } label: {
                                                Text(p.rawValue).font(.system(size: 13, weight: .semibold, design: .rounded))
                                                    .foregroundColor(draft.completeByPart == p ? .white : (isPast ? Theme.textTer : Theme.text))
                                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                                    .background(draft.completeByPart == p ? Theme.base : Theme.surfaceAlt)
                                                    .clipShape(Capsule()).opacity(isPast ? 0.5 : 1)
                                            }.buttonStyle(.plain).disabled(isPast)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(14).background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.border, lineWidth: 1))
                    }

                    Button {
                        if draft.save(into: manager) { manager.flash("Task added to your schedule."); onDone() }
                    } label: {
                        Text("Save task").font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(draft.canSave ? Theme.base : Theme.base.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    }.buttonStyle(.plain).disabled(!draft.canSave)
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, 20).padding(.top, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
            .onChange(of: manager.tasks.count) { _ in proxy.scrollTo("addtop", anchor: .top) }
            .onChange(of: page) { newValue in
                if newValue == 1 { withAnimation { proxy.scrollTo("addtop", anchor: .top) } }
            }
            .onAppear {
                if !draft.didInit {
                    draft.dayPart = manager.currentDayPart
                    draft.completeByPart = manager.currentDayPart
                    draft.didInit = true
                }
                clampTimes(); clampCompleteBy()
            }
            .onChange(of: draft.dayPart) { _ in clampTimes() }
            .onChange(of: draft.useCustomRange) { on in if on { clampTimes() } }
            .onChange(of: draft.hasCompleteBy) { on in if on { clampCompleteBy() } }
            .onChange(of: draft.useExactTime) { on in if on { clampCompleteBy() } }
        }
    }

    private func dayPartButton(_ p: DayPart, selected: Bool, disabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(p.rawValue).font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(disabled ? Theme.textTer : (selected ? .white : Theme.text))
                if disabled { Text("passed").font(.system(size: 11, design: .rounded)).foregroundColor(Theme.textTer) }
                Spacer()
                Text(manager.timeline.label(p)).font(.system(size: 12, design: .rounded))
                    .foregroundColor(selected ? .white.opacity(0.85) : Theme.textTer)
            }
            .padding(.vertical, 13).padding(.horizontal, 14)
            .background(selected ? Theme.base : (disabled ? Theme.surfaceAlt : Theme.surface))
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(selected ? .clear : Theme.border, lineWidth: 1))
            .opacity(disabled ? 0.5 : 1)
        }.buttonStyle(.plain).disabled(disabled)
    }
    private func field<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased()).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(Theme.textSec)
            content()
        }
    }
    private var currentHour: Int { Calendar.current.component(.hour, from: Date()) }

    /// Keep the custom time range within the chosen day part and never in the past.
    private func clampTimes() {
        let partStart = manager.timeline.start(draft.dayPart)
        let partEnd = manager.timeline.end(draft.dayPart)
        let lower = draft.dayPart == manager.currentDayPart ? max(currentHour, partStart) : partStart
        let lo = min(lower, max(partStart, partEnd - 1))
        if draft.startHour < lo { draft.startHour = lo }
        if draft.startHour > partEnd - 1 { draft.startHour = max(lo, partEnd - 1) }
        if draft.endHour <= draft.startHour { draft.endHour = min(partEnd, draft.startHour + 1) }
        if draft.endHour > partEnd { draft.endHour = partEnd }
    }

    /// The complete-by exact time can never be in the past.
    private func clampCompleteBy() {
        let now = Date()
        if draft.completeByTime <= now {
            draft.completeByTime = now.addingTimeInterval(15 * 60)
        }
    }

    private func hourMenu(_ label: String, _ binding: Binding<Int>, minHour: Int, maxHour: Int) -> some View {
        let lo = max(0, min(minHour, 24))
        let hi = max(lo, min(maxHour, 24))
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, design: .rounded)).foregroundColor(Theme.textTer)
            Menu {
                ForEach(Array(lo...hi), id: \.self) { h in Button(hourString(h)) { binding.wrappedValue = h } }
            } label: {
                HStack {
                    Text(hourString(binding.wrappedValue)).foregroundColor(Theme.text)
                    Spacer(); Image(systemName: "chevron.down").font(.system(size: 11)).foregroundColor(Theme.textTer)
                }
                .font(.system(size: 15, design: .rounded)).padding(12).frame(maxWidth: .infinity).background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.border, lineWidth: 1))
            }
        }
    }
    private func hourString(_ h: Int) -> String {
        let hh = h % 24
        if hh == 0 || hh == 24 { return "12 AM" }
        if hh == 12 { return "12 PM" }
        return hh < 12 ? "\(hh) AM" : "\(hh - 12) PM"
    }
}

// MARK: - Delete confirmation (compact bottom sheet, near the delete button)

struct DeleteConfirmSheet: View {
    let taskName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(Theme.border).frame(width: 40, height: 5).padding(.top, 10)

            VStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 26)).foregroundColor(Color(hex: "C0584B"))
                    .frame(width: 56, height: 56)
                    .background(Color(hex: "C0584B").opacity(0.12)).clipShape(Circle())
                    .padding(.bottom, 4)
                Text("Delete this task?")
                    .font(.system(size: 19, weight: .bold, design: .rounded)).foregroundColor(Theme.text)
                Text("\u{201C}\(taskName)\u{201D} will be removed permanently.")
                    .font(.system(size: 14, design: .rounded)).foregroundColor(Theme.textSec)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button(action: onConfirm) {
                    Text("Delete").font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Color(hex: "C0584B"))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                }.buttonStyle(.plain)
                Button(action: onCancel) {
                    Text("Cancel").font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Theme.surfaceAlt)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Edit Task

struct EditTaskView: View {
    @EnvironmentObject var manager: TaskManager
    @Environment(\.dismiss) private var dismiss
    @State var task: EnergyTask
    @State private var showDeleteConfirm = false

    // Editable "Complete by" mirror state (populated from the task on appear).
    @State private var hasCompleteBy = false
    @State private var useExactTime = false
    @State private var completeByTime = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date())!
    @State private var completeByPart: DayPart = .evening
    @State private var cbInit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    field("Name") { ThemedField(placeholder: "Task name", text: $task.name) }
                    field("Description") { ThemedField(placeholder: "Notes, context…", text: $task.detail, multiline: true) }
                    field("Energy required") { EnergyClassifier(selection: $task.energyRequired) }
                    field("Time of day") {
                        VStack(spacing: 8) {
                            ForEach(DayPart.allCases) { p in
                                let isPast = p.order < manager.currentDayPart.order
                                Button { if !isPast { task.window.dayPart = p; if completeByPart.order < p.order { completeByPart = p } } } label: {
                                    HStack {
                                        Text(p.rawValue).font(.system(size: 15, weight: .medium, design: .rounded))
                                            .foregroundColor(isPast ? Theme.textTer : (task.window.dayPart == p ? .white : Theme.text))
                                        if isPast { Text("passed").font(.system(size: 11, design: .rounded)).foregroundColor(Theme.textTer) }
                                        Spacer()
                                        Text(manager.timeline.label(p)).font(.system(size: 12, design: .rounded))
                                            .foregroundColor(task.window.dayPart == p ? .white.opacity(0.85) : Theme.textTer)
                                    }
                                    .padding(.vertical, 12).padding(.horizontal, 14)
                                    .background(task.window.dayPart == p ? Theme.base : (isPast ? Theme.surfaceAlt : Theme.surface))
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                                        .stroke(task.window.dayPart == p ? .clear : Theme.border, lineWidth: 1))
                                    .opacity(isPast ? 0.5 : 1)
                                }.buttonStyle(.plain).disabled(isPast)
                            }
                        }
                    }
                    field("Estimated time") { StepControl(minutes: $task.estimatedTime) }

                    field("Complete by (optional)") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Set a complete-by target", isOn: $hasCompleteBy.animation())
                                .font(.system(size: 15, design: .rounded)).foregroundColor(Theme.text).tint(Theme.base)
                            if hasCompleteBy {
                                Text("EnerSync won't nag beforehand. If the time passes and it's still open, it'll ask whether to reschedule.")
                                    .font(.system(size: 12, design: .rounded)).foregroundColor(Theme.textTer)
                                Toggle("Use an exact time", isOn: $useExactTime.animation())
                                    .font(.system(size: 14, design: .rounded)).foregroundColor(Theme.text).tint(Theme.base)
                                if useExactTime {
                                    DatePicker("Time", selection: $completeByTime, in: Date()..., displayedComponents: [.hourAndMinute])
                                        .font(.system(size: 15, design: .rounded)).foregroundColor(Theme.text)
                                } else {
                                    HStack(spacing: 8) {
                                        ForEach(DayPart.allCases) { p in
                                            // Can't complete-by before the task's own slot or before now.
                                            let earliest = max(manager.currentDayPart.order, task.window.dayPart.order)
                                            let isPast = p.order < earliest
                                            Button { if !isPast { completeByPart = p } } label: {
                                                Text(p.rawValue).font(.system(size: 13, weight: .semibold, design: .rounded))
                                                    .foregroundColor(completeByPart == p ? .white : (isPast ? Theme.textTer : Theme.text))
                                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                                    .background(completeByPart == p ? Theme.base : Theme.surfaceAlt)
                                                    .clipShape(Capsule()).opacity(isPast ? 0.5 : 1)
                                            }.buttonStyle(.plain).disabled(isPast)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(14).background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.border, lineWidth: 1))
                    }

                    Button {
                        // Fold the edited complete-by back into the task before saving.
                        if hasCompleteBy {
                            task.completeBy = CompleteBy(exactTime: useExactTime ? completeByTime : nil,
                                                         dayPart: useExactTime ? task.window.dayPart : completeByPart)
                        } else {
                            task.completeBy = nil
                        }
                        manager.updateTask(task); manager.flash("Task updated."); dismiss()
                    } label: {
                        Text("Save changes").font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 16).background(Theme.base)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    }.buttonStyle(.plain)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                            Text("Delete task").font(.system(size: 16, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "C0584B"))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color(hex: "C0584B").opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    }.buttonStyle(.plain)

                    Spacer(minLength: 20)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("Edit task").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Theme.base) } }
            .sheet(isPresented: $showDeleteConfirm) {
                DeleteConfirmSheet(taskName: task.name) {
                    manager.deleteTask(task); manager.flash("Task deleted."); showDeleteConfirm = false; dismiss()
                } onCancel: {
                    showDeleteConfirm = false
                }
            }
            .onAppear {
                guard !cbInit else { return }
                if let cb = task.completeBy {
                    hasCompleteBy = true
                    if let exact = cb.exactTime {
                        useExactTime = true
                        // If the stored time has already passed, nudge it forward so it stays valid.
                        completeByTime = exact < Date() ? (Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? exact) : exact
                    } else {
                        useExactTime = false
                        completeByPart = cb.dayPart
                    }
                } else {
                    completeByPart = task.window.dayPart.order >= manager.currentDayPart.order ? task.window.dayPart : manager.currentDayPart
                }
                // Never let the day-part target sit before the task's slot or the current part.
                let earliest = max(manager.currentDayPart.order, task.window.dayPart.order)
                if completeByPart.order < earliest, let fixed = DayPart.allCases.first(where: { $0.order == earliest }) {
                    completeByPart = fixed
                }
                cbInit = true
            }
        }
    }
    private func field<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased()).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(Theme.textSec)
            content()
        }
    }
}

// MARK: - Reschedule sheet (missed complete-by)

struct RescheduleSheet: View {
    @EnvironmentObject var manager: TaskManager
    @Environment(\.dismiss) private var dismiss
    let task: EnergyTask

    // Only day parts from now onward can be offered (single-day app, no tomorrow).
    private var laterParts: [DayPart] {
        DayPart.allCases.filter { $0.order >= manager.currentDayPart.order }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reschedule this task?").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(Theme.text)
                        Text("\"\(task.name)\" passed its complete-by time and is still open. When would you like to do it?")
                            .font(.system(size: 14, design: .rounded)).foregroundColor(Theme.textSec)
                    }
                    .padding(.top, 8)

                    ForEach(laterParts) { p in
                        Button { manager.reschedule(task, to: p); dismiss() } label: {
                            HStack {
                                Text(p.rawValue).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(Theme.text)
                                if p == manager.currentDayPart {
                                    Text("now").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(.white)
                                        .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.base).clipShape(Capsule())
                                }
                                Spacer()
                                Text(manager.timeline.label(p)).font(.system(size: 13, design: .rounded)).foregroundColor(Theme.textTer)
                                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(Theme.textTer)
                            }
                            .padding(16).background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.border, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }

                    Button { manager.markDone(taskIDString: task.id.uuidString); dismiss() } label: {
                        Text("It's already done").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(Theme.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Theme.surfaceAlt).clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    }.buttonStyle(.plain)

                    Button { manager.rescheduleCandidate = nil; dismiss() } label: {
                        Text("Keep it where it is")
                            .font(.system(size: 15, weight: .medium, design: .rounded)).foregroundColor(Theme.textSec)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }.buttonStyle(.plain)
                    Spacer(minLength: 10)
                }
                .padding(20)
            }
            .background(Theme.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("Missed task").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// MARK: - Gentle reminder (compact centered card for the end of the day)

struct GentleReminderCard: View {
    let task: EnergyTask
    let onDone: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dimmed backdrop; tapping outside keeps the task and dismisses.
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 16) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 28)).foregroundColor(Theme.base)
                    .frame(width: 58, height: 58)
                    .background(Theme.dawnStart.opacity(0.25)).clipShape(Circle())

                VStack(spacing: 8) {
                    Text("A gentle reminder")
                        .font(.system(size: 19, weight: .bold, design: .rounded)).foregroundColor(Theme.text)
                    Text("You didn't get to \u{201C}\(task.name)\u{201D} today — and that's okay. No pressure.")
                        .font(.system(size: 14, design: .rounded)).foregroundColor(Theme.textSec)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    Button(action: onDone) {
                        Text("It's already done")
                            .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    }.buttonStyle(.plain)
                    Button(action: onDismiss) {
                        Text("Got it")
                            .font(.system(size: 15, weight: .medium, design: .rounded)).foregroundColor(Theme.textSec)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                    }.buttonStyle(.plain)
                }
            }
            .padding(24)
            .frame(maxWidth: 300)
            .background(Theme.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).stroke(Theme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 26, y: 12)
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var manager: TaskManager
    @Binding var page: Int

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Color.clear.frame(height: 0).id("settop")
                        Text("Settings").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(Theme.text).padding(.top, 16)

                        group("Your stats") {
                            NavigationLink { TaskListView(title: "All tasks", filter: .all).environmentObject(manager) } label: { statRow("Total tasks", "\(manager.totalCount)") }
                            Divider().background(Theme.border)
                            NavigationLink { TaskListView(title: "Completed", filter: .completed).environmentObject(manager) } label: { statRow("Completed", "\(manager.completedCount)") }
                            Divider().background(Theme.border)
                            NavigationLink { RecentlyDeletedView().environmentObject(manager) } label: { statRow("Recently deleted", "\(manager.recentlyDeleted.count)") }
                        }

                        group("Timelines") {
                            Text("Adjust when each part of your day begins and ends.")
                                .font(.system(size: 12, design: .rounded)).foregroundColor(Theme.textTer)
                            ForEach(DayPart.allCases, id: \.self) { part in
                                TimelineEditorRow(part: part).environmentObject(manager)
                            }
                        }

                        group("Preferences") {
                            pref("Complete-by reminders", "If a task passes its complete-by time unfinished, EnerSync asks to reschedule", $manager.completeByRemindersEnabled)
                        }

                        group("Energy") {
                            pref("Automatic energy adjustment",
                                 "Let your energy change as you complete tasks and rearrange the schedule",
                                 $manager.autoEnergyEnabled)
                        }

                        Spacer(minLength: 110)
                    }
                    .padding(.horizontal, 20)
                }
                .onChange(of: page) { newValue in
                    if newValue == 2 { withAnimation { proxy.scrollTo("settop", anchor: .top) } }
                }
            }
            .background(Theme.background)
        }
    }

    private func statRow(_ t: String, _ v: String) -> some View {
        HStack {
            Text(t).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundColor(Theme.text)
            Spacer()
            Text(v).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(Theme.base)
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(Theme.textTer)
        }.contentShape(Rectangle()).padding(.vertical, 4)
    }
    private func pref(_ t: String, _ s: String, _ b: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundColor(Theme.text)
                Text(s).font(.system(size: 12, design: .rounded)).foregroundColor(Theme.textTer).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: b).labelsHidden().tint(Theme.base)
        }
    }
    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(Theme.textSec).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
    }
}

// MARK: - Timeline editor row

struct TimelineEditorRow: View {
    @EnvironmentObject var manager: TaskManager
    let part: DayPart
    var body: some View {
        HStack {
            Text(part.rawValue).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundColor(Theme.text)
            Spacer()
            hourMenu(isStart: true)
            Text("–").foregroundColor(Theme.textTer)
            hourMenu(isStart: false)
        }
    }
    private func hourMenu(isStart: Bool) -> some View {
        let current = isStart ? manager.timeline.start(part) : manager.timeline.end(part)
        return Menu {
            ForEach(0..<25, id: \.self) { h in
                Button(hourString(h)) {
                    if isStart { manager.timeline.startHour[part.rawValue] = h }
                    else { manager.timeline.endHour[part.rawValue] = h }
                }
            }
        } label: {
            Text(hourString(current)).font(.system(size: 14, weight: .medium, design: .rounded)).foregroundColor(Theme.base)
                .padding(.horizontal, 10).padding(.vertical, 6).background(Theme.surfaceAlt).clipShape(Capsule())
        }
    }
    private func hourString(_ h: Int) -> String {
        let hh = h % 24
        if hh == 0 || hh == 24 { return "12 AM" }
        if hh == 12 { return "12 PM" }
        return hh < 12 ? "\(hh) AM" : "\(hh - 12) PM"
    }
}

// MARK: - Searchable task list (tap to edit · undo completion)

struct TaskListView: View {
    enum Filter { case all, completed }
    @EnvironmentObject var manager: TaskManager
    let title: String
    let filter: Filter
    @State private var query = ""
    @State private var editing: EnergyTask? = nil

    private var source: [EnergyTask] {
        switch filter { case .all: return manager.tasks; case .completed: return manager.completedTasks }
    }
    private var filtered: [EnergyTask] {
        query.isEmpty ? source : source.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ThemedField(placeholder: "Search by name", text: $query)

                if filtered.isEmpty {
                    Text(filter == .completed ? "No completed tasks yet." : "No tasks match.")
                        .font(.system(size: 14, design: .rounded)).foregroundColor(Theme.textTer)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                }

                ForEach(filtered) { task in
                    HStack(spacing: 12) {
                        Button { editing = task } label: {
                            HStack(spacing: 12) {
                                EnergyBars(level: task.energyRequired)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.name).font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundColor(task.isCompleted ? Theme.textTer : Theme.text).strikethrough(task.isCompleted)
                                    Text("\(task.energyRequired.label) · \(task.window.dayPart.rawValue) · \(task.estimatedTime) min")
                                        .font(.system(size: 12, design: .rounded)).foregroundColor(Theme.textSec)
                                }
                                Spacer(minLength: 4)
                            }
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)

                        Button { manager.toggleComplete(task) } label: {
                            if task.isCompleted {
                                Text("Undo").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(Theme.base)
                                    .padding(.horizontal, 12).padding(.vertical, 7).background(Theme.surfaceAlt).clipShape(Capsule())
                            } else {
                                Text("Done").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 7).background(Theme.accent).clipShape(Capsule())
                            }
                        }.buttonStyle(.plain)
                    }
                    .padding(14).frame(maxWidth: .infinity).background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.border, lineWidth: 1))
                }
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20).padding(.top, 12)
        }
        .background(Theme.background)
        .scrollContentBackground(.hidden)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(item: $editing) { task in EditTaskView(task: task).environmentObject(manager) }
    }
}

// MARK: - Recently deleted (restore or remove permanently)

struct RecentlyDeletedView: View {
    @EnvironmentObject var manager: TaskManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Deleted tasks are kept here for 30 days. Restore one to put it back on your schedule.")
                    .font(.system(size: 12, design: .rounded)).foregroundColor(Theme.textTer)
                    .padding(.horizontal, 4)

                if manager.recentlyDeleted.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "trash").font(.system(size: 30)).foregroundColor(Theme.textTer)
                        Text("Nothing here").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(Theme.text)
                        Text("Tasks you delete will show up here.").font(.system(size: 13, design: .rounded)).foregroundColor(Theme.textSec)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 50)
                } else {
                    ForEach(manager.recentlyDeleted) { task in
                        HStack(spacing: 12) {
                            EnergyBars(level: task.energyRequired)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.name).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(Theme.text)
                                Text("\(task.energyRequired.label) · \(task.window.dayPart.rawValue) · \(task.estimatedTime) min")
                                    .font(.system(size: 12, design: .rounded)).foregroundColor(Theme.textSec)
                            }
                            Spacer(minLength: 4)
                            Button { manager.restoreTask(task) } label: {
                                Text("Restore").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 7).background(Theme.base).clipShape(Capsule())
                            }.buttonStyle(.plain)
                            Button { manager.deletePermanently(task) } label: {
                                Image(systemName: "trash").font(.system(size: 14)).foregroundColor(Color(hex: "C0584B"))
                                    .padding(8).background(Color(hex: "C0584B").opacity(0.10)).clipShape(Circle())
                            }.buttonStyle(.plain).accessibilityLabel("Delete permanently")
                        }
                        .padding(14).frame(maxWidth: .infinity).background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.border, lineWidth: 1))
                    }

                    Button { manager.emptyRecentlyDeleted() } label: {
                        Text("Empty recently deleted").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundColor(Color(hex: "C0584B"))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.buttonStyle(.plain).padding(.top, 4)
                }
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20).padding(.top, 12)
        }
        .background(Theme.background)
        .scrollContentBackground(.hidden)
        .navigationTitle("Recently deleted").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

#Preview { ContentView() }
