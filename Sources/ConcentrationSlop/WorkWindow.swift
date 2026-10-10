import AppKit
import CoreGraphics

struct WorkWindow: Equatable, Sendable {
    let id: CGWindowID
    let frame: CGRect
}

struct WorkWindowSnapshot: Sendable {
    /// Front-to-back visible windows from the selected process only.
    let visible: [WorkWindow]
    /// Whether an already attached window still exists, even when off-Space/minimized.
    let attachedWindowExists: Bool
}

/// Supplies window identity and Space visibility. Its geometry is for initial
/// AX matching only; compositor coordinates must never drive the video panel.
@MainActor
enum WorkWindowServer {
    static func snapshot(pid: pid_t, attachedID: CGWindowID?) -> WorkWindowSnapshot {
        let top = NSScreen.screens.first?.frame.maxY ?? CGDisplayBounds(CGMainDisplayID()).height
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let visible = info.compactMap { item -> WorkWindow? in
            guard (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (item[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let id = (item[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = item[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.width > 40, rect.height > 40,
                  ((item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0 else { return nil }
            return WorkWindow(id: id, frame: CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height))
        }
        let exists: Bool
        if let attachedID, !visible.contains(where: { $0.id == attachedID }) {
            let attached = CGWindowListCopyWindowInfo(.optionIncludingWindow, attachedID) as? [[String: Any]] ?? []
            exists = attached.contains {
                ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == attachedID
                && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
            }
        } else { exists = attachedID != nil }
        return WorkWindowSnapshot(visible: visible, attachedWindowExists: exists)
    }
}

struct WorkWindowAttachment {
    private(set) var windowID: CGWindowID?
    private var processID: pid_t?

    mutating func reset() { windowID = nil; processID = nil }

    mutating func resolve(pid: pid_t, snapshot: WorkWindowSnapshot) -> WorkWindow? {
        if processID != pid { windowID = nil; processID = pid }
        if let windowID {
            if let window = snapshot.visible.first(where: { $0.id == windowID }) { return window }
            // An off-Space/minimized window must not be replaced with another window
            // of the same app on the destination desktop.
            if snapshot.attachedWindowExists { return nil }
        }
        let window = snapshot.visible.first
        windowID = window?.id
        return window
    }
}

struct VideoPlacement: Equatable, Sendable {
    private(set) var x: CGFloat
    private(set) var y: CGFloat
    private(set) var fromRight = true
    private(set) var fromTop = false
    var preferredWidth: CGFloat

    init(video: CGRect, host: CGRect) {
        x = 0
        y = 0
        preferredWidth = video.width
        capture(video: video, host: host, resized: false)
    }

    init?(saved: [String: Double]) {
        guard saved["version"] == 2,
              let x = saved["x"], let y = saved["y"], let width = saved["width"],
              x.isFinite, y.isFinite, width.isFinite, x >= 0, y >= 0, width > 0,
              let right = saved["right"], let top = saved["top"],
              [0.0, 1.0].contains(right), [0.0, 1.0].contains(top) else { return nil }
        self.x = x
        self.y = y
        fromRight = right == 1
        fromTop = top == 1
        preferredWidth = width
    }

    init?(legacySaved saved: [String: Double], host: CGRect, aspectRatio: CGFloat) {
        guard saved["version"] == nil,
              let x = saved["x"], let y = saved["y"], let width = saved["width"],
              x.isFinite, y.isFinite, width.isFinite, (0...1).contains(x), (0...1).contains(y), width > 0 else { return nil }
        let bounds = Self.bounds(in: host)
        let fittedWidth = min(width, bounds.width, bounds.height * aspectRatio)
        let height = fittedWidth / aspectRatio
        self.init(video: CGRect(x: bounds.minX + x * (bounds.width - fittedWidth),
                                y: bounds.minY + y * (bounds.height - height),
                                width: fittedWidth, height: height), host: host)
        preferredWidth = width
    }

    var saved: [String: Double] {
        ["version": 2, "x": x, "y": y, "width": preferredWidth,
         "right": fromRight ? 1 : 0, "top": fromTop ? 1 : 0]
    }

    static func bounds(in host: CGRect) -> CGRect {
        let margin = min(12, min(host.width, host.height) / 10)
        return host.insetBy(dx: margin, dy: margin)
    }

    mutating func capture(video: CGRect, host: CGRect, resized: Bool) {
        let bounds = Self.bounds(in: host)
        if resized { preferredWidth = video.width }
        // Capture only explicit user changes. Automatic host fitting must retain
        // the desired insets and size even while temporarily constrained.
        let fitted = Self.constrain(video, to: bounds)
        fromRight = fitted.midX >= bounds.midX
        fromTop = fitted.midY >= bounds.midY
        x = max(0, fromRight ? bounds.maxX - fitted.maxX : fitted.minX - bounds.minX)
        y = max(0, fromTop ? bounds.maxY - fitted.maxY : fitted.minY - bounds.minY)
    }

    func frame(in host: CGRect, aspectRatio: CGFloat) -> CGRect {
        let bounds = Self.bounds(in: host)
        let width = min(preferredWidth, bounds.width, bounds.height * aspectRatio)
        let height = width / aspectRatio
        let frame = CGRect(x: fromRight ? bounds.maxX - width - x : bounds.minX + x,
                           y: fromTop ? bounds.maxY - height - y : bounds.minY + y,
                           width: width, height: height)
        return Self.constrain(frame, to: bounds)
    }

    static func constrain(_ video: CGRect, to bounds: CGRect) -> CGRect {
        let ratio = video.width / video.height
        let width = min(video.width, bounds.width, bounds.height * ratio)
        let height = width / ratio
        return CGRect(x: min(max(video.minX, bounds.minX), bounds.maxX - width),
                      y: min(max(video.minY, bounds.minY), bounds.maxY - height), width: width, height: height)
    }
}
