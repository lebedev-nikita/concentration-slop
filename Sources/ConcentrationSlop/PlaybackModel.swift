import AVFoundation
import Combine
import Foundation

@MainActor
final class PlaybackModel: ObservableObject {
    @Published var title = "Concentration Slop"
    @Published var isLoading = false
    @Published var isPaused = false
    @Published var errorMessage: String?
    @Published var linkText: String
    @Published private(set) var hasVideo = false
    @Published private(set) var videoAspectRatio = 16.0 / 9.0

    let player = AVQueuePlayer()
    private let defaults: UserDefaults
    private let resolveVideo: @Sendable (YouTubeLink) async throws -> ResolvedVideo
    private var looper: AVPlayerLooper?
    private var loadTask: Task<Void, Never>?
    private var itemObservation: NSKeyValueObservation?
    private var loadID = UUID()
    private var playbackID = UUID()
    private var wasPausedBeforeLoading = false
    private var isWindowVisible = true

    init(
        defaults: UserDefaults = .standard,
        resolveVideo: @escaping @Sendable (YouTubeLink) async throws -> ResolvedVideo = { try await YouTubeResolver().resolve($0) }
    ) {
        self.defaults = defaults
        self.resolveVideo = resolveVideo
        linkText = defaults.string(forKey: "lastYouTubeURL") ?? ""
        player.isMuted = true
    }

    @discardableResult
    func openLink() -> Bool {
        let link: YouTubeLink
        do { link = try YouTubeLink(linkText) }
        catch { errorMessage = error.localizedDescription; return false }
        startLoading(link)
        return true
    }

    private func startLoading(_ link: YouTubeLink) {
        loadTask?.cancel()
        loadID = UUID()
        let id = loadID
        errorMessage = nil
        if !isLoading { wasPausedBeforeLoading = isPaused }
        isLoading = true
        isPaused = false
        player.pause()
        let resolve = resolveVideo
        loadTask = Task { [weak self] in
            do {
                let video = try await resolve(link)
                try Task.checkCancellation()
                guard let self, self.loadID == id else { return }
                self.configure(video, id: id)
                self.linkText = link.url.absoluteString
                self.defaults.set(self.linkText, forKey: "lastYouTubeURL")
                self.title = video.title
                self.isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.loadID == id else { return }
                self.isLoading = false
                self.isPaused = true
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func configure(_ video: ResolvedVideo, id: UUID) {
        playbackID = id
        playbackObservation = nil
        itemObservation = nil
        looper?.disableLooping()
        player.removeAllItems()
        let asset = AVURLAsset(url: video.url, options: video.headers?["User-Agent"].map {
            [AVURLAssetHTTPUserAgentKey: $0]
        })
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
        hasVideo = true
        if let width = video.width, let height = video.height, height > 0,
           (0.25...4).contains(width / height) {
            videoAspectRatio = width / height
        } else {
            videoAspectRatio = 16.0 / 9.0
        }
        itemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
            let item = player.currentItem
            Task { @MainActor [weak self] in
                guard let self, self.playbackID == id else { return }
                self.observeItem(item, id: id)
            }
        }
        if isWindowVisible && !isPaused { player.play() }
    }

    private var playbackObservation: NSKeyValueObservation?

    private func observeItem(_ item: AVPlayerItem?, id: UUID) {
        playbackObservation = item?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let failed = item.status == .failed
            Task { @MainActor [weak self] in
                guard let self, self.playbackID == id, failed else { return }
                self.player.pause()
                self.isPaused = true
                self.errorMessage = "Поток недоступен или ссылка на него истекла. Нажмите «Повторить», чтобы получить новую."
            }
        }
    }

    func togglePlayback() {
        isPaused.toggle()
        isPaused || !isWindowVisible ? player.pause() : player.play()
    }

    func suspend() {
        loadTask?.cancel()
        loadID = UUID()
        isLoading = false
        player.pause()
        isPaused = true
    }

    func setWindowVisible(_ visible: Bool) {
        guard isWindowVisible != visible else { return }
        isWindowVisible = visible
        if visible && !isPaused && hasVideo {
            player.play()
        } else {
            player.pause()
        }
    }

    func cancelLoading() {
        guard isLoading else { return }
        loadTask?.cancel()
        loadID = UUID()
        isLoading = false
        isPaused = wasPausedBeforeLoading
        if hasVideo && !isPaused && isWindowVisible { player.play() }
    }
}
