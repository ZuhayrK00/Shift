import SwiftUI

// MARK: - ImageCache

/// Persistent in-memory image cache. Uses a plain dictionary (not NSCache)
/// so entries are never evicted by the OS. The exercise image set is bounded
/// (~300 small thumbnails) so memory impact is negligible.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private var images: [String: UIImage] = [:]
    private var pending: [String: [(@Sendable (UIImage?) -> Void)]] = [:]
    private let lock = NSLock()

    private init() {}

    func image(for url: URL) -> UIImage? {
        lock.lock()
        let img = images[url.absoluteString]
        lock.unlock()
        return img
    }

    func store(_ image: UIImage, for url: URL) {
        lock.lock()
        images[url.absoluteString] = image
        lock.unlock()
    }

    /// Prefetch a batch of URLs in the background (fire-and-forget).
    func prefetch(_ urls: [URL]) {
        for url in urls {
            lock.lock()
            let cached = images[url.absoluteString] != nil
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
        if let cached = images[key] {
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

        URLSession.shared.dataTask(with: url) { [self] data, _, _ in
            let img = data.flatMap { UIImage(data: $0) }

            lock.lock()
            if let img { images[key] = img }
            let waiters = pending.removeValue(forKey: key) ?? []
            lock.unlock()

            // Also cache raw data so the GIF decoder doesn't need a second fetch
            if let data { GIFDataCache.shared.store(data, for: url) }

            DispatchQueue.main.async {
                for w in waiters { w(img) }
            }
        }.resume()
    }
}

// MARK: - GIFDataCache

/// Persistent in-memory cache for raw GIF data so the animated decoder can
/// re-use it instantly without a second network fetch.
final class GIFDataCache: @unchecked Sendable {
    static let shared = GIFDataCache()

    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    private init() {}

    func data(for url: URL) -> Data? {
        lock.lock()
        let d = storage[url.absoluteString]
        lock.unlock()
        return d
    }

    func store(_ data: Data, for url: URL) {
        lock.lock()
        storage[url.absoluteString] = data
        lock.unlock()
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
                    ImageCache.shared.fetch(url) { img in
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
