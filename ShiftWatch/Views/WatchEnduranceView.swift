import SwiftUI

struct WatchEnduranceView: View {
    @Environment(WatchSessionManager.self) private var session
    @Environment(WatchWorkoutState.self) private var strength
    @State private var recorder = WatchEnduranceRecorder.shared
    @State private var sport: EnduranceSport = .run
    @State private var confirmDiscard = false
    @State private var navigateStrength = false
    private var context: WatchEnduranceContext? { session.context?.endurance }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let current = recorder.draft {
                    Text(current.sport.title).font(.title3.bold()).foregroundStyle(WatchColors.endurance)
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(EnduranceFormat.distance(current.distanceMeters, unit: context?.summary.distanceUnit ?? "km")).font(.system(size: 29, weight: .bold, design: .rounded)).minimumScaleFactor(0.7)
                            Text(EnduranceFormat.duration(current.activeSeconds(at: timeline.date))).font(.title2.monospacedDigit())
                            Text(EnduranceFormat.pace(distance: current.distanceMeters, seconds: current.activeSeconds(at: timeline.date), sport: current.sport, unit: context?.summary.distanceUnit ?? "km")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let heartRate = recorder.heartRate { Label("\(Int(heartRate)) bpm", systemImage: "heart.fill").foregroundStyle(.pink).font(.caption) }
                    if let calories = recorder.calories { Text("\(Int(calories)) active kcal").font(.caption).foregroundStyle(.secondary) }
                    Button(current.isPaused ? "Resume" : "Pause", systemImage: current.isPaused ? "play.fill" : "pause.fill") {
                        if current.isPaused { recorder.resume() } else { recorder.pause() }
                    }.tint(WatchColors.endurance).disabled(recorder.busy)
                    Button(recorder.busy ? "Saving…" : "Finish & save", systemImage: "checkmark") { Task { await recorder.finish() } }
                        .buttonStyle(.borderedProminent).tint(WatchColors.endurance).foregroundStyle(.black).disabled(recorder.busy)
                    Button("Discard", role: .destructive) { confirmDiscard = true }.disabled(recorder.busy)
                } else {
                    Picker("Sport", selection: $sport) { ForEach(EnduranceSport.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) } }
                    if recorder.preparing {
                        Label(recorder.ready ? "GPS ready" : "Waiting for GPS", systemImage: recorder.ready ? "location.fill" : "location")
                            .font(.caption).foregroundStyle(recorder.ready ? WatchColors.endurance : WatchColors.warning)
                        Button("Start recording", systemImage: "play.fill") { Task { await recorder.start() } }
                            .buttonStyle(.borderedProminent).tint(WatchColors.endurance).foregroundStyle(.black).disabled(!recorder.ready || recorder.busy)
                    } else {
                        Button("Start a \(sport.rawValue)", systemImage: sport.symbol) { Task { await recorder.prepare(sport: sport) } }
                            .buttonStyle(.borderedProminent).tint(WatchColors.endurance).foregroundStyle(.black)
                            .disabled(strength.isActive || session.context?.activeSession != nil || context?.phoneRecording == true)
                    }
                    if let message = recorder.savedMessage { Label(message, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(WatchColors.endurance) }
                    if let saved = recorder.lastSaved {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(saved.title).font(.headline)
                            Text(EnduranceFormat.distance(saved.distanceMeters, unit: context?.summary.distanceUnit ?? "km")).foregroundStyle(WatchColors.endurance)
                            Text("\(EnduranceFormat.duration(saved.activeSeconds)) active time").font(.caption)
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(WatchColors.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    let pending = WatchEnduranceOutbox.pendingCount(owner: session.context?.userId ?? "")
                    if pending > 0 { Text("\(pending) saved on Watch, waiting for iPhone.").font(.caption2).foregroundStyle(.secondary); Button("Retry sync") { WatchEnduranceOutbox.flush() } }
                    if let context {
                        TimelineView(.periodic(from: .now, by: 60)) { tick in
                            if let weather = context.summary.weather, weather.isFresh(at: tick.date) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Label("\(Int(weather.celsius.rounded()))°C · \(weather.condition)", systemImage: weather.symbol).font(.caption)
                                    Text("\(weather.place) · from iPhone").font(.caption2).foregroundStyle(.secondary)
                                    Text("Updated \(weather.fetchedAt.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                                    Link(destination: weather.legalURL) { Label("Weather · Data sources", systemImage: "apple.logo").font(.caption2) }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            Text("This week · synced from iPhone").font(.caption.bold())
                            Text(EnduranceFormat.distance(context.summary.distanceMeters, unit: context.summary.distanceUnit)).font(.title3.bold()).foregroundStyle(WatchColors.endurance)
                            Text("\(context.summary.activities) activities · \(Int(context.summary.activeSeconds / 60)) min").font(.caption).foregroundStyle(.secondary)
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(WatchColors.surface, in: RoundedRectangle(cornerRadius: 12))
                        if !context.summary.nextSessions.isEmpty {
                            Text("Your training calendar").font(.headline)
                            ForEach(Array(context.summary.nextSessions.prefix(6))) { item in
                                VStack(alignment: .leading, spacing: 7) {
                                    Label(item.title, systemImage: item.symbol).font(.caption.bold()).foregroundStyle(item.kind == .strength ? WatchColors.accent : WatchColors.endurance)
                                    if item.isAllDay == true { Text(item.scheduledAt, format: .dateTime.weekday(.abbreviated)).font(.caption2).foregroundStyle(.secondary) }
                                    else { Text(item.scheduledAt, format: .dateTime.weekday(.abbreviated).hour().minute()).font(.caption2).foregroundStyle(.secondary) }
                                    if !item.notes.isEmpty { Text(item.notes).font(.caption2).foregroundStyle(.secondary) }
                                    let target = item.targetLabel(unit: context.summary.distanceUnit)
                                    if !target.isEmpty { Text(target).font(.caption2) }
                                    Button("Start") { start(item) }.disabled(strength.isActive || session.context?.activeSession != nil || context.phoneRecording)
                                }.padding(10).background(WatchColors.surface, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        if !context.routes.isEmpty {
                            Text("Saved routes").font(.headline)
                            ForEach(context.routes) { route in
                                Button { sport = route.sport; Task { await recorder.prepare(sport: route.sport, routeID: route.id) } } label: {
                                    VStack(alignment: .leading, spacing: 4) { Label(route.title, systemImage: route.sport.symbol).font(.caption.bold()); Text(EnduranceFormat.distance(route.distanceMeters, unit: context.summary.distanceUnit)).font(.caption2) }
                                }.tint(WatchColors.endurance).disabled(strength.isActive || context.phoneRecording || session.context?.activeSession != nil)
                            }
                            Text("Saved routes are references. View the map on iPhone.").font(.caption2).foregroundStyle(.secondary)
                        }
                        ForEach(context.goals) { goal in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(goal.title).font(.caption)
                                ProgressView(value: min(goal.progress, goal.target), total: max(1, goal.target)).tint(WatchColors.endurance)
                                Text("\(Int(goal.progress)) / \(Int(goal.target)) \(goal.unit)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    } else { Text("Update and open Shift on iPhone to sync your calendar, goals and Watch recordings.").font(.caption).foregroundStyle(.secondary) }
                }
                if let error = recorder.error { Text(error).font(.caption).foregroundStyle(WatchColors.warning) }
            }.padding(.horizontal, 4)
        }.navigationTitle("Endurance")
            .task { await recorder.recover(); WatchEnduranceOutbox.flush() }
            .onDisappear { recorder.stopPreview() }
            .onChange(of: sport) { _, _ in if recorder.preparing && recorder.draft == nil { Task { await recorder.prepare(sport: sport) } } }
            .confirmationDialog("Discard this recording?", isPresented: $confirmDiscard) { Button("Discard", role: .destructive) { recorder.discard() } }
            .navigationDestination(isPresented: $navigateStrength) { WatchWorkoutView() }
    }
    private func start(_ item: TrainingSession) {
        if item.kind == .endurance {
            sport = item.sport ?? .run
            Task { await recorder.prepare(sport: sport, sessionID: item.id, routeID: item.routeID) }
        } else if let planID = item.strengthPlanID {
            session.startSessionFromPlan(planId: planID, scheduledSessionID: item.id) { id, name, date in
                Task { @MainActor in
                    guard let id else { return }
                    strength.start(sessionId: id, name: name ?? item.title, planId: planID, startedAt: date ?? Date(), exercises: [])
                    navigateStrength = true
                }
            }
        } else {
            session.startSession(name: item.title, scheduledSessionID: item.id) { id, name, date in
                Task { @MainActor in
                    guard let id else { return }
                    strength.start(sessionId: id, name: name ?? item.title, planId: nil, startedAt: date ?? Date(), exercises: [])
                    navigateStrength = true
                }
            }
        }
    }
}
