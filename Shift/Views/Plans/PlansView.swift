import SwiftUI

struct PlansView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors

    @State private var planItems: [WorkoutPlanWithCount] = []
    @State private var isLoading = false
    @State private var showNewPlan = false
    @State private var showExplore = false
    @State private var showAIGenerator = false
    @State private var showQuickSession = false
    @State private var toastMessage: String?
    @State private var showToast = false

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            Group {
                if isLoading {
                    ProgressView()
                        .tint(colors.accent)
                } else if planItems.isEmpty {
                    emptyState
                } else {
                    planList
                }
            }
        }
        .navigationTitle("Plans")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showExplore = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "compass")
                        Text("Explore")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.accent)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showNewPlan = true
                    } label: {
                        Label("Blank Plan", systemImage: "doc")
                    }

                    #if canImport(FoundationModels)
                    if #available(iOS 26, *) {
                        Section("AI-Powered") {
                            Button {
                                showAIGenerator = true
                            } label: {
                                Label("Full Program", systemImage: "sparkles")
                            }
                            Button {
                                showQuickSession = true
                            } label: {
                                Label("Quick Session", systemImage: "bolt.fill")
                            }
                        }
                    }
                    #endif
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(colors.accent)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
        }
        .navigationDestination(isPresented: $showExplore) {
            ExplorePlansView()
                .onDisappear { Task { await loadPlans() } }
        }
        #if canImport(FoundationModels)
        .modifier(AIGeneratorDestination(isPresented: $showAIGenerator, quickSession: false, onDisappear: {
            Task { await loadPlans() }
        }))
        .modifier(AIGeneratorDestination(isPresented: $showQuickSession, quickSession: true, onDisappear: {
            Task { await loadPlans() }
        }))
        #endif
        .navigationDestination(isPresented: $showNewPlan) {
            NewPlanView(
                onCreate: { newPlan in
                    planItems.append(WorkoutPlanWithCount(plan: newPlan, exerciseCount: 0, muscleGroups: [], exerciseImageUrls: [], estimatedMinutes: 0))
                },
                onSaved: { name, deleted in
                    toastMessage = deleted
                        ? "Deleted \"\(name)\""
                        : "Saved \"\(name)\""
                    showToast = true
                    Task { await loadPlans() }
                }
            )
        }
        .navigationDestination(for: WorkoutPlan.self) { plan in
            PlanEditorView(plan: plan) { deleted in
                toastMessage = deleted
                    ? "Deleted \"\(plan.name)\""
                    : "Saved \"\(plan.name)\""
                showToast = true
                Task { await loadPlans() }
            }
        }
        .task { await loadPlans() }
        .overlay(alignment: .bottom) {
            if showToast, let message = toastMessage {
                PlanToast(message: message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 24)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showToast = false
                            }
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.4), value: showToast)
    }

    // MARK: - Plan list

    private var planList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(planItems) { item in
                    NavigationLink(value: item.plan) {
                        PlanCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(colors.muted)

            Text("No plans yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(colors.text)

            Text("Create a plan to organize your workouts.")
                .font(.system(size: 14))
                .foregroundStyle(colors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            HStack(spacing: 12) {
                Button {
                    showExplore = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "compass")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Explore")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(colors.accent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(colors.accent.opacity(0.12))
                    .clipShape(Capsule())
                }

                Menu {
                    Button {
                        showNewPlan = true
                    } label: {
                        Label("Blank Plan", systemImage: "doc")
                    }

                    #if canImport(FoundationModels)
                    if #available(iOS 26, *) {
                        Section("AI-Powered") {
                            Button {
                                showAIGenerator = true
                            } label: {
                                Label("Full Program", systemImage: "sparkles")
                            }
                            Button {
                                showQuickSession = true
                            } label: {
                                Label("Quick Session", systemImage: "bolt.fill")
                            }
                        }
                    }
                    #endif
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Create")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(colors.accent)
                    .clipShape(Capsule())
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Data loading

    private func loadPlans() async {
        isLoading = planItems.isEmpty
        planItems = (try? await PlanService.listPlans()) ?? []
        isLoading = false
    }
}

// MARK: - PlanCard

private struct PlanCard: View {
    @Environment(\.shiftColors) private var colors
    let item: WorkoutPlanWithCount

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image strip at top
            if !item.exerciseImageUrls.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(item.exerciseImageUrls.prefix(5).enumerated()), id: \.offset) { _, urlString in
                        if let url = URL(string: urlString) {
                            CachedAsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    Rectangle().fill(colors.surface2)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 70)
                            .clipped()
                        }
                    }
                }
                .overlay(
                    LinearGradient(
                        colors: [.clear, colors.surface.opacity(0.8), colors.surface],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            // Content
            VStack(alignment: .leading, spacing: 10) {
                // Name + chevron
                HStack(alignment: .center) {
                    Text(item.plan.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(colors.text)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(colors.muted)
                }

                // Muscle group tags
                if !item.muscleGroups.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(item.muscleGroups.prefix(3), id: \.self) { group in
                            Text(group)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(colors.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(colors.accent.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }

                // Stats row
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "dumbbell")
                            .font(.system(size: 10))
                        Text(pluralise(item.exerciseCount, "exercise"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(colors.muted)

                    if item.estimatedMinutes > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(WorkoutDurationEstimator.formatDuration(minutes: item.estimatedMinutes))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(colors.muted)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(colors.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - PlanToast

private struct PlanToast: View {
    @Environment(\.shiftColors) private var colors
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(colors.success)
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colors.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(colors.surface)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        )
        .overlay(Capsule().stroke(colors.border, lineWidth: 1))
    }
}

// MARK: - AI Generator Destination

#if canImport(FoundationModels)
private struct AIGeneratorDestination: ViewModifier {
    @Binding var isPresented: Bool
    var quickSession: Bool
    var onDisappear: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.navigationDestination(isPresented: $isPresented) {
                AIPlanGeneratorView(quickSession: quickSession)
                    .onDisappear { onDisappear() }
            }
        } else {
            content
        }
    }
}
#endif
