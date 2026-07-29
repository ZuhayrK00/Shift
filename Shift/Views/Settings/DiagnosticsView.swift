import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @Environment(\.shiftColors) private var colors
    @State private var snapshot: DiagnosticsSnapshot?
    @State private var isRefreshing = false
    @State private var copied = false

    var body: some View {
        Form {
            if let snapshot {
                Section("App") {
                    row("Version", "\(snapshot.appVersion) (\(snapshot.buildNumber))")
                    row("Subscription", snapshot.isPro ? "Shift Pro" : "Free")
                    dateRow("Entitlement checked", snapshot.entitlementVerifiedAt)
                }

                Section("Data sync") {
                    dateRow("Last sync", snapshot.lastReferenceSync)
                    row("Pending changes", "\(snapshot.pendingChanges)")
                    row("Failed changes", "\(snapshot.failedChanges)")
                    if snapshot.pendingChanges > 0 {
                        dateRow("Next retry", snapshot.nextRetry)
                    }
                    if let error = snapshot.lastQueueError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(colors.danger)
                    }
                }

                Section("Watch & widgets") {
                    row("Watch", watchSummary(snapshot))
                    dateRow("Watch sync", snapshot.watchLastSync)
                    dateRow("Widget data", snapshot.widgetUpdatedAt)
                }

                Section {
                    Button {
                        Task { await retry() }
                    } label: {
                        HStack {
                            Spacer()
                            if isRefreshing {
                                ProgressView()
                            } else {
                                Label("Retry Everything", systemImage: "arrow.clockwise")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isRefreshing)

                    Button {
                        UIPasteboard.general.string = snapshot.shareableText
                        copied = true
                    } label: {
                        HStack {
                            Spacer()
                            Label(
                                copied ? "Copied" : "Copy Diagnostics",
                                systemImage: copied ? "checkmark" : "doc.on.doc"
                            )
                            Spacer()
                        }
                    }
                } footer: {
                    Text("The copied report excludes account details, workout data and access tokens.")
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.bg)
        .navigationTitle("Sync & Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task { snapshot = await DiagnosticsService.load() }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(colors.muted)
                .multilineTextAlignment(.trailing)
        }
    }

    private func dateRow(_ title: String, _ date: Date?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let date {
                Text(date, style: .relative)
                    .foregroundStyle(colors.muted)
            } else {
                Text("Never")
                    .foregroundStyle(colors.muted)
            }
        }
    }

    private func watchSummary(_ value: DiagnosticsSnapshot) -> String {
        guard value.watchPaired else { return "Not paired" }
        guard value.watchInstalled else { return "App not installed" }
        return value.watchReachable ? "Connected" : "Background"
    }

    private func retry() async {
        isRefreshing = true
        copied = false
        snapshot = await DiagnosticsService.retryEverything()
        isRefreshing = false
    }
}
