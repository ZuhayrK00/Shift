import SwiftUI
import UIKit

/// Cross-fades discrete RepDB poses on detail surfaces, not motion footage.
struct AnimatedExerciseImage: View {
    @Environment(\.shiftColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let imageUrl: String?
    let exerciseName: String
    var secondaryImageUrl: String? = nil
    @State private var startImage: UIImage?
    @State private var peakImage: UIImage?
    @State private var showPeak = false
    @State private var paused = false
    @State private var loadedURLs = ""
    private var taskKey: String {
        "\(imageUrl ?? "")|\(secondaryImageUrl ?? "")|\(scenePhase == .active)|\(reduceMotion)|\(paused)"
    }
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                colors.surface2
                if let startImage {
                    Image(uiImage: startImage).resizable().scaledToFit()
                    if let peakImage {
                        Image(uiImage: peakImage).resizable().scaledToFit().opacity(showPeak ? 1 : 0)
                    }
                } else {
                    Text(String(exerciseName.prefix(1)).uppercased())
                        .font(.system(size: 56, weight: .bold)).foregroundStyle(colors.accent)
                }
            }
            if peakImage != nil && !reduceMotion {
                Button { paused.toggle() } label: {
                    Label(paused ? "Play poses" : "Pause poses", systemImage: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11, weight: .semibold)).padding(8)
                        .background(colors.surface).foregroundStyle(colors.text).clipShape(Capsule())
                }.padding(10).buttonStyle(.plain)
            }
        }
        .clipped()
        .accessibilityLabel("\(exerciseName) exercise illustration")
        .task(id: taskKey) {
            showPeak = false
            let urls = "\(imageUrl ?? "")|\(secondaryImageUrl ?? "")"
            if loadedURLs != urls {
                startImage = nil
                peakImage = nil
                loadedURLs = urls
            }
            guard let url = imageUrl.flatMap(URL.init(string:)) else {
                startImage = nil; peakImage = nil; return
            }
            let start = await load(url)
            guard !Task.isCancelled else { return }
            startImage = start
            if let peakURL = secondaryImageUrl.flatMap(URL.init(string:)), peakURL != url {
                let peak = await load(peakURL)
                guard !Task.isCancelled else { return }
                peakImage = peak
            } else { peakImage = nil }
            guard peakImage != nil, startImage != nil, scenePhase == .active, !reduceMotion, !paused else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1.8)) } catch { return }
                withAnimation(.easeInOut(duration: 0.45)) { showPeak.toggle() }
            }
        }
    }
    private func load(_ url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            ImageCache.shared.fetch(url) { continuation.resume(returning: $0) }
        }
    }
}
