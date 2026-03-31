import SwiftUI

/// Image view that loads from a URL using URLSession, leveraging URLCache.shared
/// for persistent disk and memory caching. Unlike SwiftUI's AsyncImage, cached
/// responses survive navigation transitions and app restarts.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        content(phase)
            .onChange(of: url) { _, newUrl in
                loadTask?.cancel()
                load(url: newUrl)
            }
            .onAppear { load(url: url) }
            .onDisappear { loadTask?.cancel() }
    }

    private func load(url: URL?) {
        guard let url else {
            phase = .empty
            return
        }

        let request = URLRequest(url: url)
        if let cached = URLCache.shared.cachedResponse(for: request),
           let uiImage = UIImage(data: cached.data) {
            phase = .success(Image(uiImage: uiImage))
            return
        }

        phase = .empty
        loadTask = Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }
                guard let uiImage = UIImage(data: data) else {
                    phase = .failure(URLError(.cannotDecodeContentData))
                    return
                }
                let cachedResponse = CachedURLResponse(response: response, data: data)
                URLCache.shared.storeCachedResponse(cachedResponse, for: request)
                phase = .success(Image(uiImage: uiImage))
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failure(error)
            }
        }
    }
}
