// Components.swift
// EnerSync — reusable UI components.

import SwiftUI

// MARK: - Dynamic logo (progress rings synced to completion %)

/// Concentric rings in the calm dawn palette; the outer ring fills with progress.
/// Used as the app's living mark on the schedule header.
struct EnerSyncLogo: View {
    var progress: Double
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.surfaceAlt, lineWidth: size * 0.13)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(Theme.dawn,
                        style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(Theme.dawnEnd.opacity(0.55),
                        style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .scaleEffect(0.62)
                .animation(.easeInOut(duration: 0.6), value: progress)
            Circle()
                .fill(Theme.dawnDiagonal)
                .frame(width: size * 0.26, height: size * 0.26)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("EnerSync, \(Int(progress * 100)) percent of today complete")
    }
}

// MARK: - Accessible energy indicator (bars: shape + height, not color alone)

struct EnergyBars: View {
    let level: EnergyLevel
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < level.barCount ? level.accent : level.accent.opacity(0.22))
                    .frame(width: 5, height: CGFloat(6 + i * 5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.accessibilityText)
    }
}

struct EnergyChip: View {
    let level: EnergyLevel
    var body: some View {
        HStack(spacing: 7) {
            EnergyBars(level: level)
            Text(level.label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(level.ink)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(level.tint)
        .clipShape(Capsule())
    }
}

// MARK: - Progress card (matches attached screenshot design)

/// Ring on the left with center %, "Making progress!" headline, and
/// "x done · y left" with check / circle markers — per the screenshot.
struct ProgressCard: View {
    let progress: Double
    let done: Int
    let total: Int

    private var headline: String {
        switch progress {
        case 0:        return "Ready to begin"
        case 0..<0.34: return "Making progress!"
        case 0.34..<0.67: return "Going strong!"
        case 0.67..<1: return "Almost there!"
        default:       return "All done!"
        }
    }

    var body: some View {
        HStack(spacing: 20) {
            // Ring with center percentage
            ZStack {
                Circle().stroke(Theme.surfaceAlt, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: max(0.001, progress))
                    .stroke(Theme.dawn, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
            }
            .frame(width: 78, height: 78)

            VStack(alignment: .leading, spacing: 8) {
                Text(headline)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.text)
                HStack(spacing: 18) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(Theme.accent)
                        Text("\(done) done")
                            .foregroundColor(Theme.accent)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .foregroundColor(Theme.textTer)
                        Text("\(max(0, total - done)) left")
                            .foregroundColor(Theme.textTer)
                    }
                }
                .font(.system(size: 16, weight: .medium, design: .rounded))
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - Energy classifier (matches screenshot: leaf / flame / bolt cards)

struct EnergyClassifier: View {
    @Binding var selection: EnergyLevel
    var body: some View {
        HStack(spacing: 14) {
            ForEach(EnergyLevel.allCases) { level in
                Button { selection = level } label: {
                    VStack(spacing: 12) {
                        Image(systemName: level.icon)
                            .font(.system(size: 26))
                            .foregroundColor(level.accent)
                            .frame(height: 30)
                        Text(level.difficultyLabel)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(selection == level ? level.ink : Theme.textSec)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(selection == level ? level.tint : Theme.surfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                            .stroke(selection == level ? level.accent : .clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(level.difficultyLabel), \(level.accessibilityText)")
            }
        }
    }
}

// MARK: - Step control

struct StepControl: View {
    @Binding var minutes: Int
    var body: some View {
        HStack(spacing: 16) {
            stepButton("minus") { minutes = max(5, minutes - 5) }
            Text("\(minutes) min")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.text).frame(minWidth: 90)
            stepButton("plus") { minutes += 5 }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12).background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
    private func stepButton(_ symbol: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.base)
                .frame(width: 44, height: 44).background(Theme.surfaceAlt).clipShape(Circle())
        }.buttonStyle(.plain)
    }
}
