import AppKit
import ApplicationServices

/// WindowServer supplies Space visibility and identity; Accessibility supplies
/// logical geometry, without the compositor's animated desktop translation.
@MainActor
final class LogicalWindowMonitor {
    private struct Identity: Equatable, Sendable {
        let pid: pid_t
        let windowID: CGWindowID
    }

    private let queue = DispatchQueue(label: "ConcentrationSlop.window-geometry", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var identity: Identity?
    private var generation = UUID()
    private var reader: WindowGeometryReader?
    private(set) var latestFrame: CGRect?

    func follow(pid: pid_t, window: WorkWindow, desktopTop: CGFloat,
                changed: @escaping @MainActor (CGRect) -> Void) {
        guard AXIsProcessTrusted() else { stop(); return }
        let next = Identity(pid: pid, windowID: window.id)
        if identity == next, let reader {
            queue.async { reader.referenceFrame = window.frame }
            return
        }
        stop()
        identity = next
        let generation = generation
        let reader = WindowGeometryReader(pid: pid, frame: window.frame, desktopTop: desktopTop)
        self.reader = reader
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // IPC stays off the UI thread. One serial reader bounds work and avoids
        // an accumulating backlog when the host app is temporarily unresponsive.
        timer.schedule(deadline: .now(), repeating: 1.0 / 120, leeway: .milliseconds(1))
        timer.setEventHandler { @Sendable [weak self] in
            guard let frame = reader.changedFrame() else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                guard self.latestFrame != frame else { return }
                self.latestFrame = frame
                changed(frame)
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        generation = UUID()
        timer?.cancel()
        timer = nil
        reader = nil
        identity = nil
        latestFrame = nil
    }
}

/// AX objects and mutable state are confined to the monitor's serial queue.
private final class WindowGeometryReader: @unchecked Sendable {
    let pid: pid_t
    let desktopTop: CGFloat
    var referenceFrame: CGRect
    private var application: AXUIElement?
    private var window: AXUIElement?
    private var deliveredFrame: CGRect?

    init(pid: pid_t, frame: CGRect, desktopTop: CGFloat) {
        self.pid = pid
        referenceFrame = frame
        self.desktopTop = desktopTop
    }

    func changedFrame() -> CGRect? {
        guard let frame = frame(), frame != deliveredFrame else { return nil }
        deliveredFrame = frame
        return frame
    }

    private func frame() -> CGRect? {
        if let window { return geometry(of: window) }
        let application = self.application ?? AXUIElementCreateApplication(pid)
        self.application = application
        AXUIElementSetMessagingTimeout(application, 0.02)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        // Match only geometry to the pinned CGWindowID. Never use window titles
        // or silently substitute the app's focused window after attachment.
        for candidate in windows {
            AXUIElementSetMessagingTimeout(candidate, 0.02)
            guard let frame = geometry(of: candidate),
                  abs(frame.minX - referenceFrame.minX) < 2,
                  abs(frame.minY - referenceFrame.minY) < 2,
                  abs(frame.width - referenceFrame.width) < 2,
                  abs(frame.height - referenceFrame.height) < 2 else { continue }
            window = candidate
            return frame
        }
        return nil
    }

    private func geometry(of window: AXUIElement) -> CGRect? {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(
            window, [kAXPositionAttribute, kAXSizeAttribute] as CFArray, [], &values
        ) == .success, let attributes = values as? [AXValue], attributes.count == 2,
              AXValueGetType(attributes[0]) == .cgPoint, AXValueGetType(attributes[1]) == .cgSize else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(attributes[0], .cgPoint, &point),
              AXValueGetValue(attributes[1], .cgSize, &size),
              point.x.isFinite, point.y.isFinite, size.width > 40, size.height > 40 else { return nil }
        return CGRect(x: point.x, y: desktopTop - point.y - size.height, width: size.width, height: size.height)
    }
}
