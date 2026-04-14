import SwiftUI

struct PlansView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors

    @State private var planItems: [WorkoutPlanWithCount] = []
    @State private var isLoading = false
    @State private var showNewPlan = false
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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewPlan = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(colors.accent)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
        }
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

            Button {
                showNewPlan = true
            } label: {
                Text("Create Plan")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(colors.accent)
                    .clipShape(Capsule())
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
        VStack(alignment: .leading, spacing: 14) {
            // Header: name + chevron
            HStack {
                Text(item.plan.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(colors.text)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.muted)
            }

            // Exercise thumbnails
            if !item.exerciseImageUrls.isEmpty {
                HStack(spacing: 8) {
                    ForEach(item.exerciseImageUrls.prefix(4), id: \.self) { urlString in
                        if let url = URL(string: urlString) {
                            CachedAsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(colors.surface2)
                                }
                            }
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(colors.border, lineWidth: 1)
                            )
                        }
                    }
                    if item.exerciseCount > 4 {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(colors.surface2)
                            Text("+\(item.exerciseCount - 4)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(colors.muted)
                        }
                        .frame(width: 52, height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(colors.border, lineWidth: 1)
                        )
                    }
                }
            }

            // Footer: exercise count + duration + muscle groups
            HStack(spacing: 8) {
                Text(pluralise(item.exerciseCount, "exercise"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colors.muted)

                if item.estimatedMinutes > 0 {
                    Circle()
                        .fill(colors.muted.opacity(0.4))
                        .frame(width: 3, height: 3)

                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(WorkoutDurationEstimator.formatDuration(minutes: item.estimatedMinutes))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colors.muted)
                }

                if !item.muscleGroups.isEmpty {
                    Circle()
                        .fill(colors.muted.opacity(0.4))
                        .frame(width: 3, height: 3)

                    Text(item.muscleGroups.joined(separator: ", "))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(colors.accent)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
