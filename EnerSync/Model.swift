// Model.swift
// EnerSync — energy-aware task planner
// Theme (Soft Horizon palette), models, editable timelines.
// Compatible with iOS 18+ and iOS 26.

import SwiftUI

// MARK: - Theme (Soft Horizon: subtle dawn gradient + calm states)

enum Theme {
    static let base        = Color(hex: "5B8DA8")
    static let baseDark    = Color(hex: "456E86")
    static let accent      = Color(hex: "5B9A8B")
    static let background   = Color(hex: "FBFAF8")
    static let surface     = Color(hex: "FFFFFF")
    static let surfaceAlt   = Color(hex: "F3F1EE")
    static let text         = Color(hex: "20262E")
    static let textSec      = Color(hex: "5E6A72")
    static let textTer      = Color(hex: "9AA3AA")
    static let border       = Color(hex: "E7E4DF")

    static let dawnStart    = Color(hex: "A8C8E0")
    static let dawnEnd      = Color(hex: "C9B6D8")
    static var dawn: LinearGradient {
        LinearGradient(colors: [dawnStart, dawnEnd], startPoint: .leading, endPoint: .trailing)
    }
    static var dawnDiagonal: LinearGradient {
        LinearGradient(colors: [dawnStart, dawnEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let corner: CGFloat = 14
    static let cornerLarge: CGFloat = 18
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b: UInt64
        switch s.count {
        case 6: (r, g, b) = (v >> 16, v >> 8 & 0xFF, v & 0xFF)
        case 3: (r, g, b) = ((v >> 8) * 17, (v >> 4 & 0xF) * 17, (v & 0xF) * 17)
        default: (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: 1)
    }
}

// MARK: - Energy Level

enum EnergyLevel: String, CaseIterable, Identifiable, Codable, Comparable {
    case low    = "Low"
    case medium = "Medium"
    case high   = "High"

    var id: String { rawValue }
    var rank: Int { EnergyLevel.allCases.firstIndex(of: self) ?? 0 }
    static func < (lhs: EnergyLevel, rhs: EnergyLevel) -> Bool { lhs.rank < rhs.rank }

    var label: String { rawValue }

    var difficultyLabel: String {
        switch self { case .low: return "Easy"; case .medium: return "Medium"; case .high: return "Hard" }
    }
    var icon: String {
        switch self { case .low: return "leaf"; case .medium: return "flame"; case .high: return "bolt.fill" }
    }
    var barCount: Int { rank + 1 }

    var tint: Color {
        switch self {
        case .low:    return Color(hex: "ECE7F5")
        case .medium: return Color(hex: "E6F2EC")
        case .high:   return Color(hex: "FBEDE2")
        }
    }
    var accent: Color {
        switch self {
        case .low:    return Color(hex: "9D8EC4")
        case .medium: return Color(hex: "5B9A8B")
        case .high:   return Color(hex: "E8A87C")
        }
    }
    var ink: Color {
        switch self {
        case .low:    return Color(hex: "4C3F77")
        case .medium: return Color(hex: "2F5249")
        case .high:   return Color(hex: "824E29")
        }
    }
    var accessibilityText: String { "\(label) energy" }
}

// MARK: - Day Part (no "anytime"; user-editable ranges; rollover support)

enum DayPart: String, CaseIterable, Identifiable, Codable {
    case morning   = "Morning"
    case afternoon = "Afternoon"
    case evening   = "Evening"
    var id: String { rawValue }
    var order: Int { DayPart.allCases.firstIndex(of: self) ?? 0 }

    var defaultRange: ClosedRange<Int> {
        switch self {
        case .morning:   return 6...12
        case .afternoon: return 12...17
        case .evening:   return 17...22
        }
    }
    /// Next part a missed task rolls into (evening → nil = next day).
    var next: DayPart? {
        switch self {
        case .morning:   return .afternoon
        case .afternoon: return .evening
        case .evening:   return nil
        }
    }
}

struct TimelineConfig: Codable {
    var startHour: [String: Int]
    var endHour: [String: Int]

    static var `default`: TimelineConfig {
        var s: [String: Int] = [:], e: [String: Int] = [:]
        for p in DayPart.allCases {
            s[p.rawValue] = p.defaultRange.lowerBound
            e[p.rawValue] = p.defaultRange.upperBound
        }
        return TimelineConfig(startHour: s, endHour: e)
    }

    func start(_ p: DayPart) -> Int { startHour[p.rawValue] ?? p.defaultRange.lowerBound }
    func end(_ p: DayPart) -> Int { endHour[p.rawValue] ?? p.defaultRange.upperBound }
    func label(_ p: DayPart) -> String { "\(hour12(start(p))) – \(hour12(end(p)))" }

    /// Which part of the day a given hour belongs to.
    func part(forHour hour: Int) -> DayPart {
        for p in DayPart.allCases where hour >= start(p) && hour < end(p) { return p }
        if hour < start(.morning) { return .morning }
        return .evening
    }

    private func hour12(_ h: Int) -> String {
        let hh = h % 24
        if hh == 0 || hh == 24 { return "12 AM" }
        if hh == 12 { return "12 PM" }
        return hh < 12 ? "\(hh) AM" : "\(hh - 12) PM"
    }
}

// MARK: - Task time window

struct TaskWindow: Codable, Equatable {
    var dayPart: DayPart
    var customStartHour: Int?
    var customEndHour: Int?

    var isCustom: Bool { customStartHour != nil && customEndHour != nil }

    func label(using config: TimelineConfig) -> String {
        if let s = customStartHour, let e = customEndHour { return "\(h12(s)) – \(h12(e))" }
        return config.label(dayPart)
    }
    private func h12(_ h: Int) -> String {
        let hh = h % 24
        if hh == 0 || hh == 24 { return "12 AM" }
        if hh == 12 { return "12 PM" }
        return hh < 12 ? "\(hh) AM" : "\(hh - 12) PM"
    }
}

// MARK: - "Complete by" target (replaces deadline)

/// Soft target: finish by an exact time, or by a part of the day if no exact time given.
/// EnerSync does NOT remind beforehand. If the time passes and the task is still open,
/// it notifies ~2h later and offers to reschedule.
struct CompleteBy: Codable, Equatable {
    var exactTime: Date?
    var dayPart: DayPart

    func label(using config: TimelineConfig) -> String {
        if let t = exactTime { return "Complete by \(t.timeLabel)" }
        return "Complete by \(dayPart.rawValue.lowercased())"
    }
}

// MARK: - Task Model

struct EnergyTask: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var detail: String
    var energyRequired: EnergyLevel
    var window: TaskWindow
    var estimatedTime: Int
    var completeBy: CompleteBy?
    var isCompleted: Bool
    var scoreDelta: Int
    var deletedDate: Date?

    init(id: UUID = UUID(), name: String, detail: String = "",
         energyRequired: EnergyLevel, window: TaskWindow, estimatedTime: Int,
         completeBy: CompleteBy? = nil, isCompleted: Bool = false, scoreDelta: Int,
         deletedDate: Date? = nil) {
        self.id = id; self.name = name; self.detail = detail
        self.energyRequired = energyRequired; self.window = window
        self.estimatedTime = estimatedTime; self.completeBy = completeBy
        self.isCompleted = isCompleted; self.scoreDelta = scoreDelta
        self.deletedDate = deletedDate
    }

    /// Effort weight used for balancing tasks across day-part sections.
    var weight: Int { max(1, abs(scoreDelta)) }

    /// A task that adds energy when completed (leisure / recovery).
    var isRestorative: Bool { scoreDelta > 0 }
}

extension Date {
    var deadlineLabel: String { let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: self) }
    var timeLabel: String { let f = DateFormatter(); f.timeStyle = .short; return f.string(from: self) }
}
