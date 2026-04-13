import SwiftUI

/// In-memory image cache backed by NSCache. Shared singleton so exercise
/// thumbnails load instantly after the first fetch within an app session.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    /// Track in-flight downloads so we don't fire duplicate requests.
    private var pending: [String: [(@Sendable (UIImage?) -> Void)]] = [:]
    private let lock = NSLock()

    private init() {
        cache.countLimit = 500
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url.absoluteString as NSString)
    }

    /// Prefetch a batch of URLs in the background (fire-and-forget).
    func prefetch(_ urls: [URL]) {
        for url in urls {
            let key = url.absoluteString as NSString
            if cache.object(forKey: key) != nil { continue }

            lock.lock()
            let alreadyPending = pending[url.absoluteString] != nil
            lock.unlock()
            if alreadyPending { continue }

            fetch(url) { _ in }
        }
    }

    /// Fetches an image, returning a cached copy if available.
    func fetch(_ url: URL, completion: @escaping @Sendable (UIImage?) -> Void) {
        let key = url.absoluteString

        if let cached = cache.object(forKey: key as NSString) {
            completion(cached)
            return
        }

        lock.lock()
        if var waiters = pending[key] {
            waiters.append(completion)
            pending[key] = waiters
            lock.unlock()
            return
        }
        pending[key] = [completion]
        lock.unlock()

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            let img = data.flatMap { UIImage(data: $0) }
            if let img { self.cache.setObject(img, forKey: key as NSString) }

            // Also cache raw data so the GIF decoder doesn't need a second fetch
            if let data { GIFDataCache.shared.store(data, for: url) }

            self.lock.lock()
            let waiters = self.pending.removeValue(forKey: key) ?? []
            self.lock.unlock()

            DispatchQueue.main.async {
                for w in waiters { w(img) }
            }
        }.resume()
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
        // Check cache synchronously so returning to this view doesn't flash the placeholder
        if let url, let cached = ImageCache.shared.image(for: url) {
            _phase = State(initialValue: .success(Image(uiImage: cached)))
        } else {
            _phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                // Skip if already loaded (from init or previous task run)
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
