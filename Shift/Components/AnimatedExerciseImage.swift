import SwiftUI
import UIKit

/// Displays an animated GIF from a URL using UIKit's native GIF support.
/// Falls back to a placeholder if no URL is available.
struct AnimatedExerciseImage: View {
    let imageUrl: String?
    let exerciseName: String

    var body: some View {
        if let urlString = imageUrl, let url = URL(string: urlString) {
            GIFImageView(url: url)
                .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.white
            Text(String(exerciseName.prefix(1)).uppercased())
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Color(hex: "#7c5cff"))
        }
    }
}

// MARK: - UIKit GIF wrapper

/// UIViewRepresentable that loads and displays an animated GIF using UIImageView.
/// Uses UIImage.animatedImage for smooth hardware-accelerated playback.
private struct GIFImageView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        container.backgroundColor = .white

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.tag = 100
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        loadGIF(url: url, into: container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private func loadGIF(url: URL, into container: UIView) {
        // Use cached animated image if available
        if let cached = ImageCache.shared.image(for: url), cached.images != nil {
            setImage(cached, in: container)
            return
        }

        // Check if raw GIF data is already cached
        if let data = GIFDataCache.shared.data(for: url) {
            if let animated = decodeGIF(data: data) {
                ImageCache.shared.store(animated, for: url)
                setImage(animated, in: container)
            }
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data else { return }

            // Cache the raw data for instant re-decode
            GIFDataCache.shared.store(data, for: url)

            guard let animated = decodeGIF(data: data) else { return }
            ImageCache.shared.store(animated, for: url)

            DispatchQueue.main.async {
                setImage(animated, in: container)
            }
        }.resume()
    }

    private func setImage(_ image: UIImage, in container: UIView) {
        guard let imageView = container.viewWithTag(100) as? UIImageView else { return }
        imageView.image = image
    }

    private func decodeGIF(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var rawFrames: [UIImage] = []
        var rawDelays: [Double] = []

        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            rawFrames.append(UIImage(cgImage: cgImage))

            var delay = 0.1
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
               let gifDict = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                delay = (gifDict[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                    ?? (gifDict[kCGImagePropertyGIFDelayTime as String] as? Double)
                    ?? 0.1
                if delay < 0.02 { delay = 0.1 }
            }
            rawDelays.append(delay)
        }
        guard !rawFrames.isEmpty else { return nil }

        // UIImage.animatedImage uses a uniform frame duration, so we approximate
        // variable delays by duplicating frames proportionally.
        // Use the GIF's native timing, plus a 0.8s hold on first and last.
        let tick = 0.04  // smallest time slice
        let holdTicks = Int(0.8 / tick)

        var frames: [UIImage] = []

        // Hold first frame
        for _ in 0..<holdTicks { frames.append(rawFrames.first!) }

        // Native-timed frames
        for (i, img) in rawFrames.enumerated() {
            let copies = max(1, Int((rawDelays[i] / tick).rounded()))
            for _ in 0..<copies { frames.append(img) }
        }

        // Hold last frame
        for _ in 0..<holdTicks { frames.append(rawFrames.last!) }

        let totalDuration = Double(frames.count) * tick
        return UIImage.animatedImage(with: frames, duration: totalDuration)
    }
}
