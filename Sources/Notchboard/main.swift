import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets a click on the inactive panel press a button right away.
final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private let model = NotchModel()
    private var panel: NotchPanel!
    private var collapseWork: DispatchWorkItem?
    private var hoveredSince: Date?
    private lazy var setup = SetupWindow(store: store)
    private var bannerWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ note: Notification) {
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false

        let root = NotchView(store: store, model: model) { [weak self] inside in self?.hover(inside) }
        let host = FirstMouseHostingView(rootView: root)
        host.menu = makeMenu()
        panel.contentView = host

        Notifier.shared.start()
        // `defaults write app.notchboard startTab routines` opens on that tab.
        if UserDefaults.standard.string(forKey: "startTab") == "routines" { model.tab = .routines }
        store.start()
        place()
        panel.orderFrontRegardless()

        if !UserDefaults.standard.bool(forKey: "setupShown") {
            UserDefaults.standard.set(true, forKey: "setupShown")
            setup.show()
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.place() }
        }
        Task { @MainActor in
            for await change in store.$lastChange.values {
                if let change { self.announce(change) }
            }
        }
    }

    /// The screen with a notch if one is connected, else the main screen.
    private var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func place() {
        let s = screen
        if s.safeAreaInsets.top > 0,
           let left = s.auxiliaryTopLeftArea, let right = s.auxiliaryTopRightArea {
            model.notchWidth = s.frame.width - left.width - right.width
            model.barHeight = s.safeAreaInsets.top
        } else {
            model.notchWidth = 0
            model.barHeight = max(24, s.frame.maxY - s.visibleFrame.maxY)
        }
        let size = model.expanded
            ? CGSize(width: NotchView.expandedWidth + 40, height: 720)
            : CGSize(width: model.notchWidth + NotchView.sideWidth * 2, height: model.barHeight)
        panel.setFrame(CGRect(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    private func hover(_ inside: Bool) {
        collapseWork?.cancel()
        if inside {
            if hoveredSince == nil { hoveredSince = Date() }
            guard !model.expanded else { return }
            model.expanded = true
            place()
        } else {
            let work = DispatchWorkItem { [weak self] in self?.collapse() }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }

    private func collapse() {
        guard model.expanded else { return }
        // A look of a second or more counts as having seen what is there.
        if let since = hoveredSince, Date().timeIntervalSince(since) > 1.2 { store.markViewed() }
        hoveredSince = nil
        model.expanded = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.model.expanded else { return }
            self.place()
        }
    }

    /// Opens the list for a few seconds when a run starts, ends or fails.
    private func announce(_ change: Change) {
        store.clearChange()
        Notifier.shared.post(change)
        guard !model.expanded else { return }
        model.tab = change.isChat ? .chats : .routines
        model.expanded = true
        place()
        bannerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.collapse()
        }
        bannerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private func makeMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: String(localized: "Refresh now"), action: #selector(refreshNow), keyEquivalent: "").target = self
        m.addItem(withTitle: String(localized: "Open Claude"), action: #selector(openClaude), keyEquivalent: "").target = self
        m.addItem(withTitle: String(localized: "Permissions and settings…"), action: #selector(openSetup), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: String(localized: "Quit"), action: #selector(quit), keyEquivalent: "").target = self
        return m
    }

    @objc private func refreshNow() { store.refresh() }
    @objc private func openClaude() { Profile.main.open() }
    @objc private func openSetup() { setup.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}

// `Notchboard --find-icon <folder>…` prints the logo each project folder would get.
if CommandLine.arguments.dropFirst().first == "--find-icon" {
    for folder in CommandLine.arguments.dropFirst(2) {
        print(folder, "→", Logos.findIcon(in: URL(fileURLWithPath: folder))?.path ?? "(initial)")
    }
    exit(0)
}

MainActor.assumeIsolated {
    // `Notchboard --states` prints what the island would show, for checking the readers.
    if CommandLine.arguments.dropFirst().first == "--states" {
        let store = Store()
        store.refresh()
        for c in store.chats.prefix(8) {
            print("chat   ", c.state, c.unread ? "unread" : "read", c.profile.short, "·", c.title)
        }
        for r in store.routines { print("routine", r.state, r.profile.short, "·", r.title) }
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
