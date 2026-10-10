import AppKit

@MainActor
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var attachmentBounds: CGRect?
    var userInteractionEnded: (() -> Void)?
    var userFrameChanged: ((CGRect, Bool) -> Void)?

    func updateFromUser(frame: CGRect, resized: Bool) {
        if let userFrameChanged { userFrameChanged(frame, resized) }
        else { setFrame(frame, display: true) }
    }

    func setApplicationBound(_ bound: Bool) {
        // Bound video belongs to one Space and participates in its native transition.
        // Floating panels otherwise default to transient behavior.
        collectionBehavior = bound
            ? [.managed, .fullScreenAuxiliary]
            : [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}
