import AppKit
import Testing
@testable import ConcentrationSlop

@MainActor
struct FloatingPanelTests {
    @Test
    func boundPanelLeavesWithItsSpaceWithoutWaitingForAppActivation() {
        _ = NSApplication.shared
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.setApplicationBound(false)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        panel.setApplicationBound(true)
        #expect(!panel.collectionBehavior.contains(.canJoinAllSpaces), "A bound panel must not remain on the destination Space until didActivateApplication arrives")
        #expect(panel.collectionBehavior.contains(.managed), "Space transitions must be managed by WindowServer, rather than floating outside the transition")
        #expect(!panel.collectionBehavior.contains(.moveToActiveSpace), "Space changes must not pull a bound panel away from its work Space")
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        panel.setApplicationBound(false)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(!panel.collectionBehavior.contains(.managed))
    }
}
