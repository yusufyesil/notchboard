import CoreServices
import Foundation

enum RunState: Equatable {
    case none, running, ok, needsYou, failed, missed, unknown, unread

    var isProblem: Bool { self == .failed || self == .missed || self == .needsYou }
}

struct Routine: Identifiable, Equatable {
    let id: String
    var title: String
    var project: String
    var enabled: Bool
    var nextRun: Date?
    var lastStart: Date?
    var lastEnd: Date?
    var state: RunState
    var detail: String?  // error, question or one-line summary
    var runKey: String   // one run in one state: what an acknowledgement covers
    var profile: Profile = .main
    var sessionId: String?  // the last run's session
    var projectPath: String?
}

/// Something worth telling you about: a routine run that changed, an unread reply.
struct Change: Equatable {
    let id: String
    let key: String
    let isChat: Bool
    let announce: Bool
    let title: String
    let body: String
    var app: URL = Profile.main.app  // which Claude a click on the notification opens
    var projectPath: String?         // whose logo the notification shows
}

struct Chat: Identifiable, Equatable {
    let id: String
    var title: String
    var project: String
    var lastActivity: Date
    var state: RunState
    var detail: String?
    var unread: Bool  // a reply came after you last opened it
    var profile: Profile = .main
    var projectPath: String?

    var needsAttention: Bool { unread && (state == .needsYou || state == .failed) }
}

/// Reads Claude Desktop's scheduled tasks and sessions from its own files.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var routines: [Routine] = []
    @Published private(set) var chats: [Chat] = []
    @Published private(set) var lastChange: Change?
    @Published private(set) var checkedAt = Date()
    @Published private(set) var profiles: [Profile] = [.main]
    @Published private(set) var lastViewedAt: Date
    @Published private(set) var acked: Set<String>
    @Published private(set) var readMarks: [String: Double]

    private var seen: [String: String] = [:]
    private var timer: Timer?
    private var stream: FSEventStreamRef?
    private var refreshQueued = false
    private var lastRefresh = Date.distantPast
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let defaults = UserDefaults.standard

    static let chatWindow: TimeInterval = 24 * 3600
    static let runningWindow: TimeInterval = 90

    init() {
        lastViewedAt = defaults.object(forKey: "lastViewedAt") as? Date ?? Date()
        acked = Set(defaults.stringArray(forKey: "acked") ?? [])
        readMarks = defaults.dictionary(forKey: "readMarks") as? [String: Double] ?? [:]
    }

    /// Refreshes when Claude's files change, and every 15 seconds for what moves with
    /// the clock alone: countdowns, missed runs, a transcript gone quiet.
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        watch()
    }

    /// Desktop's session files and Claude Code's transcripts, watched with FSEvents.
    private func watch() {
        guard !Demo.isOn else { return }
        let paths = [Profile.main.dataDir, home.appendingPathComponent(".claude-instances"),
                     home.appendingPathComponent(".claude/projects")].map(\.path).filter { fm.fileExists(atPath: $0) }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info, let changed = unsafeBitCast(paths, to: NSArray.self) as? [String] else { return }
            // Electron's caches and logs change all the time; only sessions and transcripts matter.
            guard changed.contains(where: { $0.contains("-sessions/") || $0.contains("/.claude/projects/") }) else { return }
            let store = Unmanaged<Store>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { store.queueRefresh() }
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents))
        else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    /// At most one refresh a second: a working turn writes its transcript many times.
    private func queueRefresh() {
        guard !refreshQueued else { return }
        refreshQueued = true
        let wait = max(0, 1 - Date().timeIntervalSince(lastRefresh))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            self?.refreshQueued = false
            self?.refresh()
        }
    }

    // MARK: seen and acknowledged

    func isAcked(_ key: String) -> Bool { acked.contains(key) }

    func ack(_ key: String) {
        acked.insert(key)
        defaults.set(Array(acked.suffix(500)), forKey: "acked")
    }

    func ackAll() {
        for r in routines where r.state.isProblem { acked.insert(r.runKey) }
        defaults.set(Array(acked.suffix(500)), forKey: "acked")
        for c in chats where c.needsAttention { markRead(c.id) }
    }

    /// Read here, without opening it in Claude; opening it there counts too.
    func markRead(_ chatId: String) {
        readMarks[chatId] = Date().timeIntervalSince1970
        defaults.set(readMarks, forKey: "readMarks")
        if let i = chats.firstIndex(where: { $0.id == chatId }) { chats[i].unread = false }
    }

    func markViewed() {
        lastViewedAt = Date()
        defaults.set(lastViewedAt, forKey: "lastViewedAt")
    }

    func isNew(_ end: Date?) -> Bool { (end ?? .distantPast) > lastViewedAt }

    var openProblems: Int {
        routines.filter { $0.state.isProblem && !isAcked($0.runKey) }.count
            + chats.filter(\.needsAttention).count
    }

    var newSinceViewed: Int {
        routines.filter { $0.state != .running && $0.state != .missed && isNew($0.lastEnd) }.count
            + chats.filter { $0.unread && !$0.needsAttention }.count
    }

    var runningCount: Int {
        routines.filter { $0.state == .running }.count + chats.filter { $0.state == .running }.count
    }

    // MARK: reading

    func refresh() {
        lastRefresh = Date()
        if Demo.isOn {
            (profiles, routines, chats) = Demo.data()
            checkedAt = Date()
            return
        }
        var found: [String: Routine] = [:]
        var chatList: [Chat] = []
        profiles = Profiles.discover()
        indexTranscripts()
        for profile in profiles {
            // A clone's ids carry its slug; the default app's stay as they were.
            let tag = profile.isMain ? "" : "\(profile.slug)/"
            for root in ["claude-code-sessions", "local-agent-mode-sessions"] {
                for dir in accountDirs(under: profile.dataDir.appendingPathComponent(root)) {
                    let sessions = readSessions(in: dir)
                    chatList += sessions.compactMap(chat).map { var c = $0; c.profile = profile; return c }
                    for var r in readStore(dir, sessions: sessions) {
                        r = Routine(id: tag + r.id, title: r.title, project: r.project, enabled: r.enabled,
                                    nextRun: r.nextRun, lastStart: r.lastStart, lastEnd: r.lastEnd,
                                    state: r.state, detail: r.detail, runKey: tag + r.runKey, profile: profile,
                                    sessionId: r.sessionId, projectPath: r.projectPath)
                        if (found[r.id]?.lastStart ?? .distantPast) <= (r.lastStart ?? .distantPast) { found[r.id] = r }
                    }
                }
            }
        }

        // Running first, then what finished since you last looked, then the next to run.
        let list = found.values.filter(\.enabled).sorted {
            let a = ($0.state == .running ? 0 : isNew($0.lastEnd) ? 1 : 2, $0.nextRun ?? .distantFuture)
            let b = ($1.state == .running ? 0 : isNew($1.lastEnd) ? 1 : 2, $1.nextRun ?? .distantFuture)
            return a < b
        }
        // Running first, then unread, then the most recent; the tabs group by project in this order.
        chats = chatList.sorted {
            let a = ($0.state == .running ? 0 : $0.unread ? 1 : 2, -$0.lastActivity.timeIntervalSince1970)
            let b = ($1.state == .running ? 0 : $1.unread ? 1 : 2, -$1.lastActivity.timeIntervalSince1970)
            return a < b
        }
        // Routines announce every change; a chat when a reply arrives unread.
        var changes: [Change] = list.map { r in
            Change(id: r.id, key: r.runKey, isChat: false, announce: r.state != .none,
                   title: label(r.title, r.profile), body: [r.state.word.capitalized(with: Fmt.locale), r.detail].compactMap { $0 }.joined(separator: ": "), app: r.profile.app, projectPath: r.projectPath)
        }
        changes += chats.map { c in
            Change(id: c.id, key: "\(c.id)-\(c.lastActivity.timeIntervalSince1970)-\(c.state)", isChat: true, announce: c.unread,
                   title: label(c.title, c.profile), body: [c.state == .needsYou ? String(localized: "Waiting for your reply") : c.state == .failed ? String(localized: "Error") : String(localized: "New reply"), c.detail].compactMap { $0 }.joined(separator: ": "), app: c.profile.app, projectPath: c.projectPath)
        }
        for change in changes {
            if let before = seen[change.id], before != change.key, change.announce { lastChange = change }
            seen[change.id] = change.key
        }
        routines = list
        checkedAt = Date()
    }

    func clearChange() { lastChange = nil }

    var hasProfiles: Bool { profiles.count > 1 }

    private func label(_ title: String, _ profile: Profile) -> String {
        hasProfiles && !profile.isMain ? "\(title) · \(profile.short)" : title
    }

    private func accountDirs(under dir: URL) -> [URL] {
        let accounts = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return accounts.flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
    }

    private func json(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func readSessions(in dir: URL) -> [[String: Any]] {
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json" }
            .compactMap(json)
    }

    private func ms(_ v: Any?) -> Date? {
        (v as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    /// State, detail and finish time of one session, read from its own file.
    private func status(of s: [String: Any]) -> (RunState, String?, Date) {
        let active = ms(s["lastActivityAt"]) ?? ms(s["createdAt"]) ?? .distantPast
        let summary = s["postTurnSummary"] as? [String: Any]
        let wrap = (s["turnWrapUp"] as? [String: Any])?["description"] as? String
        let category = summary?["status_category"] as? String
        let needs = (summary?["needs_action"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if isRunning(s, active: active) { return (.running, String(localized: "Running…"), active) }
        if let error = s["error"] as? String, !error.isEmpty { return (.failed, error, active) }
        if category == "blocked" || s["interruptedAwaitingPerson"] as? Bool == true {
            return (.needsYou, needs ?? summary?["status_detail"] as? String ?? String(localized: "Waiting for your reply"), active)
        }
        if category == "completed" { return (.ok, wrap ?? summary?["status_detail"] as? String, active) }
        if let category, category.contains("fail") || category.contains("error") {
            return (.failed, summary?["status_detail"] as? String, active)
        }
        if s["lastTurnCutShort"] as? Bool == true { return (.failed, String(localized: "Cut short"), active) }
        return (.unknown, wrap, active)
    }

    // MARK: is a turn in progress

    private var transcripts: [String: URL] = [:]  // CLI session id → its .jsonl

    /// Every Claude Code transcript, by session id; listed once per refresh.
    private func indexTranscripts() {
        transcripts = [:]
        let root = home.appendingPathComponent(".claude/projects")
        for dir in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasSuffix(".jsonl") {
                transcripts[String(f.dropLast(6))] = dir.appendingPathComponent(f)
            }
        }
    }

    /// Read from the transcript's last entries: Claude is mid-turn when the last message
    /// is a tool call, a tool result or your prompt, not an answer that ended the turn.
    /// A transcript quiet for 10 minutes counts as stopped. Desktop's own activity time
    /// is a fallback only: it also moves after a turn ends.
    private func isRunning(_ s: [String: Any], active: Date) -> Bool {
        guard let cli = s["cliSessionId"] as? String, let url = transcripts[cli] else {
            let summarizedLast = s["postTurnSummaryFor"] as? String != nil
                && s["postTurnSummaryFor"] as? String == s["lastAssistantUuid"] as? String
            return !summarizedLast && Date().timeIntervalSince(active) < Self.runningWindow
        }
        guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              Date().timeIntervalSince(modified) < 600,
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 131_072 ? size - 131_072 : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return false }
        for line in text.split(separator: "\n").reversed() {
            guard let entry = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let type = entry["type"] as? String else { continue }
            if type == "system", let sub = entry["subtype"] as? String,
               sub.contains("stop") || sub.contains("turn_duration") { return false }
            guard type == "assistant" || type == "user",
                  let message = entry["message"] as? [String: Any] else { continue }
            if type == "assistant" {
                let stop = message["stop_reason"] as? String
                return stop == nil || stop == "tool_use" || stop == "pause_turn"
            }
            // Your prompt or a tool result: Claude has the turn, unless you stopped it.
            if let content = message["content"] as? String { return !content.contains("[Request interrupted") }
            if let blocks = message["content"] as? [[String: Any]] {
                let texts = blocks.compactMap { $0["text"] as? String }
                return !texts.contains { $0.contains("[Request interrupted") }
            }
            return true
        }
        return false
    }

    private func chat(_ s: [String: Any]) -> Chat? {
        guard s["scheduledTaskId"] == nil, s["isArchived"] as? Bool != true,
              let id = s["sessionId"] as? String else { return nil }
        let (state, detail, active) = status(of: s)
        // Opened in Claude, or marked read here, after the last reply: read.
        // The margin covers a reply that lands while the chat is on screen.
        let seenAt = max(ms(s["lastFocusedAt"]) ?? .distantPast,
                         Date(timeIntervalSince1970: readMarks[id] ?? 0))
        let unread = state != .running && active > seenAt.addingTimeInterval(90)
        let age = Date().timeIntervalSince(active)
        guard age < Self.chatWindow || (unread && age < 7 * 86400) else { return nil }
        let cwd = s["originCwd"] as? String ?? s["cwd"] as? String
        return Chat(id: id, title: s["title"] as? String ?? String(localized: "Untitled chat"),
                    project: Self.project(cwd),
                    lastActivity: active, state: state, detail: detail, unread: unread,
                    projectPath: Self.projectRoot(cwd))
    }

    private func readStore(_ dir: URL, sessions: [[String: Any]]) -> [Routine] {
        guard let tasks = json(dir.appendingPathComponent("scheduled-tasks.json"))?["scheduledTasks"] as? [[String: Any]],
              !tasks.isEmpty else { return [] }
        var latest: [String: [String: Any]] = [:]
        for s in sessions {
            guard let task = s["scheduledTaskId"] as? String else { continue }
            if (latest[task]?["createdAt"] as? Double ?? -1) < s["createdAt"] as? Double ?? 0 { latest[task] = s }
        }
        let now = Date()
        return tasks.compactMap { t in
            guard let id = t["id"] as? String else { return nil }
            let cron = (t["cronExpression"] as? String).flatMap(Cron.init)
            let created = ms(t["createdAt"]) ?? .distantPast
            var next = cron?.fire(from: now)
            if let fireAt = ms(t["fireAt"]) { next = fireAt > now ? fireAt : nil }
            var r = Routine(id: id, title: t["displayName"] as? String ?? id,
                            project: Self.project(t["cwd"] as? String),
                            enabled: t["enabled"] as? Bool ?? true, nextRun: next,
                            lastStart: nil, lastEnd: nil, state: .none, detail: nil, runKey: "\(id)-none")
            r.projectPath = Self.projectRoot(t["cwd"] as? String)
            if let s = latest[id] {
                let (state, detail, end) = status(of: s)
                r.lastStart = ms(s["createdAt"])
                r.sessionId = s["sessionId"] as? String
                r.lastEnd = state == .running ? nil : end
                r.state = state
                r.detail = detail
                r.runKey = "\(id)-\(r.lastStart?.timeIntervalSince1970 ?? 0)-\(state)"
            }
            // A firing that passed with no run after it (the app was closed, say).
            if r.state != .running, let cron, let prev = cron.fire(from: now, forward: false),
               now.timeIntervalSince(prev) > 20 * 60, prev > created {
                let lastFor = (t["lastScheduledFor"] as? String).flatMap(iso)
                    ?? (t["lastRunAt"] as? String).flatMap(iso) ?? created
                if lastFor < prev.addingTimeInterval(-60) {
                    r.state = .missed
                    r.detail = String(localized: "The run due \(Fmt.when(prev)) did not happen")
                    r.runKey = "\(id)-missed-\(prev.timeIntervalSince1970)"
                }
            }
            return r
        }
    }

    /// The repository folder of a working folder; none for scratch folders.
    static func projectRoot(_ path: String?) -> String? {
        guard var path, !path.isEmpty, !path.contains("/scratch-workspaces/") else { return nil }
        if let r = path.range(of: "/.claude/worktrees/") { path = String(path[..<r.lowerBound]) }
        return path
    }

    /// The Desktop project a folder belongs to: a worktree counts as its repository.
    static func project(_ path: String?) -> String {
        guard var path, !path.isEmpty else { return String(localized: "No project") }
        if path.contains("/scratch-workspaces/") { return String(localized: "Scratch") }
        if let r = path.range(of: "/.claude/worktrees/") { path = String(path[..<r.lowerBound]) }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func iso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

enum Fmt {
    /// The language the interface is shown in, so dates read the same as the words around them.
    static let locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")

    static func when(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("HHmm")
        let time = f.string(from: d)
        let cal = Calendar.current
        if cal.isDateInToday(d) { return String(localized: "today \(time)") }
        if cal.isDateInTomorrow(d) { return String(localized: "tomorrow \(time)") }
        if cal.isDateInYesterday(d) { return String(localized: "yesterday \(time)") }
        f.setLocalizedDateFormatFromTemplate("EEEdMMMHHmm")
        return f.string(from: d)
    }

    static func until(_ d: Date, now: Date = Date()) -> String {
        let m = Int(d.timeIntervalSince(now) / 60)
        if m < 1 { return String(localized: "now") }
        if m < 60 { return String(localized: "\(m) min") }
        if m < 24 * 60 { return String(localized: "\(m / 60) h \(m % 60) min") }
        return String(localized: "\(m / (24 * 60)) d")
    }

    static func ago(_ d: Date, now: Date = Date()) -> String {
        let m = Int(now.timeIntervalSince(d) / 60)
        if m < 1 { return String(localized: "just now") }
        if m < 60 { return String(localized: "\(m) min ago") }
        if m < 24 * 60 { return String(localized: "\(m / 60) h ago") }
        return String(localized: "\(m / (24 * 60)) d ago")
    }
}
