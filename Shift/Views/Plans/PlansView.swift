import SwiftUI

struct PlansView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors
    @Environment(StoreService.self) private var store

    @State private var planItems: [WorkoutPlanWithCount] = []
    @State private var programs: [WorkoutProgramSummary] = []
    @State private var standalonePlans: [WorkoutPlanWithCount] = []
    @State private var isLoading = false
    @State private var showNewPlan = false
    @State private var showExplore = false
    @State private var showAIGenerator = false
    @State private var showQuickSession = false
    @State private var showPaywall = false
    @State private var toastMessage: String?
    @State private var showToast = false
    @State private var selectedProgram: WorkoutProgramSummary?
    @State private var showProgramDetail = false
    @State private var startedSessionID: String?
    @State private var showStartedWorkout = false
    @State private var isStartingWorkout = false
    @State private var actionError: String?

    private let freePlanLimit = ProFeaturePolicy.freePlanLimit

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            Group {
                if isLoading {
                    ProgressView()
                        .tint(colors.accent)
                } else {
                    plansContent
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
                    if !store.isPro {
                        Section("\(planItems.count)/\(freePlanLimit) free plans used") {
                            if planItems.count >= freePlanLimit {
                                Button {
                                    showPaywall = true
                                } label: {
                                    Label("Upgrade to Pro", systemImage: "star.fill")
                                }
                            } else {
                                Button {
                                    showNewPlan = true
                                } label: {
                                    Label("Blank Plan", systemImage: "doc")
                                }
                            }
                        }
                    } else {
                        Button {
                            showNewPlan = true
                        } label: {
                            Label("Blank Plan", systemImage: "doc")
                        }
                    }
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
        .modifier(
            AIGeneratorDestination(
                isPresented: $showAIGenerator,
                quickSession: false,
                onSaved: showAISaveConfirmation,
                onDisappear: { Task { await loadPlans() } }
            )
        )
        .modifier(
            AIGeneratorDestination(
                isPresented: $showQuickSession,
                quickSession: true,
                onSaved: showAISaveConfirmation,
                onDisappear: { Task { await loadPlans() } }
            )
        )
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
        .navigationDestination(isPresented: $showProgramDetail) {
            if let selectedProgram {
                WorkoutProgramDetailView(program: selectedProgram) {
                    WorkoutProgramService.setActiveProgram(
                        selectedProgram.id,
                        userID: selectedProgram.workouts.first?.plan.userId ?? ""
                    )
                    Task { await loadPlans() }
                } onChanged: {
                    Task { await loadPlans() }
                }
            }
        }
        .navigationDestination(isPresented: $showStartedWorkout) {
            if let startedSessionID {
                WorkoutView(sessionId: startedSessionID)
            }
        }
        .task { await loadPlans() }
        .sheet(isPresented: $showPaywall) {
            ProPaywallView()
        }
        .alert("Couldn't start workout", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
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

    // MARK: - Plans hub

    private var plansContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                creationHub

                if planItems.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(colors.muted)
                        Text("Your saved workouts will appear here")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(colors.text)
                        Text("Build a program, start from a template, or create one yourself.")
                            .font(.system(size: 13))
                            .foregroundStyle(colors.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .padding(.horizontal, 24)
                } else {
                    if !programs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Programs")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(colors.text)

                            ForEach(programs) { program in
                                WorkoutProgramCard(
                                    program: program,
                                    isStarting: isStartingWorkout,
                                    onOpen: {
                                        selectedProgram = program
                                        showProgramDetail = true
                                    },
                                    onStart: {
                                        if let next = program.nextWorkout {
                                            Task { await startWorkout(next.plan) }
                                        }
                                    }
                                )
                            }
                        }
                    }

                    if !standalonePlans.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Workouts")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(colors.text)
                                Spacer()
                                Text(pluralise(standalonePlans.count, "workout"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(colors.muted)
                            }

                            LazyVStack(spacing: 10) {
                                ForEach(standalonePlans) { item in
                                    NavigationLink(value: item.plan) {
                                        PlanCard(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var creationHub: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Build your next workout")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(colors.text)
                Text("Start with a private AI draft, a proven template, or a blank canvas.")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.muted)
            }

            #if canImport(FoundationModels)
            if #available(iOS 26, *) {
                let availability = AppleIntelligencePlanService.availability
                VStack(spacing: 0) {
                    Button {
                        openAIBuilder(quickSession: false)
                    } label: {
                        creationRow(
                            icon: "sparkles",
                            title: "Build a program",
                            subtitle: "A complete \(store.isPro ? "goal-aware" : "Pro") training split",
                            badge: "AI",
                            enabled: true
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().overlay(colors.border).padding(.leading, 54)

                    Button {
                        openAIBuilder(quickSession: true)
                    } label: {
                        creationRow(
                            icon: "bolt.fill",
                            title: "Make a quick workout",
                            subtitle: "One session for the time and equipment you have",
                            badge: "AI",
                            enabled: true
                        )
                    }
                    .buttonStyle(.plain)
                }
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(colors.border, lineWidth: 1))

                if availability != .available {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(availability.title)
                                .font(.system(size: 12, weight: .semibold))
                            Text(availability.message)
                                .font(.system(size: 11))
                        }
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .foregroundStyle(colors.muted)
                } else {
                    Label(
                        "Runs privately with Apple Intelligence. You'll review the draft before anything is saved.",
                        systemImage: "lock.shield"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(colors.muted)
                }
            }
            #endif

            HStack(spacing: 10) {
                Button {
                    showExplore = true
                } label: {
                    compactCreationButton(icon: "square.grid.2x2", title: "Templates")
                }
                .buttonStyle(.plain)

                Button {
                    if !store.isPro && planItems.count >= freePlanLimit {
                        showPaywall = true
                    } else {
                        showNewPlan = true
                    }
                } label: {
                    compactCreationButton(icon: "plus", title: "Blank workout")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func openAIBuilder(quickSession: Bool) {
        guard store.isPro else {
            showPaywall = true
            return
        }
        if quickSession {
            showQuickSession = true
        } else {
            showAIGenerator = true
        }
    }

    private func creationRow(
        icon: String,
        title: String,
        subtitle: String,
        badge: String,
        enabled: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(enabled ? colors.accent : colors.muted)
                .frame(width: 34, height: 34)
                .background((enabled ? colors.accent : colors.muted).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(enabled ? colors.text : colors.muted)
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(colors.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colors.accent.opacity(0.1))
                        .clipShape(Capsule())
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(colors.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colors.muted)
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private func compactCreationButton(icon: String, title: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(colors.text)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.border, lineWidth: 1))
    }

    // MARK: - Data loading

    private func loadPlans() async {
        isLoading = planItems.isEmpty
        async let plansResult = PlanService.listPlans()
        let userID = authManager.currentUserId ?? ""
        async let sessionsResult = SessionRepository.findCompleted(userId: userID)
        planItems = (try? await plansResult) ?? []
        let sessions = (try? await sessionsResult) ?? []
        let grouped = WorkoutProgramService.summaries(
            plans: planItems,
            completedSessions: sessions,
            userID: userID
        )
        programs = grouped.programs
        standalonePlans = grouped.standalone
        isLoading = false
    }

    private func startWorkout(_ plan: WorkoutPlan) async {
        guard !isStartingWorkout else { return }
        isStartingWorkout = true
        defer { isStartingWorkout = false }
        do {
            if let existing = try await WorkoutService.getLatestInProgress() {
                startedSessionID = existing.id
                showStartedWorkout = true
                return
            }
            let session = try await PlanService.createSessionFromPlan(plan.id)
            startedSessionID = session.id
            showStartedWorkout = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func showAISaveConfirmation(_ count: Int) {
        toastMessage = count == 1 ? "Saved workout" : "Saved \(count) workouts"
        showToast = true
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
    var onSaved: (Int) -> Void
    var onDisappear: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.navigationDestination(isPresented: $isPresented) {
                AIPlanGeneratorView(quickSession: quickSession, onSaved: onSaved)
                    .onDisappear { onDisappear() }
            }
        } else {
            content
        }
    }
}
#endif
