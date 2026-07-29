import SwiftUI

struct DataExportSettingsPage: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.shiftColors) private var colors

    @State private var isExporting = false
    @State private var exportURLs: [URL] = []
    @State private var showShareSheet = false
    @State private var exportError: String?

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await export() }
                } label: {
                    HStack {
                        Spacer()
                        if isExporting {
                            ProgressView()
                        } else {
                            Label("Export My Data", systemImage: "square.and.arrow.up")
                        }
                        Spacer()
                    }
                }
                .disabled(isExporting)
            } footer: {
                Text("Creates a readable JSON backup and a CSV of every logged set. Progress photo links are included; the image files themselves remain protected in storage.")
            }

            Section("Included") {
                Label("Workout history and sets", systemImage: "dumbbell.fill")
                Label("Saved plans and programs", systemImage: "rectangle.stack.fill")
                Label("Weight and measurements", systemImage: "chart.line.uptrend.xyaxis")
                Label("Progress photo metadata", systemImage: "photo")
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.bg)
        .navigationTitle("Export Data")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            FileActivitySheet(urls: exportURLs)
        }
        .alert("Couldn't export data", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "Please try again.")
        }
    }

    private func export() async {
        guard let userID = authManager.currentUserId else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            exportURLs = try await DataExportService.makeExport(userID: userID)
            showShareSheet = true
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct FileActivitySheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
