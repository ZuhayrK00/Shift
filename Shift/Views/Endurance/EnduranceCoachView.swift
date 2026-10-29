import SwiftUI

struct EnduranceCoachView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.shiftColors) private var colors
    @State private var store = StoreService.shared
    @State private var access = EnduranceProAccess.shared
    @State private var showPro = false
    @State private var messages: [CoachMessage] = []
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var data = TrainingHub()
    @FocusState private var composerFocused: Bool
    private struct CoachMessage: Identifiable { var id = UUID(); var user: Bool; var text: String }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    NavigationLink { EndurancePlannerView() } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "calendar.badge.plus").font(.title2).foregroundStyle(colors.enduranceAccent)
                                .frame(width: 48, height: 48).background(colors.enduranceAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Build my week").font(.headline)
                                Text("A plan around your time and the weather").font(.caption).foregroundStyle(colors.muted)
                            }
                            Spacer(minLength: 0); Image(systemName: "arrow.up.right").font(.subheadline).foregroundStyle(colors.enduranceAccent)
                        }.padding(17).background(colors.enduranceSoft, in: RoundedRectangle(cornerRadius: 22))
                    }.buttonStyle(.plain)
                    if !store.isPro && !store.isCheckingEntitlement {
                        if access.decision == .freeWeek { EnduranceFreeWeekNote() }
                        EnduranceProCard(title: "Talk it through with your coach", message: "Get help with running, walking and cycling routines. Your coach and continued personalised planning are included in Shift Pro.") { showPro = true }
                    }
                    if messages.isEmpty && store.isPro {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("What are you working towards?").font(.system(.title, design: .rounded, weight: .bold))
                            Text("Talk through a goal or find a way to fit training into your week.").font(.subheadline).foregroundStyle(colors.muted)
                        }.padding(.top, 12)
                        if let reason = EnduranceCoachService.unavailableReason {
                            Text(reason).font(.footnote).foregroundStyle(colors.muted)
                        } else {
                            VStack(spacing: 10) {
                                prompt("Fit five walks into my week", icon: "figure.walk", message: "How can I fit five walks into my week?")
                                prompt("Balance running and gym days", icon: "figure.run", message: "Help me balance running with gym days.")
                                prompt("Get started with cycling", icon: "figure.outdoor.cycle", message: "What should I consider when planning my first regular rides?")
                            }
                            Label("Private conversation · on your device", systemImage: "lock.shield").font(.caption2).foregroundStyle(colors.muted)
                        }
                    }
                    if store.isPro { ForEach(messages) { item in
                        HStack(alignment: .top, spacing: 0) {
                            if item.user { Spacer(minLength: 28) }
                            VStack(alignment: .leading, spacing: 10) {
                                if !item.user {
                                    Label("Shift coach", systemImage: "sparkle").font(.caption.weight(.semibold)).foregroundStyle(colors.enduranceAccent)
                                }
                                Text(item.text).font(.body).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }.padding(item.user ? 16 : 4)
                                .background(item.user ? colors.surface2 : .clear, in: RoundedRectangle(cornerRadius: 20))
                            if !item.user { Spacer(minLength: 8) }
                        }
                    }
                    }
                    if busy && store.isPro { CoachThinkingView() }
                    if let error { Text(error).font(.footnote).foregroundStyle(colors.warning) }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in withAnimation(.smooth) { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: busy) { _, _ in withAnimation(.smooth) { proxy.scrollTo("bottom", anchor: .bottom) } }
        }.background(colors.bg).foregroundStyle(colors.text).tint(colors.enduranceAccent)
            .navigationTitle("Shift coach").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom) {
                if store.isPro && EnduranceCoachService.unavailableReason == nil { composer }
            }
            .task(id: auth.currentUserId) {
                task?.cancel(); messages = []; error = nil; busy = false
                await store.updatePurchasedProducts(); await access.load(); await data.load()
                #if SHIFT_STORE_CAPTURE && targetEnvironment(simulator)
                if StoreCaptureConfiguration.enabled && StoreCaptureConfiguration.screen == "coach" {
                    // Illustrative conversation for local product photography, never a live AI result.
                    messages = [
                        .init(user: true, text: "I want to walk five times this week. I can do 30 minutes after work, and I train at the gym on Monday and Thursday."),
                        .init(user: false, text: "Keep the walks easy on gym days. A short walk after work gives you a simple starting point.\n\nUse Build my week to choose your available days and times. It can check the forecast and avoid busy times in your calendar. You can review each walk before saving it.")
                    ]
                }
                #endif
            }
            .sheet(isPresented: $showPro) { ProPaywallView(endurance: true) }
            .onChange(of: store.isPro) { _, pro in
                if !pro { task?.cancel(); busy = false }
                Task { await access.load() }
            }
            .onDisappear { task?.cancel() }
    }
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message your coach", text: $text, axis: .vertical).lineLimit(1...5).focused($composerFocused)
                .padding(.vertical, 10).padding(.leading, 6).submitLabel(.send).onSubmit { send() }
                .onChange(of: text) { _, value in if value.count > 1_500 { text = String(value.prefix(1_500)) } }
            Button { send() } label: {
                Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colors.onAccent).frame(width: 42, height: 42)
                    .background(colors.enduranceAccent.opacity(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1), in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("Send to Shift coach").disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(8).background(colors.surface, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(composerFocused ? colors.enduranceAccent.opacity(0.5) : colors.border, lineWidth: 1))
            .padding(.horizontal, 20).padding(.vertical, 12).background(colors.bg)
    }
    private func prompt(_ title: String, icon: String, message: String) -> some View {
        Button { text = message; send() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(colors.enduranceAccent).frame(width: 25)
                Text(title).font(.subheadline)
                Spacer(); Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(colors.muted)
            }.padding(16).background(colors.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(colors.border, lineWidth: 1))
        }.buttonStyle(.plain)
    }
    private func send() {
        guard store.isPro else { showPro = true; return }
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !prompt.isEmpty, prompt.count <= 1_500, EnduranceCoachService.unavailableReason == nil else { return }
        composerFocused = false
        text = ""; error = nil; busy = true; messages.append(.init(user: true, text: prompt))
        let owner = auth.currentUserId
        let weather = EnduranceWeatherService.shared.snapshot
        let weatherContext: String
        if let weather, weather.isFresh(at: Date()) { weatherContext = "Latest conditions for \(weather.place): \(weather.current.condition), \(Int(weather.current.celsius)) Celsius. This is current weather only, not a future forecast." }
        else { weatherContext = "No current weather data is available." }
        let context = "The user has \(data.activities.count) saved endurance activities and \(data.sessions.filter { $0.scheduledAt > Date() && $0.status == .scheduled }.count) upcoming Shift sessions. \(weatherContext)"
        let transcript = messages.map { (user: $0.user, text: $0.text) }
        task = Task {
            defer { if auth.currentUserId == owner { busy = false } }
            do {
                let answer = try await EnduranceCoachService.reply(to: transcript, context: context)
                guard !Task.isCancelled, auth.currentUserId == owner, store.isPro else { return }
                messages.append(.init(user: false, text: answer))
            } catch EnduranceProService.AccessError.proRequired {
                if !Task.isCancelled, auth.currentUserId == owner { showPro = true }
            } catch { if !Task.isCancelled, auth.currentUserId == owner { self.error = "Couldn't get a reply. Try again, or use Build my week to plan your sessions." } }
        }
    }
}

struct CoachThinkingView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var title = "Working on your reply"
    @State private var started = Date()
    var body: some View {
        TimelineView(.periodic(from: started, by: 0.35)) { tick in
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    ForEach(0..<3) { index in
                        let active = Int(tick.date.timeIntervalSince(started) / 0.35) % 3 == index
                        Circle().fill(colors.enduranceAccent.opacity(reduceMotion || active ? 1 : 0.25)).frame(width: 6, height: 6)
                            .offset(y: !reduceMotion && active ? -2 : 0)
                    }
                }.frame(width: 35)
                Text(title).font(.caption).foregroundStyle(colors.muted)
            }.padding(.vertical, 10)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Shift coach is preparing a reply")
    }
}
