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
        GIFDataCache.shared.removeAll()
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

            // Also cache raw data so the GIF decoder doesn't need a second fetch
            if let validData { GIFDataCache.shared.store(validData, for: url) }

            DispatchQueue.main.async {
                for w in waiters { w(img) }
            }
        }.resume()
    }
}

// MARK: - GIFDataCache

/// Memory-bounded raw-data cache used by the GIF decoder.
final class GIFDataCache: @unchecked Sendable {
    static let shared = GIFDataCache()

    private let storage = NSCache<NSString, NSData>()

    private init() {
        storage.countLimit = 20
        storage.totalCostLimit = 30 * 1_024 * 1_024
    }

    func data(for url: URL) -> Data? {
        storage.object(forKey: url.absoluteString as NSString) as Data?
    }

    func store(_ data: Data, for url: URL) {
        guard data.count <= 20 * 1_024 * 1_024 else { return }
        storage.setObject(data as NSData, forKey: url.absoluteString as NSString, cost: data.count)
    }

    func removeAll() {
        storage.removeAllObjects()
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

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
        if let url, let cached = ImageCache.shared.image(for: url) {
            _phase = State(initialValue: .success(Image(uiImage: cached)))
        } else {
            _phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                if case .success = phase { return }
                guard let url else {
                    phase = .empty
                    return
                }
                if let cached = ImageCache.shared.image(for: url) {
                    phase = .success(Image(uiImage: cached))
                    return
                }
                await withCheckedContinuation { continuation in
                    ImageCache.shared.fetch(url) { [self] img in
                        Task { @MainActor in
                            if let img {
                                phase = .success(Image(uiImage: img))
                            } else {
                                phase = .empty
                            }
                            continuation.resume()
                        }
                    }
                }
            }
    }
}
