import AppKit
@preconcurrency import ApplicationServices
import Combine
import SwiftUI

@main
struct ConcentrationSlopApplication {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = PlaybackModel()
    private let interaction = PanelInteraction()
    private var scope = ApplicationScope()
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var linkWindow: NSWindow?
    private var sizeObservation: AnyCancellable?
    private var windowAttachment = WorkWindowAttachment()
    private var hostWindow: WorkWindow?
    private var placement: VideoPlacement?
    private var windowMonitor: Timer?
    private let logicalWindowMonitor = LogicalWindowMonitor()
    private let ownBundleID = Bundle.main.bundleIdentifier ?? "com.concentrationslop.macos"

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.userFrameChanged = { [weak self] frame, resized in self?.applyUserFrame(frame, resized: resized) }
        panel.userInteractionEnded = { [weak self] in self?.savePlacement() }
        restorePlacement()
        panel.title = "Concentration Slop"
        panel.setAccessibilityRole(.window)
        panel.setAccessibilityTitle("Concentration Slop")
        panel.level = .floating
        panel.setApplicationBound(scope.application != nil)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.contentAspectRatio = NSSize(width: 16, height: 9)
        panel.contentMinSize = NSSize(width: 160, height: 90)
        panel.setFrameAutosaveName("FloatingVideoWindow")
        let contextMenu = controlMenu()
        let content = HoverHostingView(rootView: PlayerView(
            model: model, interaction: interaction, menu: contextMenu, editLink: { [weak self] in self?.editLink() },
            availableApplications: { [weak self] in self?.runningWorkApplications() ?? [] },
            selectedApplication: { [weak self] in self?.scope.application },
            bindApplication: { [weak self] in self?.bind(to: $0) },
            hide: { [weak self] in self?.hide() }
        ))
        content.interaction = interaction
        content.wantsLayer = true
        content.layer?.cornerRadius = 14
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        panel.contentView = content
        if !panel.setFrameUsingName("FloatingVideoWindow", force: true), let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 24, y: visible.minY + 24))
        }
        sizeObservation = model.$videoAspectRatio.sink { [weak self] ratio in
            guard let self else { return }
            self.panel.contentAspectRatio = NSSize(width: ratio, height: 1)
            self.panel.contentMinSize = NSSize(width: max(160, 90 * ratio), height: max(90, 160 / ratio))
            self.resize(toWidth: self.placement?.preferredWidth ?? self.panel.frame.width)
        }
        makeMenus()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelOcclusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification, object: panel
        )
        if scope.application != nil { requestWindowAccessIfNeeded() }
        updateVisibility()
        if !model.linkText.isEmpty { model.openLink() }
    }

    private func controlMenu() -> NSMenu {
        let menu = NSMenu(title: "Concentration Slop")
        menu.delegate = self
        menu.autoenablesItems = false
        return menu
    }

    private func makeMenus() {
        let appMenu = NSMenu()
        let root = NSMenuItem()
        root.submenu = controlMenu()
        appMenu.addItem(root)
        let editRoot = NSMenuItem(title: "Правка", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Правка")
        for (title, action, key) in [("Вырезать", "cut:", "x"), ("Копировать", "copy:", "c"), ("Вставить", "paste:", "v"), ("Выбрать всё", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editRoot.submenu = editMenu
        appMenu.addItem(editRoot)
        NSApplication.shared.mainMenu = appMenu

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "play.rectangle", accessibilityDescription: "Concentration Slop")
        statusItem.button?.toolTip = "Concentration Slop — видео и привязка к приложению"
        statusItem.menu = controlMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Открыть ссылку…", action: #selector(editLink), key: "o"))
        let playback = item(model.isPaused ? "Продолжить" : "Пауза", action: #selector(togglePlayback), key: "")
        playback.isEnabled = model.hasVideo && !model.isLoading
        menu.addItem(playback)
        menu.addItem(.separator())
        let binding = NSMenuItem(title: scope.application.map { "Привязка: \($0.name)" } ?? "Привязать к приложению", action: nil, keyEquivalent: "")
        binding.submenu = applicationMenu()
        menu.addItem(binding)
        if scope.application != nil, !AXIsProcessTrusted() {
            menu.addItem(item("Разрешить привязку к окну…", action: #selector(requestWindowAccess), key: ""))
        }
        menu.addItem(.separator())
        menu.addItem(item(scope.application.map { "Показать в \($0.name)" } ?? "Показать окно", action: #selector(show), key: ""))
        menu.addItem(item("Скрыть окно", action: #selector(hide), key: "w"))
        menu.addItem(.separator())
        menu.addItem(item("Выйти из Concentration Slop", action: #selector(quit), key: "q"))
    }

    private func applicationMenu() -> NSMenu {
        let menu = NSMenu()
        let all = item("Все приложения", action: #selector(bindApplication), key: "")
        all.state = scope.application == nil ? .on : .off
        menu.addItem(all)
        menu.addItem(.separator())
        var listedIDs = Set<String>()
        for app in runningWorkApplications() {
            let id = app.bundleID
            listedIDs.insert(id)
            let entry = item(app.name, action: #selector(bindApplication), key: "")
            entry.representedObject = id
            entry.state = scope.application?.bundleID == id ? .on : .off
            menu.addItem(entry)
        }
        if let bound = scope.application, !listedIDs.contains(bound.bundleID) {
            let entry = NSMenuItem(title: "\(bound.name) (не запущено)", action: nil, keyEquivalent: "")
            entry.state = .on
            menu.addItem(entry)
        }
        return menu
    }

    private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func runningWorkApplications() -> [WorkApplication] {
        var ids = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
                  id != ownBundleID, ids.insert(id).inserted else { return nil }
            return WorkApplication(bundleID: id, name: app.localizedName ?? id)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func bind(to application: WorkApplication?) {
        savePlacement()
        scope.bind(to: application)
        logicalWindowMonitor.stop()
        windowAttachment.reset()
        hostWindow = nil
        panel.attachmentBounds = nil
        restorePlacement()
        panel.setApplicationBound(scope.application != nil)
        if application != nil { requestWindowAccessIfNeeded() }
        updateVisibility()
    }

    @objc private func bindApplication(_ sender: NSMenuItem) {
        bind(to: (sender.representedObject as? String).map { WorkApplication(bundleID: $0, name: sender.title) })
    }

    @objc private func activeApplicationChanged(_ notification: Notification) { updateVisibility() }

    @objc private func activeSpaceChanged(_ notification: Notification) { updateVisibility() }

    @objc private func panelOcclusionChanged(_ notification: Notification) { synchronizePlaybackVisibility() }

    @objc private func refreshAttachedWindow(_ timer: Timer) { updateVisibility() }

    private func synchronizePlaybackVisibility() {
        model.setWindowVisible(
            panel.isVisible && panel.isOnActiveSpace && panel.occlusionState.contains(.visible)
            && scope.shouldShow(frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                boundWindowIsOnScreen: hostWindow != nil)
        )
    }

    private func updateVisibility() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let boundIsActive = scope.application?.bundleID == frontmost?.bundleIdentifier
        updateWindowMonitor(active: boundIsActive)
        if scope.application != nil, boundIsActive, let frontmost {
            let snapshot = WorkWindowServer.snapshot(pid: frontmost.processIdentifier, attachedID: windowAttachment.windowID)
            if let visibleWindow = windowAttachment.resolve(pid: frontmost.processIdentifier, snapshot: snapshot) {
                let top = NSScreen.screens.first?.frame.maxY ?? CGDisplayBounds(CGMainDisplayID()).height
                logicalWindowMonitor.follow(pid: frontmost.processIdentifier, window: visibleWindow, desktopTop: top) { [weak self] frame in
                    guard let self, self.windowAttachment.windowID == visibleWindow.id,
                          self.scope.application?.bundleID == NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
                    self.applyHostFrame(WorkWindow(id: visibleWindow.id, frame: frame))
                    self.presentPanelIfAllowed()
                }
                if let frame = logicalWindowMonitor.latestFrame {
                    applyHostFrame(WorkWindow(id: visibleWindow.id, frame: frame))
                } else { hostWindow = nil }
            } else {
                hostWindow = nil
                logicalWindowMonitor.stop()
            }
        } else {
            hostWindow = nil
            logicalWindowMonitor.stop()
        }
        presentPanelIfAllowed()
    }

    private func applyHostFrame(_ window: WorkWindow) {
        hostWindow = window
        if placement == nil {
            let saved = scope.application.flatMap {
                UserDefaults.standard.dictionary(forKey: "videoPlacement.\($0.bundleID)") as? [String: Double]
            }
            placement = saved.flatMap { VideoPlacement(legacySaved: $0, host: window.frame, aspectRatio: CGFloat(model.videoAspectRatio)) }
                ?? VideoPlacement(video: panel.frame, host: window.frame)
        }
        fitPanelToHost()
    }

    private func presentPanelIfAllowed() {
        let visible = scope.shouldShow(frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                       boundWindowIsOnScreen: hostWindow != nil)
        // Never order a bound panel onto a Space without its actual work window,
        // even if an activation notification still names the outgoing application.
        if visible {
            if !panel.isVisible {
                // Geometry callbacks can arrive between Space notifications.
                // Check current membership before ordering onto any desktop.
                if let id = windowAttachment.windowID, scope.application != nil,
                   let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                   !WorkWindowServer.snapshot(pid: pid, attachedID: id).visible.contains(where: { $0.id == id }) { return }
                panel.orderFrontRegardless()
            }
        } else {
            interaction.isHovered = false
            if panel.isVisible { panel.orderOut(nil) }
        }
        synchronizePlaybackVisibility()
    }

    private func updateWindowMonitor(active: Bool) {
        guard scope.application != nil else {
            windowMonitor?.invalidate()
            windowMonitor = nil
            return
        }
        let interval = active ? 0.1 : 0.2
        guard windowMonitor?.timeInterval != interval else { return }
        windowMonitor?.invalidate()
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(refreshAttachedWindow), userInfo: nil, repeats: true)
        timer.tolerance = active ? 0.01 : 0.04
        // Space visibility is separate from fast logical geometry tracking.
        RunLoop.main.add(timer, forMode: .common)
        windowMonitor = timer
    }

    private func restorePlacement() {
        placement = scope.application.flatMap {
            UserDefaults.standard.dictionary(forKey: "videoPlacement.\($0.bundleID)") as? [String: Double]
        }.flatMap(VideoPlacement.init(saved:))
    }

    private func savePlacement() {
        guard let application = scope.application, let placement else { return }
        UserDefaults.standard.set(placement.saved, forKey: "videoPlacement.\(application.bundleID)")
    }

    private func fitPanelToHost() {
        guard let hostWindow, let placement else { return }
        let ratio = CGFloat(model.videoAspectRatio)
        let bounds = VideoPlacement.bounds(in: hostWindow.frame)
        panel.attachmentBounds = bounds
        let minimumWidth = min(max(160, 90 * ratio), bounds.width, bounds.height * ratio)
        panel.contentMinSize = NSSize(width: minimumWidth, height: minimumWidth / ratio)
        let frame = placement.frame(in: hostWindow.frame, aspectRatio: ratio)
        guard !approximatelyEqual(panel.frame, frame) else { return }
        panel.setFrame(frame, display: true)
    }

    private func approximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5
        && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    private func applyUserFrame(_ frame: CGRect, resized: Bool) {
        let constrained = panel.attachmentBounds.map { VideoPlacement.constrain(frame, to: $0) } ?? frame
        panel.setFrame(constrained, display: true)
        if let hostWindow {
            placement?.capture(video: panel.frame, host: hostWindow.frame, resized: resized)
            fitPanelToHost()
        }
    }

    private func resize(toWidth width: CGFloat) {
        if scope.application != nil, let hostWindow {
            if placement == nil { placement = VideoPlacement(video: panel.frame, host: hostWindow.frame) }
            placement?.preferredWidth = width
            fitPanelToHost()
            return
        }
        let ratio = CGFloat(model.videoAspectRatio)
        panel.contentMinSize = NSSize(width: max(160, 90 * ratio), height: max(90, 160 / ratio))
        let screen = panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? panel.frame
        let width = min(max(width, panel.contentMinSize.width), visible.width, visible.height * ratio)
        let size = NSSize(width: width, height: width / ratio)
        let origin = NSPoint(
            x: max(visible.minX, min(panel.frame.minX, visible.maxX - size.width)),
            y: max(visible.minY, min(panel.frame.minY, visible.maxY - size.height))
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func requestWindowAccessIfNeeded() {
        guard !AXIsProcessTrusted(), !UserDefaults.standard.bool(forKey: "windowAccessPrompted") else { return }
        UserDefaults.standard.set(true, forKey: "windowAccessPrompted")
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    @objc private func requestWindowAccess() {
        guard !AXIsProcessTrusted() else { updateVisibility(); return }
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func togglePlayback() { model.togglePlayback() }

    @objc private func editLink() {
        if linkWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 250),
                styleMask: [.titled, .closable], backing: .buffered, defer: false
            )
            window.title = "Видео с YouTube"
            window.level = .floating
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: LinkEditor(model: model) { [weak self] in
                self?.linkWindow?.orderOut(nil)
            })
            window.center()
            linkWindow = window
        }
        NSApplication.shared.activate()
        linkWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func show() {
        scope.show()
        if let bound = scope.application,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bound.bundleID,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bound.bundleID).first {
            running.activate(options: [])
        }
        updateVisibility()
    }

    @objc private func hide() {
        scope.hide()
        updateVisibility()
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        windowMonitor?.invalidate()
        logicalWindowMonitor.stop()
        savePlacement()
        model.suspend()
    }
}
