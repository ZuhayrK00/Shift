import SwiftUI
import UIKit

// MARK: - ImageCache

/// Memory-bounded image cache. NSCache automatically evicts decoded images when
/// the process is under memory pressure.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let images = NSCache<NSString, UIImage>()
    private var pending: [String: [(@Sendable (UIImage?) -> Void)]] = [:]
    private let lock = NSLock()
    private let session: URLSession

    private init() {
        images.countLimit = 80
        images.totalCostLimit = 80 * 1_024 * 1_024

        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForRequest = 20
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.removeAll()
        }
    }

    func image(for url: URL) -> UIImage? {
        images.object(forKey: url.absoluteString as NSString)
    }

    func store(_ image: UIImage, for url: URL) {
        images.setObject(image, forKey: url.absoluteString as NSString, cost: image.memoryCost)
    }

    func removeAll() {
        images.removeAllObjects()
    }

    /// Prefetches only a small leading batch. Callers should prefer demand loading.
    func prefetch(_ urls: [URL]) {
        for url in urls.prefix(12) {
            lock.lock()
            let cached = images.object(forKey: url.absoluteString as NSString) != nil
            let inflight = pending[url.absoluteString] != nil
            lock.unlock()
            if cached || inflight { continue }
            fetch(url) { _ in }
        }
    }

    /// Fetches an image, returning a cached copy if available.
    func fetch(_ url: URL, completion: @escaping @Sendable (UIImage?) -> Void) {
        let key = url.absoluteString

        lock.lock()
        if let cached = images.object(forKey: key as NSString) {
            lock.unlock()
            completion(cached)
            return
        }
        if var waiters = pending[key] {
            waiters.append(completion)
            pending[key] = waiters
            lock.unlock()
            return
        }
        pending[key] = [completion]
        lock.unlock()

        session.dataTask(with: url) { [self] data, response, _ in
            let validData: Data? = {
                guard let data,
                      data.count <= 20 * 1_024 * 1_024,
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else { return nil }
                return data
            }()
            let img = validData.flatMap { UIImage(data: $0) }

            lock.lock()
            if let img {
                images.setObject(img, forKey: key as NSString, cost: img.memoryCost)
            }
            let waiters = pending.removeValue(forKey: key) ?? []
            lock.unlock()

            DispatchQueue.main.async {
                for w in waiters { w(img) }
            }
        }.resume()
    }
}

private extension UIImage {
    var memoryCost: Int {
        if let frames = images {
            return frames.reduce(0) { result, frame in
                result + (frame.cgImage.map { $0.bytesPerRow * $0.height } ?? 0)
            }
        }
        return cgImage.map { $0.bytesPerRow * $0.height } ?? 1
    }
}

// MARK: - CachedAsyncImage

/// Drop-in replacement for AsyncImage that uses the shared ImageCache.
/// Checks the cache synchronously on init so already-loaded images never flash.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase
    @State private var loadedURL: URL?

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
        _loadedURL = State(initialValue: url)
        if let url, let cached = ImageCache.shared.image(for: url) {
            _phase = State(initialValue: .success(Image(uiImage: cached)))
        } else {
            _phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                if loadedURL == url, case .success = phase { return }
                loadedURL = url
                phase = .empty
                guard let url else {
                    phase = .empty
                    return
                }
                if let cached = ImageCache.shared.image(for: url) {
                    phase = .success(Image(uiImage: cached))
                    return
                }
                let image: UIImage? = await withCheckedContinuation { continuation in
                    ImageCache.shared.fetch(url) { img in
                        continuation.resume(returning: img)
                    }
                }
                guard !Task.isCancelled, loadedURL == url else { return }
                phase = image.map { .success(Image(uiImage: $0)) } ?? .empty
            }
    }
}
