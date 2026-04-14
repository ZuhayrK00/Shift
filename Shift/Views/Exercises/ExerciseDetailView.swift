import SwiftUI

struct ExerciseDetailView: View {
    @Environment(\.shiftColors) private var colors
    let exercise: Exercise

    var initialTab: Tab = .about
    @State private var activeTab: Tab = .about

    enum Tab: String, CaseIterable {
        case about    = "About"
        case history  = "History"
        case progress = "Progress"
        case goals    = "Goals"
    }

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Tab bar (always visible at top)
                tabBar
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                // Tab content
                switch activeTab {
                case .about:
                    aboutContent
                case .history:
                    ExerciseHistoryView(exerciseId: exercise.id)
                case .progress:
                    ExerciseProgressView(exerciseId: exercise.id)
                case .goals:
                    ExerciseGoalsView(exercise: exercise)
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { activeTab = initialTab }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { activeTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(activeTab == tab ? colors.text : colors.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(activeTab == tab ? colors.surface : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(colors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }

    // MARK: - Hero image

    private var heroImage: some View {
        AnimatedExerciseImage(
            imageUrl: exercise.imageUrl,
            exerciseName: exercise.name
        )
    }

    // MARK: - About tab content

    private var aboutContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero image
                heroImage
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Metadata chips
                metadataChips

                // Description
                if let description = exercise.description, !description.isEmpty {
                    infoCard(title: "About") {
                        Text(description)
                            .font(.system(size: 14))
                            .foregroundStyle(colors.muted)
                            .lineSpacing(4)
                    }
                }

                // Instructions
                if let steps = exercise.instructionsSteps, !steps.isEmpty {
                    infoCard(title: "Instructions") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(colors.accent)
                                        .frame(width: 22, height: 22)
                                        .background(colors.accent.opacity(0.15))
                                        .clipShape(Circle())
                                    Text(step)
                                        .font(.system(size: 14))
                                        .foregroundStyle(colors.text)
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                } else if let instructions = exercise.instructions, !instructions.isEmpty {
                    infoCard(title: "Instructions") {
                        Text(instructions)
                            .font(.system(size: 14))
                            .foregroundStyle(colors.text)
                            .lineSpacing(4)
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Metadata chips

    private var metadataChips: some View {
        let chips: [(String?, String)] = [
            (exercise.level?.capitalized, "figure.strengthtraining.traditional"),
            (exercise.category?.capitalized, "tag"),
            (exercise.bodyPart?.capitalized, "person"),
            (exercise.force?.capitalized, "arrow.up.and.down"),
            (exercise.mechanic?.capitalized, "gearshape"),
            (exercise.equipment?.capitalized, "dumbbell")
        ]

        return FlowLayout(spacing: 8) {
            ForEach(chips.filter { $0.0 != nil }, id: \.1) { chip in
                HStack(spacing: 5) {
                    Image(systemName: chip.1)
                        .font(.system(size: 10))
                        .foregroundStyle(colors.accent)
                    Text(chip.0!)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(colors.text)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(colors.surface2)
                .overlay(
                    Capsule().stroke(colors.border, lineWidth: 1)
                )
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Info card

    @ViewBuilder
    private func infoCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.muted)
                .textCase(.uppercase)
                .kerning(0.5)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - FlowLayout

/// Wrapping horizontal layout for chip rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                totalHeight = y
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
