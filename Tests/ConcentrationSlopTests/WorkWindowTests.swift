import CoreGraphics
import Testing
@testable import ConcentrationSlop

struct WorkWindowTests {
    private let original = WorkWindow(id: 10, frame: CGRect(x: 100, y: 100, width: 1000, height: 700))

    @Test
    func keepsNearestEdgeInsetsDuringLiveResize() {
        for video in [CGRect(x: 748, y: 570, width: 300, height: 168.75),
                      CGRect(x: 142, y: 132, width: 300, height: 168.75)] {
            let placement = VideoPlacement(video: video, host: original.frame)
            for step in 1...100 {
                let host = CGRect(x: 100, y: 100, width: 1000 - step * 3, height: 700 - step * 2)
                let frame = placement.frame(in: host, aspectRatio: 16 / 9)
                if video.midX > original.frame.midX {
                    #expect(abs(host.maxX - frame.maxX - (original.frame.maxX - video.maxX)) < 0.001)
                    #expect(abs(host.maxY - frame.maxY - (original.frame.maxY - video.maxY)) < 0.001)
                } else {
                    #expect(frame.minX - host.minX == video.minX - original.frame.minX)
                    #expect(frame.minY - host.minY == video.minY - original.frame.minY)
                }
            }
        }
    }

    @Test
    func migratesExistingPlacementWithoutLosingPreferredSize() throws {
        let saved = ["x": 1.0, "y": 1.0, "width": 480.0]
        let placement = try #require(VideoPlacement(legacySaved: saved, host: original.frame, aspectRatio: 16 / 9))
        let frame = placement.frame(in: original.frame, aspectRatio: 16 / 9)
        #expect(frame.maxX == original.frame.maxX - 12)
        #expect(frame.maxY == original.frame.maxY - 12)
        #expect(placement.preferredWidth == 480)
        #expect(VideoPlacement(saved: placement.saved) == placement)
    }

    @Test
    func doesNotJumpToAnotherWindowOfTheSameAppOnAnotherSpace() {
        var attachment = WorkWindowAttachment()
        #expect(attachment.resolve(pid: 7, snapshot: WorkWindowSnapshot(visible: [original], attachedWindowExists: false)) == original)
        let other = WorkWindow(id: 20, frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(attachment.resolve(pid: 7, snapshot: WorkWindowSnapshot(visible: [other], attachedWindowExists: true)) == nil)
        #expect(attachment.windowID == original.id)
        #expect(attachment.resolve(pid: 7, snapshot: WorkWindowSnapshot(visible: [original], attachedWindowExists: true)) == original)
        #expect(attachment.resolve(pid: 7, snapshot: WorkWindowSnapshot(visible: [other], attachedWindowExists: false)) == other)
        // A process restart invalidates the old window identity.
        #expect(attachment.resolve(pid: 8, snapshot: WorkWindowSnapshot(visible: [original], attachedWindowExists: true)) == original)
    }

    @Test
    func movesAndShrinksWithinHostThenRestoresPreferredSize() {
        let video = CGRect(x: 748, y: 122, width: 340, height: 191.25)
        let placement = VideoPlacement(video: video, host: original.frame)
        let movedHost = original.frame.offsetBy(dx: -400, dy: 200)
        let moved = placement.frame(in: movedHost, aspectRatio: 16 / 9)
        #expect(moved == video.offsetBy(dx: -400, dy: 200))
        let smallHost = CGRect(x: -300, y: 300, width: 220, height: 150)
        let small = placement.frame(in: smallHost, aspectRatio: 16 / 9)
        #expect(smallHost.contains(small))
        #expect(small.width < video.width)
        #expect(abs(small.width / small.height - 16 / 9) < 0.001)
        #expect(placement.frame(in: original.frame, aspectRatio: 16 / 9) == video)
    }

    @Test
    func clampsAnOldAbsolutePositionAndRetainsAnchorWhileHostIsTiny() {
        let outside = CGRect(x: 1200, y: 900, width: 331, height: 187)
        var placement = VideoPlacement(video: outside, host: original.frame)
        #expect(original.frame.contains(placement.frame(in: original.frame, aspectRatio: 331 / 187)))
        let tiny = CGRect(x: 0, y: 0, width: 100, height: 70)
        let fitted = placement.frame(in: tiny, aspectRatio: 331 / 187)
        let preferredWidth = placement.preferredWidth
        placement.capture(video: fitted, host: tiny, resized: false)
        #expect(placement.preferredWidth == preferredWidth)
        #expect(tiny.contains(fitted))
        #expect(VideoPlacement(saved: placement.saved) == placement)
    }
}
