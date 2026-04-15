import SwiftUI

// MARK: - WorkoutShareCard
//
// Full-screen story-style card (9:16) rendered as an image for sharing.
// Designed to look great on Instagram Stories, iMessage, etc.
// Uses hard-coded dark colours so it renders consistently.

struct WorkoutShareCard: View {
    let workoutName: String
    let date: Date
    let durationMinutes: Int
    let exerciseCount: Int
    let setCount: Int
    let totalVolume: String
    let weightUnit: String
    let blocks: [ShareBlock]
    var calories: Double? = nil
    var avgHeartRate: Double? = nil

    struct ShareBlock: Identifiable {
        var id: String
        var name: String
        var sets: [ShareSet]
        var note: String?
    }

    struct ShareSet: Identifiable {
        var id: String
        var weight: Double?
        var reps: Int
        var setType: SetType
    }

    // Hard-coded palette
    private let bg       = Color(hex: "#0b0b0f")
    private let surface  = Color(hex: "#16161d")
    private let surface2 = Color(hex: "#1f1f29")
    private let border   = Color(hex: "#2a2a36")
    private let text     = Color(hex: "#f5f5f7")
    private let muted    = Color(hex: "#9a9aae")
    private let accent   = Color(hex: "#7c5cff")
    private let accent2  = Color(hex: "#22d3ee")
    private let success  = Color(hex: "#22c55e")

    // 9:16 story dimensions
    private let cardWidth: CGFloat  = 390
    private let cardHeight: CGFloat = 693 // 390 * 16/9

    var body: some View {
        ZStack {
            // Background gradient
            backgroundGradient

            VStack(spacing: 0) {
                Spacer().frame(height: 40)

                // Top branding
                branding
                    .padding(.horizontal, 28)
                    .padding(.bottom, 32)

                // Hero section — workout name + duration
                heroSection
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)

                // Stats grid
                statsGrid
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)

                // Divider line
                Rectangle()
                    .fill(text.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)

                // Exercise list
                exerciseList
                    .padding(.horizontal, 28)

                Spacer()

                // Footer
                footer
                    .padding(.horizontal, 28)
                    .padding(.bottom, 36)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipped()
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            bg

            // Accent glow top-right
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.25), accent.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: 140, y: -180)

            // Secondary glow bottom-left
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent2.opacity(0.12), accent2.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .offset(x: -140, y: 260)

            // Noise overlay for texture
            bg.opacity(0.3)
        }
    }

    // MARK: - Branding

    private var branding: some View {
        HStack {
            Image("ShiftLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 28)
            Spacer()
            Text(formattedDate)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(muted)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Completion badge
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(success)
                Text("COMPLETED")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(success)
            }

            // Workout name
            Text(workoutName)
                .font(.system(size: 32, weight: .black))
                .foregroundStyle(text)
                .lineLimit(2)

            // Duration — big and bold
            Text(WorkoutDurationEstimator.formatDuration(minutes: durationMinutes))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(text.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        let items: [(String, String, String)] = {
            var list: [(String, String, String)] = [
                ("\(exerciseCount)", exerciseCount == 1 ? "Exercise" : "Exercises", "dumbbell.fill"),
                ("\(setCount)", setCount == 1 ? "Set" : "Sets", "checkmark.circle"),
                (totalVolume, weightUnit, "scalemass"),
            ]
            if let cal = calories, cal > 0 {
                list.append(("\(Int(cal.rounded()))", "kcal", "flame.fill"))
            }
            if let bpm = avgHeartRate, bpm > 0 {
                list.append(("\(Int(bpm.rounded()))", "bpm", "heart.fill"))
            }
            return list
        }()

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: min(items.count, 4)),
            spacing: 10
        ) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 4) {
                    Image(systemName: item.2)
                        .font(.system(size: 13))
                        .foregroundStyle(accent)
                    Text(item.0)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(text)
                    Text(item.1)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(muted)
                        .textCase(.uppercase)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(text.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Exercise list

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks.prefix(8)) { block in
                exerciseRow(block)
            }
            if blocks.count > 8 {
                Text("+\(blocks.count - 8) more")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(muted)
            }
        }
    }

    @ViewBuilder
    private func exerciseRow(_ block: ShareBlock) -> some View {
        HStack(spacing: 12) {
            // Accent dot
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(block.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(text)
                    .lineLimit(1)

                // Compact set summary
                let completedSets = block.sets
                if !completedSets.isEmpty {
                    Text(setsSummary(completedSets))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(muted)
                }

                if let note = block.note, !note.isEmpty {
                    Text("\"\(note)\"")
                        .font(.system(size: 11).italic())
                        .foregroundStyle(muted.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Set count badge
            Text("\(block.sets.count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.12))
                .clipShape(Circle())
        }
    }

    private func setsSummary(_ sets: [ShareSet]) -> String {
        // Group identical weight x reps combos: "80kg x 8 (x3)"
        var groups: [(String, Int)] = []
        for set in sets {
            let weightText: String = {
                if let w = set.weight { return formatWeight(w, unit: weightUnit) }
                return "BW"
            }()
            let label = "\(weightText) x \(set.reps)"
            if let last = groups.last, last.0 == label {
                groups[groups.count - 1].1 += 1
            } else {
                groups.append((label, 1))
            }
        }
        return groups.map { $0.1 > 1 ? "\($0.0) (x\($0.1))" : $0.0 }
            .joined(separator: "  ·  ")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .center) {
            Text(formattedDate)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(muted)
            Spacer()
        }
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }
}
