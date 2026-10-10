import AppKit
import ApplicationServices
import Testing
@testable import ConcentrationSlop

@MainActor
struct LogicalWindowMonitorTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CONCENTRATION_SLOP_WINDOW_TEST"] == "1"))
    func followsLogicalResizeWithoutAddingSpaceTranslation() async throws {
        #expect(AXIsProcessTrusted(), "The optional native test needs Accessibility permission")
        _ = NSApplication.shared
        NSApplication.shared.finishLaunching()
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 640, height: 360),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        defer { window.close() }
        let top = try #require(NSScreen.screens.first?.frame.maxY)
        let monitor = LogicalWindowMonitor()
        defer { monitor.stop() }
        let id = CGWindowID(window.windowNumber)
        let pid = ProcessInfo.processInfo.processIdentifier
        monitor.follow(pid: pid, window: WorkWindow(id: id, frame: window.frame), desktopTop: top) { _ in }
        try await wait(until: { monitor.latestFrame == window.frame })
        let resized = CGRect(x: 120, y: 140, width: 510, height: 320)
        let started = ContinuousClock.now
        window.setFrame(resized, display: true)
        try await wait(until: { monitor.latestFrame == resized })
        let latency = started.duration(to: .now)
        print("Native geometry update latency: \(latency)")
        #expect(latency < .milliseconds(80), "Geometry must not wait for the slow Space-visibility poll")
        // Simulate WindowServer reporting the outgoing desktop animation.
        // Its translation must never become an additional panel translation.
        monitor.follow(pid: pid, window: WorkWindow(id: id, frame: resized.offsetBy(dx: -700, dy: 0)), desktopTop: top) { _ in }
        try await Task.sleep(for: .milliseconds(50))
        #expect(monitor.latestFrame == resized)
        monitor.stop()
        try await Task.sleep(for: .milliseconds(25))
        #expect(monitor.latestFrame == nil, "Late IPC callbacks must not revive a stopped attachment")
    }

    private func wait(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(1)
        while !condition(), ContinuousClock.now < deadline {
            pumpAppKit()
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }

    private func pumpAppKit() {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
    }
}
