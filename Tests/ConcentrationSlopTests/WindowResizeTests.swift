import AppKit
import Testing
@testable import ConcentrationSlop

struct WindowResizeTests {
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    private let start = NSRect(x: 100, y: 300, width: 320, height: 180)
    private let minimum = NSSize(width: 160, height: 90)

    @Test(arguments: VideoCorner.allCases)
    func resizesFromEveryCornerKeepingTheOppositeCornerFixed(corner: VideoCorner) {
        let room = NSRect(x: -1000, y: -1000, width: 4000, height: 3000)
        let delta = NSPoint(x: corner.isLeft ? -160 : 160, y: corner.isTop ? 90 : -90)
        let frame = WindowResize.frame(from: start, corner: corner, delta: delta, minimum: minimum, visible: room)
        #expect(abs(frame.width - 480) < 0.001)
        #expect(abs(frame.height - 270) < 0.001)
        #expect((corner.isLeft ? frame.maxX : frame.minX) == (corner.isLeft ? start.maxX : start.minX))
        #expect((corner.isTop ? frame.minY : frame.maxY) == (corner.isTop ? start.minY : start.maxY))
        let shrunk = WindowResize.frame(from: frame, corner: corner,
                                       delta: NSPoint(x: -delta.x, y: -delta.y), minimum: minimum, visible: room)
        #expect(abs(shrunk.minX - start.minX) < 0.001)
        #expect(abs(shrunk.minY - start.minY) < 0.001)
        #expect(abs(shrunk.width - start.width) < 0.001)
    }

    @Test(arguments: VideoCorner.allCases)
    func everyCornerStopsAtHostBounds(corner: VideoCorner) {
        let host = start.insetBy(dx: -40, dy: -30)
        let delta = NSPoint(x: corner.isLeft ? -5000 : 5000, y: corner.isTop ? 5000 : -5000)
        let frame = WindowResize.frame(from: start, corner: corner, delta: delta, minimum: minimum, visible: host)
        #expect(host.contains(frame))
        #expect(abs(frame.width / frame.height - start.width / start.height) < 0.001)
        #expect((corner.isLeft ? frame.maxX : frame.minX) == (corner.isLeft ? start.maxX : start.minX))
        #expect((corner.isTop ? frame.minY : frame.maxY) == (corner.isTop ? start.minY : start.maxY))
    }

    @Test
    func followsDiagonalDragWithoutMovingTopLeftOrCropping() {
        let frame = WindowResize.frame(from: start, corner: .bottomRight, delta: NSPoint(x: 160, y: -90), minimum: minimum, visible: screen)
        #expect(abs(frame.width - 480) < 0.001)
        #expect(abs(frame.height - 270) < 0.001)
        #expect(frame.minX == start.minX)
        #expect(frame.maxY == start.maxY)
    }

    @Test
    func clampsToMinimumAndAvailableScreenSpace() {
        let small = WindowResize.frame(from: start, corner: .bottomRight, delta: NSPoint(x: -1000, y: 1000), minimum: minimum, visible: screen)
        #expect(small.size == minimum)
        let large = WindowResize.frame(from: start, corner: .bottomRight, delta: NSPoint(x: 5000, y: -5000), minimum: minimum, visible: screen)
        #expect(screen.contains(large))
        #expect(abs(large.minY - screen.minY) < 0.001)
        #expect(abs(large.width / large.height - 16.0 / 9) < 0.001)
    }

    @Test
    func supportsPortraitVideoOnDisplaysWithNegativeOrigins() {
        let portrait = NSRect(x: -1000, y: 100, width: 180, height: 320)
        let leftScreen = NSRect(x: -1440, y: -200, width: 1440, height: 1100)
        let frame = WindowResize.frame(from: portrait, corner: .bottomRight, delta: NSPoint(x: 90, y: -160), minimum: NSSize(width: 160, height: 160 * 16 / 9), visible: leftScreen)
        #expect(abs(frame.width - 270) < 0.001)
        #expect(abs(frame.height - 480) < 0.001)
        #expect(frame.maxY == portrait.maxY)
        #expect(leftScreen.contains(frame))
    }
}
