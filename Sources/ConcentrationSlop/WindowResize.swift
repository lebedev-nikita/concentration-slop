import AppKit
import SwiftUI

enum VideoCorner: CaseIterable, Hashable {
    case topLeft, topRight, bottomLeft, bottomRight

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }
    var alignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }
    var label: String {
        switch self {
        case .topLeft: "левый верхний"
        case .topRight: "правый верхний"
        case .bottomLeft: "левый нижний"
        case .bottomRight: "правый нижний"
        }
    }

    @MainActor var cursor: NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition = switch self {
            case .topLeft: .topLeft
            case .topRight: .topRight
            case .bottomLeft: .bottomLeft
            case .bottomRight: .bottomRight
            }
            return .frameResize(position: position, directions: .all)
        }
        return isLeft == isTop ? Self.descendingCursor : Self.ascendingCursor
    }

    @MainActor private static let ascendingCursor = diagonalCursor(ascending: true)
    @MainActor private static let descendingCursor = diagonalCursor(ascending: false)

    @MainActor private static func diagonalCursor(ascending: Bool) -> NSCursor {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            let path = NSBezierPath()
            let lowY: CGFloat = ascending ? 5 : 19
            let highY: CGFloat = ascending ? 19 : 5
            let direction: CGFloat = ascending ? 1 : -1
            path.move(to: NSPoint(x: 5, y: lowY))
            path.line(to: NSPoint(x: 19, y: highY))
            path.move(to: NSPoint(x: 5, y: lowY + 6 * direction))
            path.line(to: NSPoint(x: 5, y: lowY))
            path.line(to: NSPoint(x: 11, y: lowY))
            path.move(to: NSPoint(x: 13, y: highY))
            path.line(to: NSPoint(x: 19, y: highY))
            path.line(to: NSPoint(x: 19, y: highY - 6 * direction))
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.white.setStroke()
            path.lineWidth = 4
            path.stroke()
            NSColor.black.setStroke()
            path.lineWidth = 2
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }
}

/// Keep the opposite corner and video ratio fixed while dragging any corner.
enum WindowResize {
    static func frame(from start: NSRect, corner: VideoCorner, delta: NSPoint, minimum: NSSize, visible: NSRect) -> NSRect {
        let ratio = start.width / start.height
        let horizontal: CGFloat = corner.isLeft ? -1 : 1
        let vertical: CGFloat = corner.isTop ? 1 : -1
        let anchorX = corner.isLeft ? start.maxX : start.minX
        let anchorY = corner.isTop ? start.minY : start.maxY
        let projectedWidth = start.width + (horizontal * delta.x + vertical * delta.y / ratio) / (1 + 1 / (ratio * ratio))
        let minimumWidth = max(minimum.width, minimum.height * ratio)
        let availableWidth = corner.isLeft ? anchorX - visible.minX : visible.maxX - anchorX
        let availableHeight = corner.isTop ? visible.maxY - anchorY : anchorY - visible.minY
        let maximumWidth = min(availableWidth, availableHeight * ratio)
        let width = min(max(projectedWidth, minimumWidth), max(minimumWidth, maximumWidth))
        let height = width / ratio
        return NSRect(x: corner.isLeft ? anchorX - width : anchorX,
                      y: corner.isTop ? anchorY : anchorY - height, width: width, height: height)
    }
}

private final class ResizeCornerView: NSView {
    var corner: VideoCorner = .bottomRight
    var resizing: (Bool) -> Void = { _ in }
    private var initialFrame: NSRect?
    private var initialPointer: NSPoint?
    private var cursorTracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var resizeCursor: NSCursor {
        corner.cursor
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: resizeCursor)
    }

    override func updateTrackingAreas() {
        if let cursorTracking { removeTrackingArea(cursorTracking) }
        let tracking = NSTrackingArea(rect: .zero,
                                      options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
        addTrackingArea(tracking)
        cursorTracking = tracking
        super.updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) { resizeCursor.set() }
    override func mouseEntered(with event: NSEvent) { resizeCursor.set() }
    override func mouseExited(with event: NSEvent) {
        if initialFrame == nil { NSCursor.arrow.set() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialFrame = window.frame
        initialPointer = window.convertPoint(toScreen: event.locationInWindow)
        resizeCursor.push()
        resizing(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let start = initialFrame, let pointer = initialPointer else { return }
        let current = window.convertPoint(toScreen: event.locationInWindow)
        let frame = WindowResize.frame(
            from: start, corner: corner, delta: NSPoint(x: current.x - pointer.x, y: current.y - pointer.y),
            minimum: window.contentMinSize,
            visible: (window as? FloatingPanel)?.attachmentBounds ?? (window.screen ?? NSScreen.main)?.visibleFrame ?? start
        )
        if let panel = window as? FloatingPanel {
            panel.updateFromUser(frame: frame, resized: true)
        } else { window.setFrame(frame, display: true) }
        resizeCursor.set()
    }

    override func mouseUp(with event: NSEvent) {
        if initialFrame != nil { NSCursor.pop() }
        initialFrame = nil
        initialPointer = nil
        window?.saveFrame(usingName: "FloatingVideoWindow")
        (window as? FloatingPanel)?.userInteractionEnded?()
        resizing(false)
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            resizeCursor.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}

struct ResizeCorner: NSViewRepresentable {
    let corner: VideoCorner
    let resizing: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ResizeCornerView()
        view.corner = corner
        view.resizing = resizing
        view.toolTip = "Потяните, чтобы изменить размер"
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.growArea)
        view.setAccessibilityLabel("Изменить размер: перетащите \(corner.label) угол.")
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
