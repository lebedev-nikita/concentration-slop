import AVKit
import SwiftUI

private final class DraggablePlayerView: AVPlayerView {
    var togglePlayback: (() -> Void)?
    var pointerEntered: (() -> Void)?
    private var dragFrame: NSRect?
    private var dragPointer: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        pointerEntered?()
        if event.clickCount == 2 {
            dragFrame = nil
            dragPointer = nil
            togglePlayback?()
        } else if let window {
            dragFrame = window.frame
            dragPointer = window.convertPoint(toScreen: event.locationInWindow)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let frame = dragFrame, let pointer = dragPointer else { return }
        let current = window.convertPoint(toScreen: event.locationInWindow)
        let moved = NSRect(x: frame.minX + current.x - pointer.x, y: frame.minY + current.y - pointer.y,
                           width: frame.width, height: frame.height)
        if let panel = window as? FloatingPanel {
            panel.updateFromUser(frame: moved, resized: false)
        } else { window.setFrameOrigin(moved.origin) }
    }

    override func mouseUp(with event: NSEvent) {
        dragFrame = nil
        dragPointer = nil
        window?.saveFrame(usingName: "FloatingVideoWindow")
        (window as? FloatingPanel)?.userInteractionEnded?()
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
}

struct NativePlayerView: NSViewRepresentable {
    let player: AVQueuePlayer
    let menu: NSMenu
    let togglePlayback: () -> Void
    let pointerEntered: () -> Void

    func makeNSView(context: Context) -> AVPlayerView {
        let view = DraggablePlayerView()
        view.player = player
        view.controlsStyle = .none
        view.allowsVideoFrameAnalysis = false
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.videoGravity = .resizeAspect
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel("Геймплей. Наведение — меню; перетаскивание — перемещение; двойной щелчок — пауза.")
        view.menu = menu
        view.togglePlayback = togglePlayback
        view.pointerEntered = pointerEntered
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}
}

struct PlayerView: View {
    @ObservedObject var model: PlaybackModel
    @ObservedObject var interaction: PanelInteraction
    let menu: NSMenu
    let editLink: () -> Void
    let availableApplications: () -> [WorkApplication]
    let selectedApplication: () -> WorkApplication?
    let bindApplication: (WorkApplication?) -> Void
    let hide: () -> Void
    @State private var resizing = false
    @State private var applications: [WorkApplication] = []
    @State private var boundApplication: WorkApplication?

    var body: some View {
        ZStack {
            if model.hasVideo {
                NativePlayerView(player: model.player, menu: menu, togglePlayback: model.togglePlayback, pointerEntered: { interaction.isHovered = true })
                    .background(.black)
                    .accessibilityLabel("Геймплей. Наведение — меню; перетаскивание — перемещение; двойной щелчок — пауза.")
            } else {
                VStack(spacing: 12) {
                    Text("Геймплей рядом").font(.title2.weight(.semibold))
                    Text("Видео поверх работы.\nНаведите мышь для управления.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Вставить ссылку YouTube", action: editLink)
                        .buttonStyle(.borderedProminent)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            if model.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Открываем видео…").font(.callout)
                    Button("Отменить") { model.cancelLoading() }
                }
                .padding(24)
                .background(.regularMaterial)
            } else if let error = model.errorMessage {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error).font(.callout).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Повторить") { model.openLink() }
                        Button("Другая ссылка", action: editLink)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            hoverMenu
                .padding(6)
                .opacity(interaction.isHovered || resizing ? 1 : 0)
                .allowsHitTesting(interaction.isHovered || resizing)
                .accessibilityHidden(!interaction.isHovered && !resizing)
        }
        .overlay {
            ZStack {
                ForEach(VideoCorner.allCases, id: \.self) { corner in
                    ResizeCorner(corner: corner) { resizing = $0 }
                        .frame(width: 24, height: 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: interaction.isHovered) { _, inside in
            if inside {
                applications = availableApplications()
                boundApplication = selectedApplication()
            }
        }
    }

    private var hoverMenu: some View {
        HStack(spacing: 2) {
            Button(action: model.togglePlayback) {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill").frame(width: 24, height: 28)
            }
            .help(model.isPaused ? "Продолжить" : "Пауза")
            .accessibilityLabel(model.isPaused ? "Продолжить" : "Пауза")
            .disabled(!model.hasVideo || model.isLoading)
            Button(action: editLink) {
                Image(systemName: "link").frame(width: 24, height: 28)
            }
            .help("Открыть ссылку YouTube")
            .accessibilityLabel("Открыть ссылку YouTube")
            Menu {
                Button("Все приложения") { bindApplication(nil); boundApplication = nil }
                Divider()
                ForEach(applications, id: \.bundleID) { application in
                    Button {
                        bindApplication(application)
                        boundApplication = application
                    } label: {
                        if boundApplication == application {
                            Label(application.name, systemImage: "checkmark")
                        } else { Text(application.name) }
                    }
                }
                if let boundApplication, !applications.contains(boundApplication) {
                    Text("\(boundApplication.name) (не запущено)")
                }
            } label: {
                Image(systemName: boundApplication == nil ? "app.dashed" : "app.badge.checkmark")
                    .frame(width: 24, height: 28)
            }
            .help(boundApplication.map { "Привязка: \($0.name)" } ?? "Привязать к приложению")
            .accessibilityLabel("Привязать к приложению")
            Button(action: hide) {
                Image(systemName: "xmark").frame(width: 24, height: 28)
            }
            .help("Скрыть окно")
            .accessibilityLabel("Скрыть окно")
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 5)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct LinkEditor: View {
    @ObservedObject var model: PlaybackModel
    let dismiss: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Видео с YouTube").font(.headline)
            TextField("https://www.youtube.com/watch?v=…", text: $model.linkText)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(submit)
                .accessibilityLabel("Ссылка на видео YouTube")
            Text("Обычная ссылка, youtu.be или Shorts.")
                .font(.caption).foregroundStyle(.secondary)
            Text(model.errorMessage ?? "")
                .font(.callout)
                .frame(height: 64, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Найти Subway Surfers") {
                    NSWorkspace.shared.open(URL(string: "https://www.youtube.com/results?search_query=subway+surfers+gameplay+no+commentary")!)
                }
                Spacer()
                Button("Открыть", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { focused = true }
    }

    private func submit() {
        if model.openLink() { dismiss() }
    }
}
