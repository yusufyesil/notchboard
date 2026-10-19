import AppKit

/// `Notchboard --demo`: sample projects, chats and routines instead of your Claude
/// data, and the island opening and closing on its own. For screenshots and the
/// README recording. Run it from the build folder (`.build/release/Notchboard --demo`)
/// so its settings stay apart from the installed app's.
enum Demo {
    static let isOn = CommandLine.arguments.contains("--demo")

    static let work = Profile(slug: "work", name: "Claude Work", dataDir: URL(fileURLWithPath: "/dev/null"),
                              app: Profile.main.app, rgb: [93, 202, 165])

    /// Project folders with a logo each, so the logos are found the usual way.
    private static let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchboard-demo")
    private static func path(_ project: String) -> String { root.appendingPathComponent(project).path }

    static func data(now: Date = Date()) -> (profiles: [Profile], routines: [Routine], chats: [Chat]) {
        writeLogos()
        let cal = Calendar.current
        func today(_ h: Int, _ m: Int, days: Int = 0) -> Date {
            cal.date(byAdding: .day, value: days, to: cal.date(bySettingHour: h, minute: m, second: 0, of: now)!)!
        }
        func routine(_ id: String, _ title: String, _ project: String, _ state: RunState, last: Date, next: Date,
                     detail: String?, profile: Profile = .main) -> Routine {
            Routine(id: id, title: title, project: project, enabled: true, nextRun: next, lastStart: last,
                    lastEnd: last.addingTimeInterval(120), state: state, detail: detail,
                    runKey: "\(id)-\(last.timeIntervalSince1970)-\(state)", profile: profile,
                    sessionId: nil, projectPath: path(project))
        }
        func chat(_ id: String, _ title: String, _ project: String, _ state: RunState, ago: Double,
                  unread: Bool, detail: String? = nil, profile: Profile = .main) -> Chat {
            Chat(id: id, title: title, project: project, lastActivity: now.addingTimeInterval(-ago), state: state,
                 detail: detail, unread: unread, profile: profile, projectPath: path(project))
        }
        let routines = [
            routine("nightly", "Nightly analytics report", "data-pipeline", .failed, last: today(3, 0),
                    next: today(3, 0, days: 1), detail: "Warehouse connection timed out"),
            routine("sync", "Hourly metrics sync", "data-pipeline", .ok, last: now.addingTimeInterval(-37 * 60),
                    next: now.addingTimeInterval(23 * 60), detail: "Synced 48 tables."),
            routine("deps", "Weekly dependency check", "acme-web", .ok, last: today(8, 0, days: -2),
                    next: today(8, 0, days: 5), detail: "3 minor updates, all tests pass."),
            routine("crash", "Daily crash digest", "mobile-app", .ok, last: today(18, 0, days: -1),
                    next: today(18, 0), detail: "No new crashes.", profile: work),
        ]
        let chats = [
            chat("c1", "Add dark mode to settings", "acme-web", .running, ago: 5, unread: false),
            chat("c2", "Fix flaky checkout test", "acme-web", .ok, ago: 4 * 60, unread: true,
                 detail: "All 312 tests pass.", profile: work),
            chat("c3", "Update App Store screenshots", "mobile-app", .ok, ago: 2 * 3600, unread: false),
            chat("c4", "Write release notes for 3.2", "mobile-app", .ok, ago: 5 * 3600, unread: false),
        ]
        return ([.main, work], routines, chats)
    }

    // MARK: logos

    private static var wroteLogos = false

    private static func writeLogos() {
        guard !wroteLogos else { return }
        wroteLogos = true
        let logos: [(String, NSColor, NSColor, (NSRect) -> Void)] = [
            ("acme-web", NSColor(red: 0.31, green: 0.56, blue: 0.97, alpha: 1), NSColor(red: 0.13, green: 0.76, blue: 0.84, alpha: 1), { r in
                let p = NSBezierPath()
                p.move(to: NSPoint(x: r.width * 0.2, y: r.height * 0.24))
                p.line(to: NSPoint(x: r.width * 0.5, y: r.height * 0.78))
                p.line(to: NSPoint(x: r.width * 0.8, y: r.height * 0.24))
                p.close()
                NSColor.white.setFill(); p.fill()
                let cut = NSBezierPath()
                cut.move(to: NSPoint(x: r.width * 0.37, y: r.height * 0.24))
                cut.line(to: NSPoint(x: r.width * 0.5, y: r.height * 0.47))
                cut.line(to: NSPoint(x: r.width * 0.63, y: r.height * 0.24))
                cut.close()
                NSColor(red: 0.23, green: 0.65, blue: 0.9, alpha: 1).setFill(); cut.fill()
            }),
            ("data-pipeline", NSColor(red: 1, green: 0.7, blue: 0.28, alpha: 1), NSColor(red: 0.91, green: 0.4, blue: 0.24, alpha: 1), { r in
                for (x, y, w, a) in [(0.2, 0.63, 0.6, 1.0), (0.34, 0.43, 0.46, 0.8), (0.2, 0.23, 0.6, 1.0)] {
                    NSColor.white.withAlphaComponent(a).setFill()
                    NSBezierPath(roundedRect: NSRect(x: r.width * x, y: r.height * y, width: r.width * w, height: r.height * 0.13),
                                 xRadius: r.width * 0.065, yRadius: r.width * 0.065).fill()
                }
            }),
            ("mobile-app", NSColor(red: 0.2, green: 0.83, blue: 0.6, alpha: 1), NSColor(red: 0.05, green: 0.62, blue: 0.43, alpha: 1), { r in
                let phone = NSBezierPath(roundedRect: NSRect(x: r.width * 0.32, y: r.height * 0.2, width: r.width * 0.36, height: r.height * 0.6),
                                         xRadius: r.width * 0.08, yRadius: r.width * 0.08)
                phone.lineWidth = r.width * 0.08
                NSColor.white.setStroke(); phone.stroke()
                NSColor.white.setFill()
                NSBezierPath(ovalIn: NSRect(x: r.width * 0.455, y: r.height * 0.265, width: r.width * 0.09, height: r.width * 0.09)).fill()
            }),
        ]
        for (name, top, bottom, mark) in logos {
            let size = NSSize(width: 256, height: 256)
            let image = NSImage(size: size, flipped: false) { r in
                NSGradient(starting: top, ending: bottom)?.draw(in: NSBezierPath(rect: r), angle: -45)
                mark(r)
                return true
            }
            guard let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            let dir = root.appendingPathComponent(name)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? png.write(to: dir.appendingPathComponent("logo.png"))
        }
    }
}
