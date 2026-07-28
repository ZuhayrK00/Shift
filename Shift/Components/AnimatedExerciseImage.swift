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

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data,
                  data.count <= 20 * 1_024 * 1_024,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return }

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
        var totalDuration: Double = 0
        let maximumFrameCount = 24
        let stride = max(1, Int(ceil(Double(count) / Double(maximumFrameCount))))
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 360,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]

        for i in Swift.stride(from: 0, to: count, by: stride) {
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                i,
                thumbnailOptions as CFDictionary
            ) else { continue }
            rawFrames.append(UIImage(cgImage: cgImage))

            var delay = 0.1
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
               let gifDict = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                delay = (gifDict[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                    ?? (gifDict[kCGImagePropertyGIFDelayTime as String] as? Double)
                    ?? 0.1
                if delay < 0.02 { delay = 0.1 }
            }
            totalDuration += delay * Double(stride)
        }
        guard !rawFrames.isEmpty else { return nil }

        return UIImage.animatedImage(
            with: rawFrames,
            duration: max(totalDuration, Double(rawFrames.count) * 0.1)
        )
    }
}
