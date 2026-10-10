import AppKit
import Combine
import SwiftUI

@MainActor
final class PanelInteraction: ObservableObject {
    @Published var isHovered = false
}

/// Track the whole surface, including controls, even while the work app keeps focus.
@MainActor
final class HoverHostingView<Content: View>: NSHostingView<Content> {
    var interaction: PanelInteraction?
    private var hoverTracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(tracking)
        hoverTracking = tracking
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { interaction?.isHovered = true }
    override func mouseExited(with event: NSEvent) { interaction?.isHovered = false }
}
