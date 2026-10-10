import Foundation
import Testing
@testable import ConcentrationSlop

struct PlaybackModelTests {
    @Test(arguments: [true, false])
    @MainActor
    func cancellingReplacementRestoresPlayback(wasPaused: Bool) async throws {
        let suite = "ConcentrationSlopTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = Bundle.module.url(forResource: "silent", withExtension: "mp4", subdirectory: "Fixtures")!
        let resolver = DelayedReplacementResolver(video: ResolvedVideo(title: "Test", url: fixture, isLive: false, headers: nil))
        let model = PlaybackModel(defaults: defaults, resolveVideo: { try await resolver.resolve($0) })
        defer { model.suspend() }
        model.linkText = "https://youtu.be/jNQXAC9IVRw"
        #expect(model.openLink())
        for _ in 0..<100 where !model.hasVideo {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.hasVideo)
        if wasPaused { model.togglePlayback() }
        #expect(model.isPaused == wasPaused)

        model.linkText = "https://youtu.be/3jEpiw87n5U"
        #expect(model.openLink())
        #expect(model.isLoading)
        model.cancelLoading()

        #expect(!model.isLoading)
        #expect(model.isPaused == wasPaused)
        if wasPaused { #expect(model.player.rate == 0) }
        #expect(defaults.string(forKey: "lastYouTubeURL") == "https://www.youtube.com/watch?v=jNQXAC9IVRw")
    }
    @Test(arguments: [true, false])
    @MainActor
    func hidingAndReturningPreservesPauseIncludingLoading(wasPaused: Bool) async throws {
        let suite = "VisibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = Bundle.module.url(forResource: "silent", withExtension: "mp4", subdirectory: "Fixtures")!
        let model = PlaybackModel(defaults: defaults, resolveVideo: { _ in
            try await Task.sleep(for: .milliseconds(20))
            return ResolvedVideo(title: "Test", url: fixture, isLive: false, headers: nil, width: 64, height: 64)
        })
        defer { model.suspend() }
        model.linkText = "https://youtu.be/jNQXAC9IVRw"
        #expect(model.openLink())
        model.setWindowVisible(false)
        for _ in 0..<100 where !model.hasVideo {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.hasVideo)
        #expect(model.player.rate == 0, "Resolution must not start playback while the window is hidden")
        #expect(model.videoAspectRatio == 1)
        if wasPaused { model.togglePlayback() }
        model.setWindowVisible(true)
        #expect(model.isPaused == wasPaused)
        model.setWindowVisible(false)
        #expect(model.player.rate == 0)
        model.setWindowVisible(true)
        #expect(model.isPaused == wasPaused, "Returning to a work app must preserve an explicit pause")
        if wasPaused { #expect(model.player.rate == 0) }
    }

}

private actor DelayedReplacementResolver {
    let video: ResolvedVideo
    private var requests = 0

    init(video: ResolvedVideo) { self.video = video }

    func resolve(_ link: YouTubeLink) async throws -> ResolvedVideo {
        requests += 1
        if requests > 1 { try await Task.sleep(for: .seconds(60)) }
        return video
    }
}
