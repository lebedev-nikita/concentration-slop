import AVFoundation
import Foundation
import Testing
@testable import ConcentrationSlop

struct PlaybackIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CONCENTRATION_SLOP_LIVE_TEST"] == "1"))
    @MainActor
    func resolvesAndLoopsRealYouTubeMedia() async throws {
        // A short public recording keeps this optional network test bounded.
        let video = try await YouTubeResolver().resolve(YouTubeLink("https://youtu.be/jNQXAC9IVRw"))
        let player = AVQueuePlayer()
        player.isMuted = true
        let item = AVPlayerItem(url: video.url)
        let looper = AVPlayerLooper(player: player, templateItem: item)
        player.play()
        defer { player.pause(); looper.disableLooping(); player.removeAllItems() }
        let deadline = Date().addingTimeInterval(50)
        var advanced = false
        while Date() < deadline && looper.loopCount == 0 {
            if player.currentTime().seconds > 1 { advanced = true }
            if player.currentItem?.status == .failed {
                Issue.record("AVPlayer failed: \(player.currentItem?.error?.localizedDescription ?? "unknown")")
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        #expect(advanced, "The stream must actually play, not merely resolve to a URL")
        #expect(looper.loopCount >= 1, "Playback must cross the end of the recording and repeat")
    }
}
