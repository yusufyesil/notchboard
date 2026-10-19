import AppKit
import SwiftUI

/// One Claude Desktop data folder: the default app, or a Claude Profiles clone.
struct Profile: Equatable, Hashable {
    let slug: String       // "" for the default app
    let name: String       // "Claude Work"
    let dataDir: URL
    let app: URL
    let rgb: [Double]

    var isMain: Bool { slug.isEmpty }
    /// The badge text: "Work" for "Claude Work", "Main" for the default app.
    var short: String {
        if isMain { return String(localized: "Main") }
        let trimmed = name.hasPrefix("Claude ") ? String(name.dropFirst(7)) : name
        return trimmed.isEmpty ? slug : trimmed
    }
    var color: Color { Color(red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255) }

    static let main = Profile(
        slug: "", name: "Claude",
        dataDir: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude"),
        app: URL(fileURLWithPath: "/Applications/Claude.app"),
        rgb: [110, 106, 98])

    /// Brings this profile's running Claude forward; starts it only when none runs.
    /// (A clone's launcher always starts a new instance with `open -n`, and opening
    /// Claude.app may raise a clone instead of the default app.)
    func open() {
        if let pid = runningPid(), let running = NSRunningApplication(processIdentifier: pid) {
            running.unhide()
            running.activate(options: [.activateAllWindows])
            return
        }
        if isMain {
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: app, configuration: config)
        } else {
            NSWorkspace.shared.open(app)
        }
    }

    /// Opens one Code session in this profile's own Claude window. The link goes
    /// to that process as an Apple Event: opened as a URL, macOS would hand it to
    /// whichever Claude instance it picks, often not this profile's.
    func open(session id: String) {
        guard let pid = runningPid(),
              let url = "claude://code/continue?session=\(id)&source=desktop_action"
                  .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { open(); return }
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: url), forKeyword: keyDirectObject)
        _ = try? event.sendEvent(options: [.noReply], timeout: 5)
        open()
    }

    /// The main Claude process for this data folder, matched the way Claude
    /// Profiles' engine.sh does: `--user-data-dir=<dir>` as a whole argument,
    /// and for the default app, no such argument at all.
    private func runningPid() -> pid_t? {
        let claudes = NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop")
        for app in claudes {
            let args = Self.arguments(of: app.processIdentifier)
            let dirArg = args.first { $0.hasPrefix("--user-data-dir=") }
            if isMain ? dirArg == nil : dirArg == "--user-data-dir=\(dataDir.path)" { return app.processIdentifier }
        }
        return nil
    }

    /// A process's argv, read with sysctl KERN_PROCARGS2.
    private static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > 4 else { return [] }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = 4
        while i < size && buf[i] != 0 { i += 1 }   // executable path
        while i < size && buf[i] == 0 { i += 1 }   // padding
        var args: [String] = []
        while i < size && args.count < argc {
            let start = i
            while i < size && buf[i] != 0 { i += 1 }
            args.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }
}

/// Finds Claude Profiles clones the way its engine.sh lays them out:
/// data in ~/.claude-instances/<slug>, the launcher in ~/Applications with
/// bundle id local.claude-profiles.<slug>, the Dock badge colour by slug.
enum Profiles {
    private static var colorCache: [String: [Double]] = [:]
    private static let fm = FileManager.default
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    static func discover() -> [Profile] {
        var out = [Profile.main]
        let root = home.appendingPathComponent(".claude-instances")
        let slugs = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .filter { fm.fileExists(atPath: root.appendingPathComponent("\($0)/claude-code-sessions").path) }
            .sorted()
        let launchers = launchersBySlug()
        for slug in slugs {
            let launcher = launchers[slug]
            out.append(Profile(
                slug: slug,
                name: launcher?.name ?? "Claude \(slug)",
                dataDir: root.appendingPathComponent(slug),
                app: launcher?.url ?? Profile.main.app,
                rgb: color(for: slug)))
        }
        return out
    }

    private static func launchersBySlug() -> [String: (name: String, url: URL)] {
        var out: [String: (String, URL)] = [:]
        let apps = home.appendingPathComponent("Applications")
        for name in (try? fm.contentsOfDirectory(atPath: apps.path)) ?? [] where name.hasSuffix(".app") {
            let url = apps.appendingPathComponent(name)
            guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
                  let id = info["CFBundleIdentifier"] as? String,
                  id.hasPrefix("local.claude-profiles.") else { continue }
            let slug = String(id.dropFirst("local.claude-profiles.".count))
            out[slug] = (info["CFBundleDisplayName"] as? String ?? String(name.dropLast(4)), url)
        }
        return out
    }

    /// engine.sh: the user's pick in .runtime/badges, else `cksum` of the slug mod 6.
    private static func color(for slug: String) -> [Double] {
        if let c = colorCache[slug] { return c }
        let palette: [[Double]] = [[59, 125, 216], [93, 202, 165], [224, 165, 94],
                                   [124, 92, 196], [210, 95, 140], [76, 169, 178]]
        var index: Int?
        let badges = home.appendingPathComponent(".claude-instances/.runtime/badges")
        if let text = try? String(contentsOf: badges, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: " ")
                if parts.count >= 2, parts[0] == slug, let i = Int(parts[1]), (0..<6).contains(i) { index = i }
            }
        }
        let c = palette[index ?? Int(cksum(slug) % 6)]
        colorCache[slug] = c
        return c
    }

    /// POSIX cksum (CRC-32/CKSUM over the bytes, then their length), as the shell prints it
    /// for `printf '%s' slug | cksum`.
    static func cksum(_ s: String) -> UInt32 {
        var crc: UInt32 = 0
        func feed(_ byte: UInt8) {
            crc ^= UInt32(byte) << 24
            for _ in 0..<8 { crc = crc & 0x8000_0000 != 0 ? (crc << 1) ^ 0x04C1_1DB7 : crc << 1 }
        }
        let bytes = Array(s.utf8)
        bytes.forEach(feed)
        var len = bytes.count
        while len > 0 { feed(UInt8(len & 0xFF)); len >>= 8 }
        return ~crc
    }
}
