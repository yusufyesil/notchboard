import SwiftUI

extension RunState {
    var color: Color {
        switch self {
        case .ok: return .green
        case .failed, .missed: return .red
        case .running: return .orange
        case .needsYou: return .orange
        case .none, .unknown: return .gray
        case .unread: return .blue
        }
    }
    var symbol: String {
        switch self {
        case .ok: return "checkmark"
        case .failed: return "xmark"
        case .missed: return "clock.badge.exclamationmark"
        case .running: return "arrow.triangle.2.circlepath"
        case .needsYou: return "hand.raised.fill"
        case .unknown: return "circle.fill"
        case .unread: return "bubble.left.fill"
        case .none: return "circle.dashed"
        }
    }
    var word: String {
        switch self {
        case .ok: return String(localized: "succeeded")
        case .failed: return String(localized: "failed")
        case .missed: return String(localized: "missed")
        case .running: return String(localized: "running")
        case .needsYou: return String(localized: "waiting for you")
        case .unknown: return String(localized: "done")
        case .unread: return String(localized: "new reply")
        case .none: return String(localized: "never ran")
        }
    }
}

/// The island: shoulders that curve out into the menu bar, like the real notch,
/// and a rounded bottom.
struct NotchShape: Shape {
    var radius: CGFloat
    var shoulder: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(radius, shoulder) }
        set { radius = newValue.first; shoulder = newValue.second }
    }
    func path(in r: CGRect) -> Path {
        let s = shoulder
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + s, y: r.minY + s), control: CGPoint(x: r.minX + s, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + s + radius, y: r.maxY), control: CGPoint(x: r.minX + s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - s - radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - s, y: r.maxY - radius), control: CGPoint(x: r.maxX - s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.minY + s))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - s, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// An eight-ray spark: the island's single status mark.
struct Spark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let outer = min(r.width, r.height) / 2
        let w = outer * 0.17
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4
            let dir = CGPoint(x: cos(a), y: sin(a))
            let n = CGPoint(x: -dir.y, y: dir.x)
            let len = i % 2 == 0 ? outer : outer * 0.78
            p.move(to: CGPoint(x: c.x + n.x * w, y: c.y + n.y * w))
            p.addLine(to: CGPoint(x: c.x + dir.x * len + n.x * w * 0.4, y: c.y + dir.y * len + n.y * w * 0.4))
            p.addLine(to: CGPoint(x: c.x + dir.x * len - n.x * w * 0.4, y: c.y + dir.y * len - n.y * w * 0.4))
            p.addLine(to: CGPoint(x: c.x - n.x * w, y: c.y - n.y * w))
            p.closeSubpath()
        }
        return p
    }
}

/// The spark in the state's colour; it turns slowly while something works.
struct SparkMark: View {
    let color: Color
    let working: Bool
    var size: CGFloat = 14
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !working)) { context in
            Spark()
                .fill(color)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(working ? context.date.timeIntervalSinceReferenceDate * 90 : 0))
                .shadow(color: color.opacity(working ? 0.6 : 0.25), radius: working ? 4 : 2)
        }
    }
}

enum Tab: String, CaseIterable {
    case chats, routines

    var title: String {
        switch self {
        case .chats: return String(localized: "Chats")
        case .routines: return String(localized: "Routines")
        }
    }
}

@MainActor
final class NotchModel: ObservableObject {
    @Published var expanded = false
    @Published var tab: Tab = .chats
    @Published var profileFilter: String?  // a profile's slug; nil shows every profile
    @Published var notchWidth: CGFloat = 0
    @Published var barHeight: CGFloat = 32
}

/// One line in any section: a routine, a chat or a problem.
struct Item: Identifiable {
    let id: String
    let project: String
    let state: RunState
    let isAcked: Bool
    let isNew: Bool
    let title: String
    let subtitle: String
    let detail: String?
    let trailing: String?
    let ackKey: String?
    var chatId: String? = nil
    var tint: Color? = nil  // overrides the state's colour
    var profile: Profile = .main
    var sessionId: String? = nil  // what a click opens
    var projectPath: String? = nil
    var badge: Bool = false  // shown when clones exist, on a clone's rows only
    var lastRun: String? = nil  // a routine's last run, short: "yesterday 14:04"
    var isRoutine = false
}

struct NotchView: View {
    @ObservedObject var store: Store
    @ObservedObject var model: NotchModel
    var onHover: (Bool) -> Void
    @Namespace private var tabSpace
    @ObservedObject private var logos = Logos.shared  // redraws once a logo's colour is known

    static let sideWidth: CGFloat = 100
    static let expandedWidth: CGFloat = 540
    private var shoulder: CGFloat { model.expanded ? 14 : 8 }

    var body: some View {
        ZStack(alignment: .top) {
            if model.expanded {
                expandedBody.transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
            } else {
                compactBody.transition(.opacity)
            }
        }
        .padding(.horizontal, shoulder)
        .frame(width: model.expanded ? Self.expandedWidth : model.notchWidth + Self.sideWidth * 2, alignment: .top)
        .background(NotchShape(radius: model.expanded ? 30 : 12, shoulder: shoulder).fill(.black))
        .shadow(color: .black.opacity(model.expanded ? 0.5 : 0), radius: 18, y: 8)
        .onHover(perform: onHover)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.expanded)
        .preferredColorScheme(.dark)
    }

    // MARK: compact

    private var sparkColor: Color {
        if store.openProblems > 0 { return .red }
        if store.runningCount > 0 { return .orange }
        if store.newSinceViewed > 0 { return .blue }
        return .white.opacity(0.55)
    }

    /// The creature the closed island shows: the most urgent project's, acting out its state;
    /// a grey sleeper when all is quiet.
    private var focusCritter: (state: RunState, color: Color) {
        func tint(_ name: String, _ path: String?) -> Color { logos.accent(for: path, name: name) }
        if let c = store.chats.first(where: \.needsAttention) {
            return (c.state == .failed ? .failed : .needsYou, tint(c.project, c.projectPath))
        }
        if let r = store.routines.first(where: { $0.state.isProblem && !store.isAcked($0.runKey) }) {
            return (r.state == .needsYou ? .needsYou : .failed, tint(r.project, r.projectPath))
        }
        if let c = store.chats.first(where: { $0.state == .running }) { return (.running, tint(c.project, c.projectPath)) }
        if let r = store.routines.first(where: { $0.state == .running }) { return (.running, tint(r.project, r.projectPath)) }
        if let c = store.chats.first(where: \.unread) { return (.unread, tint(c.project, c.projectPath)) }
        return (.ok, .white.opacity(0.45))
    }

    /// Projects that want a look, most urgent first: problems, work in progress, new replies.
    private var focusProjects: [(name: String, path: String?)] {
        var out: [(name: String, path: String?)] = []
        func add(_ name: String, _ path: String?) {
            if !out.contains(where: { $0.name == name }) { out.append((name, path)) }
        }
        for c in store.chats where c.needsAttention { add(c.project, c.projectPath) }
        for r in store.routines where r.state.isProblem && !store.isAcked(r.runKey) { add(r.project, r.projectPath) }
        for c in store.chats where c.state == .running { add(c.project, c.projectPath) }
        for r in store.routines where r.state == .running { add(r.project, r.projectPath) }
        for c in store.chats where c.unread { add(c.project, c.projectPath) }
        return out
    }

    private var compactBody: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Critter(state: focusCritter.state, color: focusCritter.color, pixel: 2)
                if !focusProjects.isEmpty {
                    LogoStack(projects: focusProjects, size: 15)
                        .transition(.scale.combined(with: .opacity))
                }
                if store.openProblems > 0 {
                    Text("\(store.openProblems)").foregroundStyle(.red)
                } else if store.newSinceViewed > 0 {
                    Text("\(store.newSinceViewed)").foregroundStyle(.blue)
                }
            }
            .frame(width: Self.sideWidth - 14, alignment: .leading)
            .padding(.leading, 6)
            Spacer(minLength: model.notchWidth - 24)
            Group {
                if store.runningCount > 0 {
                    HStack(spacing: 5) { WorkingDots(size: 4); Text("\(store.runningCount)").foregroundStyle(.orange) }
                } else if let next = store.routines.first(where: { $0.nextRun != nil })?.nextRun {
                    HStack(spacing: 4) {
                        Image(systemName: "clock").font(.system(size: 10, weight: .semibold))
                        Text(Fmt.until(next))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: Self.sideWidth - 14, alignment: .trailing)
            .padding(.trailing, 6)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
        .frame(height: model.barHeight)
    }

    // MARK: expanded

    private func shown(_ p: Profile) -> Bool { model.profileFilter == nil || model.profileFilter == p.slug }
    private var routines: [Routine] { store.routines.filter { shown($0.profile) } }
    private var chats: [Chat] { store.chats.filter { shown($0.profile) } }

    private var attention: [Item] {
        routines.filter { $0.state.isProblem && !store.isAcked($0.runKey) }.map(routineItem)
            + chats.filter(\.needsAttention).map(chatItem)
    }

    private func open(_ state: RunState, _ key: String) -> Bool { state.isProblem && !store.isAcked(key) }

    private var chatItems: [Item] {
        chats.filter { !$0.needsAttention }.map(chatItem)
    }

    private var routineItems: [Item] {
        routines.filter { !open($0.state, $0.runKey) }.map(routineItem)
    }

    private func routineItem(_ r: Routine) -> Item {
        let acked = r.state.isProblem && store.isAcked(r.runKey)
        let last: String
        let ackedNote = acked ? " · " + String(localized: "acknowledged") : ""
        if r.state == .missed { last = String(localized: "Missed") + ackedNote }
        else if let s = r.lastStart { last = String(localized: "Last: \(Fmt.when(s)) · \(r.state.word)") + ackedNote }
        else { last = String(localized: "Never ran") }
        return Item(id: "r-" + r.id, project: r.project, state: r.state, isAcked: acked, isNew: store.isNew(r.lastEnd) && r.state != .missed,
                    title: r.title,
                    subtitle: last + (r.nextRun.map { " · " + String(localized: "next \(Fmt.when($0))") } ?? ""),
                    detail: r.detail, trailing: r.nextRun.map { Fmt.until($0) },
                    ackKey: r.state.isProblem && !acked ? r.runKey : nil,
                    profile: r.profile, sessionId: r.sessionId, projectPath: r.projectPath, badge: store.hasProfiles && !r.profile.isMain,
                    lastRun: r.state == .missed ? String(localized: "missed") : r.lastStart.map { Fmt.when($0) } ?? String(localized: "never ran"),
                    isRoutine: true)
    }

    /// A chat is about replies: new one, a question for you, or read.
    private func chatItem(_ c: Chat) -> Item {
        let (word, tint): (String, Color) = {
            if c.state == .running { return (String(localized: "typing"), .orange) }
            if c.unread {
                switch c.state {
                case .needsYou: return (String(localized: "waiting for your reply"), .orange)
                case .failed: return (String(localized: "error"), .red)
                default: return (String(localized: "new reply"), .blue)
                }
            }
            return ("", c.state == .needsYou ? .orange.opacity(0.6) : .gray)
        }()
        let symbol: RunState = c.state == .running ? .running
            : !c.unread ? (c.state == .needsYou ? .needsYou : .unknown)
            : c.state == .ok || c.state == .unknown ? .unread : c.state
        return Item(id: "c-" + c.id, project: c.project, state: symbol, isAcked: false,
                    isNew: c.unread, title: c.title, subtitle: word,
                    detail: c.state == .running || !c.unread ? nil : c.detail, trailing: Fmt.ago(c.lastActivity),
                    ackKey: nil, chatId: c.id, tint: tint,
                    profile: c.profile, sessionId: c.id, projectPath: c.projectPath, badge: store.hasProfiles && !c.profile.isMain)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                tabBar
                Spacer()
                if store.hasProfiles { profileMenu }
            }
            .padding(.top, model.barHeight + 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if !attention.isEmpty { attentionCard.padding(.bottom, 8) }
                    let items = model.tab == .chats ? chatItems : routineItems
                    if items.isEmpty {
                        Text(model.tab == .chats ? String(localized: "No chats in the last 24 hours.") : String(localized: "No routines."))
                            .font(.system(size: 12, design: .rounded)).foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                    ForEach(groups(items), id: \.0) { project, rows in
                        header(project, path: rows.first?.projectPath, count: rows.count,
                               running: rows.contains { $0.state == .running })
                        ForEach(rows) { row($0, showProject: false) }
                    }
                }
                .padding(.bottom, 6)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 560)
            .fixedSize(horizontal: false, vertical: true)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            HStack {
                Text("last seen \(Fmt.ago(store.lastViewedAt))")
                Spacer()
                Text("updated \(store.checkedAt.formatted(date: .omitted, time: .shortened))")
            }
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(.white.opacity(0.28))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
    }

    /// Unacknowledged problems in one tinted card above the tabs.
    private var attentionCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                Text("Attention").font(.system(size: 11, weight: .semibold, design: .rounded))
                Text("\(attention.count)").foregroundStyle(.red.opacity(0.5))
                Spacer()
                if attention.count > 1 {
                    Button("Acknowledge all") { store.ackAll() }.buttonStyle(Pill())
                }
            }
            .foregroundStyle(.red.opacity(0.9))
            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
            ForEach(attention) { row($0, showProject: true) }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 16).fill(.red.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.red.opacity(0.22), lineWidth: 1))
    }

    /// Projects in the order of their first row: most recent chat, soonest routine.
    private func groups(_ items: [Item]) -> [(String, [Item])] {
        var order: [String] = []
        var byProject: [String: [Item]] = [:]
        for item in items {
            if byProject[item.project] == nil { order.append(item.project) }
            byProject[item.project, default: []].append(item)
        }
        return order.map { ($0, byProject[$0]!) }
    }

    /// Every profile merged by default; the menu narrows the whole list to one.
    private var profileMenu: some View {
        let current = store.profiles.first { $0.slug == model.profileFilter }
        return Menu {
            Button("All profiles") { model.profileFilter = nil }
            Divider()
            ForEach(store.profiles, id: \.slug) { p in
                Button(p.isMain ? String(localized: "Main profile") : p.name) { model.profileFilter = p.slug }
            }
        } label: {
            HStack(spacing: 5) {
                if let current, !current.isMain { Circle().fill(current.color).frame(width: 6, height: 6) }
                Text(current?.short ?? String(localized: "All"))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.07)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { tab in
                let items = tab == .chats ? chatItems : routineItems
                let working = tab == .chats ? chats.contains { $0.state == .running }
                                            : routines.contains { $0.state == .running }
                let fresh = items.contains(where: \.isNew)
                Button {
                    model.tab = tab
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.title)
                        if working { WorkingDots(size: 3.5) }
                        else if fresh { Circle().fill(.blue).frame(width: 5, height: 5) }
                        else { Text("\(items.count)").foregroundStyle(.white.opacity(0.35)) }
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(model.tab == tab ? 1 : 0.5))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background {
                        if model.tab == tab { Capsule().fill(.white.opacity(0.12)).matchedGeometryEffect(id: "tab", in: tabSpace) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.05)))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.tab)
    }

    private func header(_ title: String, path: String?, count: Int, running: Bool) -> some View {
        HStack(spacing: 7) {
            ProjectLogo(name: title, path: path, size: 16)
            Text(title)
            Text("\(count)").foregroundStyle(.white.opacity(0.22))
            if running { WorkingDots(size: 3) }
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.4))
        .padding(.horizontal, 8)
        .padding(.top, 10).padding(.bottom, 2)
        .contentShape(Rectangle())
        .contextMenu {
            if let path {
                Button("Choose logo…") { Logos.shared.choose(for: path, name: title) }
                Button("Use initial") { Logos.shared.useLetter(for: path) }
                if Logos.shared.hasOverride(path) {
                    Button("Back to automatic logo") { Logos.shared.useAutomatic(for: path) }
                }
                Divider()
                Button("Show folder in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) }
            }
        }
    }

    private func row(_ item: Item, showProject: Bool) -> some View {
        ItemRow(item: item, showProject: showProject,
                onAck: { if let k = item.ackKey { store.ack(k) } },
                onOpen: { if let id = item.chatId { store.markRead(id) } })
    }
}

struct ItemRow: View {
    let item: Item
    let showProject: Bool
    let onAck: () -> Void
    let onOpen: () -> Void
    @State private var hovering = false
    @ObservedObject private var logos = Logos.shared

    private var color: Color { item.tint ?? (item.isAcked ? .gray : item.state.color) }

    private func openItem() {
        if let id = item.sessionId { item.profile.open(session: id) } else { item.profile.open() }
    }

    /// A read chat: one line, nothing to act on.
    private var isQuiet: Bool { item.subtitle.isEmpty && item.detail == nil }

    var body: some View {
        if item.isRoutine && item.ackKey == nil { routineRow }
        else if isQuiet { quietRow } else { fullRow }
    }

    /// A routine in its tab: one line; the summary shows on hover.
    private var routineRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                StateIcon(state: item.state, color: color, size: 10)
                    .frame(width: 26)
                Text(item.title)
                    .font(.system(size: 12.5, weight: item.isNew || item.state == .running ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(item.isNew || item.state == .running ? 0.95 : 0.7))
                    .lineLimit(1)
                if item.isNew { Circle().fill(.blue).frame(width: 5, height: 5) }
                if item.badge { ProfileBadge(profile: item.profile) }
                Spacer(minLength: 8)
                if let last = item.lastRun {
                    Text(last).foregroundStyle(item.isAcked ? .gray : color.opacity(item.state == .unknown || item.state == .none ? 0.4 : 0.75))
                }
                if let next = item.trailing {
                    HStack(spacing: 3) {
                        Image(systemName: "clock").font(.system(size: 9, weight: .semibold))
                        Text(next)
                    }
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(minWidth: 58, alignment: .trailing)
                }
            }
            .font(.system(size: 11, design: .rounded).monospacedDigit())
            if hovering, let d = item.detail {
                Text(d).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(4)
                    .padding(.leading, 34)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(hovering ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { openItem() }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var quietRow: some View {
        HStack(spacing: 10) {
            StateIcon(state: item.state, color: color, size: 7, plain: true)
            Text(showProject ? "\(item.title) · \(item.project)" : item.title)
                .font(.system(size: 12.5, design: .rounded)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            if item.badge { ProfileBadge(profile: item.profile) }
            Spacer(minLength: 8)
            if let t = item.trailing {
                Text(t).font(.system(size: 11, design: .rounded).monospacedDigit()).foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(hovering ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { openItem() }
    }

    private var fullRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Critter(state: item.isAcked ? .ok : item.state,
                    color: logos.accent(for: item.projectPath, name: item.project), pixel: 2)
                .frame(width: 26, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                    if item.badge { ProfileBadge(profile: item.profile) }
                    Spacer(minLength: 8)
                    if let t = item.trailing {
                        Text(t).font(.system(size: 11, design: .rounded).monospacedDigit()).foregroundStyle(.white.opacity(0.35))
                    }
                }
                HStack(spacing: 5) {
                    if showProject {
                        ProjectLogo(name: item.project, path: item.projectPath, size: 12)
                        Text(item.project).foregroundStyle(.white.opacity(0.45))
                        Text("·").foregroundStyle(.white.opacity(0.25))
                    }
                    Text(item.subtitle).foregroundStyle(color)
                }
                .font(.system(size: 11, weight: .medium, design: .rounded)).lineLimit(1)
                if let d = item.detail {
                    Text(d).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                        .lineLimit(hovering ? 5 : 1)
                        .padding(.top, 1)
                }
            }
            if item.ackKey != nil {
                Button("OK", action: onAck).buttonStyle(Pill()).padding(.top, 2)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            onOpen()
            openItem()
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct Pill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.28 : 0.12)))
            .foregroundStyle(.white)
    }
}

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}

/// A quiet hint of which clone a row belongs to: its Dock colour and name, dimmed.
struct ProfileBadge: View {
    let profile: Profile
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(profile.color.opacity(0.7)).frame(width: 5, height: 5)
            Text(profile.short).font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
        }
        .fixedSize()
    }
}

/// Three orange dots that pulse in turn: something is working.
struct WorkingDots: View {
    var size: CGFloat = 4.5
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.3) % 3
            HStack(spacing: size * 0.6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(.orange).opacity(i == step ? 1 : 0.35).frame(width: size, height: size)
                }
            }
        }
    }
}

/// A row's status mark: the state's symbol, a dot for quiet rows, or the dots while it works.
struct StateIcon: View {
    let state: RunState
    let color: Color
    let size: CGFloat
    var plain = false
    var body: some View {
        Group {
            if state == .running { WorkingDots(size: plain ? 3 : size * 0.3) }
            else if plain { Circle().fill(color.opacity(0.6)).frame(width: size, height: size) }
            else { Image(systemName: state.symbol).foregroundStyle(color).font(.system(size: size, weight: .semibold)) }
        }
        .frame(width: plain ? 26 : 18, height: plain ? 12 : size + 4)
    }
}

/// Several projects' logos overlapping, the first on top; past three, a "+N".
struct LogoStack: View {
    let projects: [(name: String, path: String?)]
    var size: CGFloat = 15
    private let limit = 3

    var body: some View {
        HStack(spacing: -size * 0.38) {
            ForEach(Array(projects.prefix(limit).enumerated()), id: \.element.name) { i, p in
                ProjectLogo(name: p.name, path: p.path, size: size)
                    .padding(1.5)
                    .background(RoundedRectangle(cornerRadius: size * 0.36, style: .continuous).fill(.black))
                    .zIndex(Double(limit - i))
            }
            if projects.count > limit {
                Text("+\(projects.count - limit)")
                    .font(.system(size: size * 0.6, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: size + 3, height: size + 3)
                    .background(RoundedRectangle(cornerRadius: size * 0.36, style: .continuous).fill(Color(white: 0.18)))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.36, style: .continuous).strokeBorder(.black, lineWidth: 1.5))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: projects.map(\.name))
    }
}

