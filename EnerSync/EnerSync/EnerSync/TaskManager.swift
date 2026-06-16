// TaskManager.swift
// EnerSync — central state: energy engine (internal score), keyword-based energy
// prediction (tasks add or drain), time-aware scheduling with rollover & cross-section
// suggestions, persistence, and "Complete by" miss notifications with quick actions.

import SwiftUI
import Combine
import UserNotifications
import NaturalLanguage

final class TaskManager: ObservableObject {
    static let shared = TaskManager()

    // Persisted state (each change auto-saves once `ready`)
    @Published var tasks: [EnergyTask] = [] { didSet { save() } }
    @Published var currentEnergy: EnergyLevel = .high { didSet { save() } }
    @Published var energyScore: Int = 100 { didSet { save() } }     // internal only (no longer shown)
    @Published var timeline: TimelineConfig = .default { didSet { save() } }
    @Published var autoEnergyEnabled: Bool = true { didSet { save() } }
    @Published var manualOverride: Bool = false { didSet { save() } }
    @Published var completeByRemindersEnabled: Bool = true { didSet { save() } }
    @Published var lastCheckIn: Date? = nil { didSet { save() } }
    /// Soft-deleted tasks kept for restore (auto-purged after 30 days).
    @Published var recentlyDeleted: [EnergyTask] = [] { didSet { save() } }

    // Transient (not persisted)
    @Published var rescheduleCandidate: EnergyTask? = nil
    @Published var banner: String? = nil

    private var ready = false
    private static let key = "enersync.state.v1"

    init() { load() }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var tasks: [EnergyTask]
        var timeline: TimelineConfig
        var currentEnergy: EnergyLevel
        var energyScore: Int
        var autoEnergyEnabled: Bool
        var manualOverride: Bool
        var completeByRemindersEnabled: Bool
        var lastCheckIn: Date?
        var recentlyDeleted: [EnergyTask]?
    }

    private func save() {
        guard ready else { return }
        let snap = Snapshot(tasks: tasks, timeline: timeline, currentEnergy: currentEnergy,
                            energyScore: energyScore, autoEnergyEnabled: autoEnergyEnabled,
                            manualOverride: manualOverride,
                            completeByRemindersEnabled: completeByRemindersEnabled,
                            lastCheckIn: lastCheckIn, recentlyDeleted: recentlyDeleted)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func load() {
        defer { ready = true }
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        tasks = snap.tasks
        timeline = snap.timeline
        currentEnergy = snap.currentEnergy
        energyScore = snap.energyScore
        autoEnergyEnabled = snap.autoEnergyEnabled
        manualOverride = snap.manualOverride
        completeByRemindersEnabled = snap.completeByRemindersEnabled
        lastCheckIn = snap.lastCheckIn
        recentlyDeleted = snap.recentlyDeleted ?? []
    }

    // MARK: - Daytime greeting (once per day)

    enum Daytime: String { case morning = "Good morning", afternoon = "Good afternoon", evening = "Good evening", night = "Hello, night owl" }

    var daytime: Daytime {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return .morning
        case 12..<17: return .afternoon
        case 17..<22: return .evening
        default:      return .night
        }
    }
    var greetingSubtitle: String {
        switch daytime {
        case .morning:   return "A fresh start. How's your energy today?"
        case .afternoon: return "Halfway through. How are you feeling?"
        case .evening:   return "Winding down. What's your energy like now?"
        case .night:     return "Still going? Let's match your tasks to your energy."
        }
    }

    var needsDailyCheckIn: Bool {
        guard let d = lastCheckIn else { return true }
        return !Calendar.current.isDateInToday(d)
    }

    var currentDayPart: DayPart {
        timeline.part(forHour: Calendar.current.component(.hour, from: Date()))
    }

    // MARK: - Energy score → level (thresholds 50 and 10)

    func level(forScore s: Int) -> EnergyLevel { s > 50 ? .high : (s > 10 ? .medium : .low) }
    private func representativeScore(_ l: EnergyLevel) -> Int {
        switch l { case .high: return 100; case .medium: return 40; case .low: return 5 }
    }

    func setDailyEnergy(_ level: EnergyLevel) {
        currentEnergy = level
        energyScore = representativeScore(level)
        lastCheckIn = Date()
        rolloverIfNeeded()
        refreshNotifications()
    }

    // MARK: - Energy prediction (Apple on-device NaturalLanguage sentiment)
    //
    // We use Apple's built-in, on-device sentiment model (NLTagger .sentimentScore,
    // range −1…+1) as the primary signal for whether a task adds or drains energy.
    // Sentiment ≈ energy for most everyday tasks ("relax with friends" reads positive,
    // "urgent exam deadline" reads negative). Because tone isn't a perfect proxy for
    // energy, a tiny curated set of unambiguous energy words nudges the score so that
    // e.g. "nap" or "rest" (often scored neutral) still register as restorative and
    // "work"/"study" as draining. No dataset to maintain; runs fully offline.

    private static let restorativeHints: Set<String> = [
        "rest","nap","sleep","relax","break","unwind","recharge","leisure","movie","read",
        "walk","stroll","meditate","yoga","stretch","music","hobby","game","friends","family",
        "lunch","dinner","coffee","shower","bath","spa","massage","nature","chill","fun"
    ]
    private static let drainingHints: Set<String> = [
        "work","study","exam","deadline","meeting","email","report","essay","thesis","code",
        "assignment","homework","chore","clean","errand","tax","admin","interview","presentation",
        "grind","overtime","revise","invoice","budget","commute","paperwork"
    ]

    /// On-device sentiment in −1…+1 for arbitrary text (0 if model unavailable).
    private func sentimentScore(_ text: String) -> Double {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        return Double(tag?.rawValue ?? "0") ?? 0
    }

    /// Returns a signed energy delta: positive = restorative (adds), negative = draining (costs).
    func classifyDelta(name: String, detail: String, energy: EnergyLevel, minutes: Int) -> Int {
        let text = (name + ". " + detail)
        let sentiment = sentimentScore(text)              // −1 … +1

        // Small lexical correction so unambiguous energy words aren't lost to neutral tone.
        let tokens = text.lowercased().split { !$0.isLetter }.map(String.init)
        var bias = 0.0
        for t in tokens {
            if Self.restorativeHints.contains(t) { bias += 0.5 }
            if Self.drainingHints.contains(t) { bias -= 0.5 }
        }
        let signal = sentiment + bias                     // combined evidence

        // Magnitude from difficulty × duration (same model as before).
        let base = energy == .high ? 25 : (energy == .medium ? 12 : 5)
        let factor = max(0.5, min(2.0, Double(minutes) / 30.0))
        let mag = max(3, Int((Double(base) * factor).rounded()))

        if signal > 0.15 { return +mag }                  // clearly restorative → adds energy
        if signal < -0.15 { return -mag }                 // clearly draining → costs energy
        // Near-neutral: fall back to difficulty (a planned "task" usually costs something).
        return energy == .low ? -max(2, mag / 2) : -mag
    }

    // MARK: - Mutations

    func toggleComplete(_ task: EnergyTask) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let nowDone = !tasks[i].isCompleted
        tasks[i].isCompleted = nowDone
        applyScoreChange(nowDone ? tasks[i].scoreDelta : -tasks[i].scoreDelta)
        objectWillChange.send()
    }

    /// Notification quick-action: mark a task done from outside the app.
    func markDone(taskIDString id: String?) {
        guard let id, let uuid = UUID(uuidString: id),
              let i = tasks.firstIndex(where: { $0.id == uuid }), !tasks[i].isCompleted else { return }
        tasks[i].isCompleted = true
        applyScoreChange(tasks[i].scoreDelta)
        refreshNotifications()
    }

    /// Notification quick-action: open the in-app reschedule prompt.
    func beginReschedule(taskIDString id: String?) {
        guard let id, let uuid = UUID(uuidString: id),
              let t = tasks.first(where: { $0.id == uuid }) else { return }
        rescheduleCandidate = t
    }

    private func applyScoreChange(_ delta: Int) {
        let prev = level(forScore: energyScore)
        energyScore = min(100, max(0, energyScore + delta))
        guard autoEnergyEnabled, !manualOverride else { return }
        let now = level(forScore: energyScore)
        if now != prev {
            currentEnergy = now
            let verb = delta > 0 ? "back up to" : "now"
            flash("Energy is \(verb) \(now.label). Your schedule was rearranged to match.")
            objectWillChange.send()
        }
    }

    func setEnergyManually(_ level: EnergyLevel) {
        currentEnergy = level
        energyScore = representativeScore(level)
        objectWillChange.send()
    }

    func updateTask(_ updated: EnergyTask) {
        guard let i = tasks.firstIndex(where: { $0.id == updated.id }) else { return }
        var t = updated
        // Re-run the classifier so edits keep the energy prediction consistent.
        t.scoreDelta = classifyDelta(name: t.name, detail: t.detail, energy: t.energyRequired, minutes: t.estimatedTime)
        tasks[i] = t
        refreshNotifications()
    }

    func moveTasks(from source: IndexSet, to destination: Int) {
        tasks.move(fromOffsets: source, toOffset: destination)
    }

    func deleteTask(_ task: EnergyTask) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var removed = tasks.remove(at: idx)
        removed.deletedDate = Date()
        recentlyDeleted.insert(removed, at: 0)          // most-recent first
        if rescheduleCandidate?.id == task.id { rescheduleCandidate = nil }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["miss.\(task.id)"])
        purgeOldDeleted()
    }

    /// Put a soft-deleted task back into the active schedule.
    func restoreTask(_ task: EnergyTask) {
        guard let idx = recentlyDeleted.firstIndex(where: { $0.id == task.id }) else { return }
        var restored = recentlyDeleted.remove(at: idx)
        restored.deletedDate = nil
        // If its section is already behind us, pull it to the current part.
        if restored.window.dayPart.order < currentDayPart.order { restored.window.dayPart = currentDayPart }
        tasks.append(restored)
        scheduleMissNotification(for: restored)
        flash("\(restored.name) restored to your schedule.")
    }

    func deletePermanently(_ task: EnergyTask) {
        recentlyDeleted.removeAll { $0.id == task.id }
    }

    func emptyRecentlyDeleted() { recentlyDeleted.removeAll() }

    /// Drop anything in the trash older than 30 days.
    private func purgeOldDeleted() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date.distantPast
        recentlyDeleted.removeAll { ($0.deletedDate ?? Date()) < cutoff }
    }

    func sectionLoad(_ p: DayPart) -> Int {
        tasks.filter { $0.window.dayPart == p && !$0.isCompleted }.reduce(0) { $0 + $1.weight }
    }

    // MARK: - Energy forecast (projected level at the start of each day-part)

    /// Projects your energy SCORE at the start of each upcoming day-part by walking
    /// forward from the current score and applying each section's existing task deltas.
    func projectedScores() -> [DayPart: Int] {
        var result: [DayPart: Int] = [:]
        var running = energyScore
        let parts = DayPart.allCases.sorted { $0.order < $1.order }
        for p in parts where p.order >= currentDayPart.order {
            result[p] = running                                  // score entering this section
            let delta = tasks.filter { $0.window.dayPart == p && !$0.isCompleted }
                             .reduce(0) { $0 + $1.scoreDelta }
            running = min(100, max(0, running + delta))          // carry into the next section
        }
        return result
    }

    /// Projected energy LEVEL entering a section (for the UI forecast chip).
    func projectedLevel(for part: DayPart) -> EnergyLevel? {
        guard let s = projectedScores()[part] else { return nil }
        return level(forScore: s)
    }

    /// Balanced smart placement: hard/draining tasks prefer the section with the
    /// highest projected energy; restorative tasks prefer the lowest (place recovery
    /// where you'll dip). "Balanced" — we also avoid dumping into an already-heavy
    /// section by blending in its current load.
    private func autoPlacePart(restorative: Bool, demand: Int) -> DayPart {
        let eligible = DayPart.allCases.filter { $0.order >= currentDayPart.order }
        let pool = eligible.isEmpty ? [currentDayPart] : eligible
        let forecast = projectedScores()

        func fitCost(_ p: DayPart) -> Double {
            let proj = Double(forecast[p] ?? energyScore)
            let load = Double(sectionLoad(p))
            if restorative {
                // Want LOW projected energy (recovery where you dip); light penalty for load.
                return proj + load * 0.3
            } else {
                // Want HIGH projected energy for demand; penalize sections already heavy.
                // Lower cost = better; higher projection lowers cost, load raises it.
                return (100.0 - proj) + load * 0.5 + Double(demand) * 0.1
            }
        }
        return pool.min(by: { fitCost($0) < fitCost($1) }) ?? currentDayPart
    }

    func addTask(name: String, detail: String, energyRequired: EnergyLevel,
                 dayPart: DayPart?, customStart: Int?, customEnd: Int?,
                 estimatedTime: Int, completeBy: CompleteBy?) {
        let delta = classifyDelta(name: name, detail: detail, energy: energyRequired, minutes: estimatedTime)
        let resolved = dayPart ?? autoPlacePart(restorative: delta > 0, demand: abs(delta))
        let window = TaskWindow(dayPart: resolved, customStartHour: customStart, customEndHour: customEnd)
        let t = EnergyTask(name: name, detail: detail, energyRequired: energyRequired,
                           window: window, estimatedTime: estimatedTime, completeBy: completeBy, scoreDelta: delta)
        tasks.append(t)
        scheduleMissNotification(for: t)
    }

    /// For a task that needs more energy than you have now, find an available
    /// restorative task whose completion would lift you to (or past) the needed level.
    func unlockSuggestion(for task: EnergyTask) -> EnergyTask? {
        guard needsMoreEnergy(task) else { return nil }
        let needed = task.energyRequired
        // Candidate restorative tasks (incomplete, add energy), best lift first.
        let candidates = tasks.filter { $0.id != task.id && !$0.isCompleted && $0.isRestorative }
            .sorted { $0.scoreDelta > $1.scoreDelta }
        for c in candidates {
            let projected = min(100, energyScore + c.scoreDelta)
            if level(forScore: projected).rank >= needed.rank { return c }
        }
        // None fully unlocks it — still suggest the strongest restorative as a step up.
        return candidates.first
    }

    func flash(_ message: String) {
        banner = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            if self?.banner == message { self?.banner = nil }
        }
    }

    // MARK: - Rollover (unfinished tasks move forward through the day)

    func rolloverIfNeeded() {
        let nowPart = currentDayPart
        var changed = false
        for i in tasks.indices where !tasks[i].isCompleted {
            if tasks[i].window.dayPart.order < nowPart.order {
                tasks[i].window.dayPart = nowPart
                changed = true
            }
        }
        if changed { objectWillChange.send() }
    }

    func reschedule(_ task: EnergyTask, to part: DayPart) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[i].window.dayPart = part
        if tasks[i].completeBy != nil { tasks[i].completeBy?.exactTime = nil; tasks[i].completeBy?.dayPart = part }
        rescheduleCandidate = nil
        flash("\(task.name) moved to \(part.rawValue).")
        scheduleMissNotification(for: tasks[i])
    }

    // MARK: - Scheduling (time-of-day aware)

    var orderedDayParts: [DayPart] {
        let active = DayPart.allCases.filter { p in tasks.contains { $0.window.dayPart == p } }
        let nowOrder = currentDayPart.order
        return active.sorted { a, b in
            let da = (a.order - nowOrder + DayPart.allCases.count) % DayPart.allCases.count
            let db = (b.order - nowOrder + DayPart.allCases.count) % DayPart.allCases.count
            return da < db
        }
    }

    func tasks(in part: DayPart) -> [EnergyTask] {
        tasks.filter { $0.window.dayPart == part }.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            let am = matchRank(a.energyRequired), bm = matchRank(b.energyRequired)
            if am != bm { return am < bm }
            return a.estimatedTime < b.estimatedTime
        }
    }

    /// Lower rank = better fit for the user's current energy.
    /// Tasks needing MORE energy than you have are pushed to the bottom; among the
    /// rest the closest match to your current level comes first.
    private func matchRank(_ req: EnergyLevel) -> Int {
        let diff = req.rank - currentEnergy.rank
        if diff == 0 { return 0 }
        if diff < 0  { return 1 + abs(diff) }
        return 10 + diff
    }

    func needsMoreEnergy(_ task: EnergyTask) -> Bool {
        !task.isCompleted && task.energyRequired.rank > currentEnergy.rank
    }

    /// True when a day-part still lies ahead of the current one (so a task can be
    /// moved later today). False in the evening — the end of the day.
    var hasLaterSlotNow: Bool {
        DayPart.allCases.contains { $0.order > currentDayPart.order }
    }

    /// Cross-section help: when auto-organizing, surface a few later-today tasks
    /// that fit your current energy so you can get ahead. Spans ALL later sections.
    func suggestedFromLater(limit: Int = 2) -> [EnergyTask] {
        guard !manualOverride else { return [] }
        let now = currentDayPart
        let later = tasks.filter {
            !$0.isCompleted && $0.window.dayPart.order > now.order &&
            $0.energyRequired.rank <= currentEnergy.rank
        }
        return Array(later.sorted { matchRank($0.energyRequired) < matchRank($1.energyRequired) }.prefix(limit))
    }

    func bringToNow(_ task: EnergyTask) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[i].window.dayPart = currentDayPart
        flash("\(task.name) moved to \(currentDayPart.rawValue).")
        objectWillChange.send()
    }

    // MARK: - Stats

    var completedCount: Int { tasks.filter { $0.isCompleted }.count }
    var totalCount: Int { tasks.count }
    var progress: Double { totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount) }
    var completedTasks: [EnergyTask] { tasks.filter { $0.isCompleted } }

    // MARK: - Notifications (complete-by miss with quick actions)

    func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func refreshNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard completeByRemindersEnabled else { return }
        for t in tasks where !t.isCompleted { scheduleMissNotification(for: t) }
    }

    private func scheduleMissNotification(for task: EnergyTask) {
        guard completeByRemindersEnabled, let cb = task.completeBy, !task.isCompleted else { return }
        let cal = Calendar.current
        let passDate: Date
        if let exact = cb.exactTime {
            passDate = exact
        } else {
            let endHour = timeline.end(cb.dayPart)
            passDate = cal.date(bySettingHour: min(23, endHour), minute: 0, second: 0, of: Date()) ?? Date()
        }
        // Fire ~2h after the target passes, but never past the end of today (single-day app).
        let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 0, of: Date()) ?? Date()
        let fireDate = min(passDate.addingTimeInterval(2 * 60 * 60), endOfToday)
        guard fireDate > Date() else { return }

        // Is there still a later day-part after the notification fires?
        let firePart = timeline.part(forHour: cal.component(.hour, from: fireDate))
        let hasLaterSlot = DayPart.allCases.contains { $0.order > firePart.order }

        let content = UNMutableNotificationContent()
        if hasLaterSlot {
            content.title = "Still on your list"
            content.body = "\"\(task.name)\" passed its complete-by time. Mark it done, or move it to a later slot?"
        } else {
            content.title = "A gentle reminder"
            content.body = "You didn't get to \"\(task.name)\" today — no pressure. Tap if you actually finished it."
        }
        content.sound = .default
        content.userInfo = ["taskID": task.id.uuidString]
        content.categoryIdentifier = "TASK_MISSED"

        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "miss.\(task.id)", content: content, trigger: trigger))
    }

    func checkForMissedTasks() {
        guard rescheduleCandidate == nil else { return }
        let now = Date()
        if let missed = tasks.first(where: { t in
            guard !t.isCompleted, let cb = t.completeBy, let exact = cb.exactTime else { return false }
            return exact < now
        }) {
            rescheduleCandidate = missed
        }
    }
}
