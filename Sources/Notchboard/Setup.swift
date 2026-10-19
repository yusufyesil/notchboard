import AppKit
import SwiftUI
import UserNotifications

/// macOS notifications for unread replies and routine runs.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private let center = UNUserNotificationCenter.current()

    func start() { center.delegate = self }

    func status() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func request() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func post(_ change: Change) {
        Task {
            guard await status() == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = change.title
            content.body = change.body
            content.sound = .default
            content.userInfo = ["app": change.app.path]
            if let file = await Logos.shared.attachmentFile(for: change.projectPath),
               let attachment = try? UNNotificationAttachment(identifier: "logo", url: file) {
                content.attachments = [attachment]
            }
            try? await center.add(UNNotificationRequest(identifier: change.key, content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let app = response.notification.request.content.userInfo["app"] as? String ?? Profile.main.app.path
        await MainActor.run { (Profiles.discover().first { $0.app.path == app } ?? .main).open() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Login start through a LaunchAgent, as build.sh first set it up.
enum LoginItem {
    static let label = "app.notchboard"
    static var plist: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var isOn: Bool { FileManager.default.fileExists(atPath: plist.path) }

    /// Takes effect at the next login; the running copy is left alone.
    static func set(_ on: Bool) {
        if !on { try? FileManager.default.removeItem(at: plist); return }
        let exe = Bundle.main.executablePath ?? ""
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>Label</key><string>\(label)</string>
          <key>ProgramArguments</key><array><string>\(exe)</string></array>
          <key>RunAtLoad</key><true/>
          <key>ProcessType</key><string>Interactive</string>
        </dict></plist>
        """
        try? xml.write(to: plist, atomically: true, encoding: .utf8)
    }
}

/// Automation permission for Claude: what lets a click open a chat in the right profile.
enum Automation {
    enum State { case granted, denied, notAsked, claudeNotRunning }

    static func check(ask: Bool) -> State {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.anthropic.claudefordesktop")
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(kInternetEventClass),
                                                           AEEventID(kAEGetURL), ask)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .claudeNotRunning
        default: return .notAsked
        }
    }
}

@MainActor
final class SetupModel: ObservableObject {
    @Published var notifications: UNAuthorizationStatus = .notDetermined
    @Published var loginItem = LoginItem.isOn
    @Published var automation: Automation.State = .notAsked
    let store: Store

    init(store: Store) { self.store = store }

    var canReadClaude: Bool { !store.routines.isEmpty || !store.chats.isEmpty }

    func reload() async {
        notifications = await Notifier.shared.status()
        loginItem = LoginItem.isOn
        automation = Automation.check(ask: false)
    }
}

struct SetupView: View {
    @ObservedObject var model: SetupModel
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notchboard").font(.system(size: 18, weight: .semibold))
                Text("Notchboard shows your Claude Desktop chats and routines. To work fully, it needs the following.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            row(ok: model.canReadClaude, title: String(localized: "Read Claude data"),
                detail: model.canReadClaude
                    ? String(localized: "Reading \(model.store.chats.count) chats and \(model.store.routines.count) routines.")
                    : String(localized: "Couldn’t read the Claude Desktop folder. Full Disk Access may be needed.")) {
                if !model.canReadClaude {
                    Button("Open Settings") {
                        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
                    }
                }
            }
            row(ok: model.notifications == .authorized, title: String(localized: "Notifications"),
                detail: String(localized: "Tells you when a new reply arrives, when a chat is waiting for you, or when a routine finishes or fails.")) {
                switch model.notifications {
                case .authorized: EmptyView()
                case .notDetermined:
                    Button("Allow") {
                        Task { _ = await Notifier.shared.request(); await model.reload() }
                    }
                default:
                    Button("Open Settings") {
                        open("x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")")
                    }
                }
            }
            row(ok: model.automation == .granted, title: String(localized: "Open chats"),
                detail: String(localized: "Clicking a row opens that chat in the right Claude profile. macOS asks for this as permission to control Claude.")) {
                switch model.automation {
                case .granted: EmptyView()
                case .denied:
                    Button("Open Settings") {
                        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
                    }
                case .claudeNotRunning: Text("Claude is not running").font(.system(size: 11)).foregroundStyle(.secondary)
                case .notAsked:
                    Button("Allow") {
                        Task.detached { _ = Automation.check(ask: true); await model.reload() }
                    }
                }
            }
            row(ok: model.loginItem, title: String(localized: "Open at login"), detail: String(localized: "The notch comes up on its own when your Mac starts.")) {
                Toggle("", isOn: Binding(get: { model.loginItem },
                                          set: { LoginItem.set($0); model.loginItem = $0 }))
                    .toggleStyle(.switch).labelsHidden()
            }
            HStack {
                Spacer()
                Button("OK", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
        .task {
            await model.reload()
            // Settings changed in System Settings show up when you come back.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await model.reload()
            }
        }
    }

    private func row<A: View>(ok: Bool, title: String, detail: String, @ViewBuilder action: () -> A) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange).font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            action()
        }
    }

    private func open(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }
}

@MainActor
final class SetupWindow {
    private var window: NSWindow?
    private let model: SetupModel

    init(store: Store) { model = SetupModel(store: store) }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Notchboard"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SetupView(model: model) { [weak self] in self?.window?.close() })
            w.center()
            window = w
        }
        // Started by launchd, the app is never frontmost: float the window and take focus.
        window?.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
