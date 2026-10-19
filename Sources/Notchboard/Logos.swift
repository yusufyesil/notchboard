import AppKit
import CryptoKit
import SwiftUI

/// Project logos: one you picked, else an icon found in the project folder,
/// else the project's initial on a colour of its own.
@MainActor
final class Logos: ObservableObject {
    static let shared = Logos()

    @Published private(set) var images: [String: NSImage] = [:]  // project path → logo
    @Published private(set) var colors: [String: Color] = [:]    // project path → its logo's colour
    private var looked: Set<String> = []
    private var overrides: [String: String]  // project path → stored file, or "letter"
    private let defaults = UserDefaults.standard
    private let store = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Notchboard/logos")

    private init() {
        overrides = defaults.dictionary(forKey: "logoOverrides") as? [String: String] ?? [:]
    }

    func image(for path: String?) -> NSImage? {
        guard let path else { return nil }
        if !looked.contains(path) { look(path) }
        return images[path]
    }

    /// A PNG of the logo for a notification attachment (which moves the file it gets).
    func attachmentFile(for path: String?) -> URL? {
        guard let image = image(for: path), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notchboard-\(UUID().uuidString).png")
        return (try? png.write(to: url)) != nil ? url : nil
    }

    // MARK: choosing

    func choose(for path: String, name: String) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose a logo for \(name)")
        panel.allowedContentTypes = [.image]
        panel.directoryURL = URL(fileURLWithPath: path)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let src = panel.url, let image = NSImage(contentsOf: src) else { return }
        try? FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        let dest = store.appendingPathComponent(Self.hash(path) + "." + src.pathExtension.lowercased())
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: src, to: dest)
        setOverride(path, dest.path)
        setImage(image, for: path)
    }

    func useLetter(for path: String) {
        setOverride(path, "letter")
        images[path] = nil
        colors[path] = nil
    }

    func useAutomatic(for path: String) {
        setOverride(path, nil)
        looked.remove(path)
        images[path] = nil
        colors[path] = nil
        look(path)
    }

    private func setImage(_ image: NSImage, for path: String) {
        images[path] = image
        colors[path] = Self.dominantColor(of: image)
    }

    /// The project's colour: its logo's, else the one its initial is drawn on, lifted to read on black.
    func accent(for path: String?, name: String) -> Color {
        if let path {
            if !looked.contains(path) { look(path) }
            if let c = colors[path] { return c }
        }
        return ProjectLogo.color(for: name, brightness: 0.9)
    }

    /// The logo's most common saturated hue, at a saturation and brightness that read
    /// on black; nil for a black, white or grey logo.
    nonisolated static func dominantColor(of image: NSImage) -> Color? {
        let side = 24
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        var weight = [Double](repeating: 0, count: 12)
        var hueSum = [Double](repeating: 0, count: 12)
        for x in 0..<side {
            for y in 0..<side {
                guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.6 else { continue }
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                guard s > 0.25, b > 0.25 else { continue }
                let i = min(Int(h * 12), 11)
                weight[i] += Double(s)
                hueSum[i] += Double(h * s)
            }
        }
        guard let top = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[top] > 3 else { return nil }
        return Color(hue: hueSum[top] / weight[top], saturation: 0.62, brightness: 0.92)
    }

    var hasOverride: (String) -> Bool { { [overrides] in overrides[$0] != nil } }

    private func setOverride(_ path: String, _ value: String?) {
        overrides[path] = value
        defaults.set(overrides, forKey: "logoOverrides")
    }

    // MARK: finding

    private func look(_ path: String) {
        looked.insert(path)
        if let o = overrides[path] {
            // Not while a view is drawing: publish on the next turn.
            if o != "letter", let image = NSImage(contentsOfFile: o) {
                DispatchQueue.main.async { self.setImage(image, for: path) }
            }
            return
        }
        Task.detached(priority: .utility) {
            guard let url = Self.findIcon(in: URL(fileURLWithPath: path)),
                  let image = NSImage(contentsOf: url), image.isValid else { return }
            await MainActor.run { self.setImage(image, for: path) }
        }
    }

    nonisolated private static let skipped: Set<String> = [
        "node_modules", ".git", "build", ".build", "Pods", ".dart_tool", "dist", ".next", ".claude",
        "archive", "arsiv", "arşiv", "sunumlar", "DerivedData", ".venv", "venv", "vendor", "coverage",
    ]

    /// Scores what a project folder holds: an app icon first, then a root logo,
    /// a favicon, any logo file; shallower wins.
    nonisolated static func findIcon(in root: URL) -> URL? {
        let fm = FileManager.default
        var best: (score: Int, url: URL)?
        var seen = 0
        // Words of the project's own name: a logo named for it is the project's,
        // "acme-logo" in the same folder is someone else's.
        let projectName = root.lastPathComponent.lowercased().filter { $0.isLetter || $0.isNumber }
        func namesProject(_ fileName: String) -> Bool {
            let generic: Set<String> = ["logo", "icon", "png", "svg", "jpg", "jpeg", "webp", "ico", "cropped",
                                        "background", "app", "the", "v1", "v2", "v3", "alpha", "dark", "light"]
            let words = fileName.split { !$0.isLetter && !$0.isNumber }.map(String.init)
            return words.contains { $0.count >= 2 && !generic.contains($0) && projectName.contains($0) }
        }
        func consider(_ url: URL, depth: Int) {
            let name = url.lastPathComponent.lowercased()
            let ext = url.pathExtension.lowercased()
            guard ["png", "svg", "ico", "icns", "jpg", "jpeg", "webp"].contains(ext) else { return }
            let parent = url.deletingLastPathComponent().lastPathComponent.lowercased()
            let inLogoFolder = ["logo", "logos", "brand", "branding"].contains(parent)
            var score: Int
            // A file named for the app icon is the project's own; an .appiconset may
            // still hold a template's default (Flutter's, say).
            if name.contains("appicon") { score = 110 }
            else if depth == 0 && (name.hasPrefix("logo.") || name.hasPrefix("icon.")) { score = 95 }
            else if name.contains("logo") && namesProject(name) { score = 90 }
            else if parent == "appicon.appiconset" { score = 85 + min(pixelSize(url) / 128, 8) }
            else if inLogoFolder { score = 78 }
            else if name.hasPrefix("apple-touch-icon") { score = 75 }
            else if name == "ic_launcher.png" && parent.contains("xxxhdpi") { score = 72 }
            else if name.hasPrefix("logo") { score = 70 }
            else if name.hasPrefix("favicon") { score = ext == "png" ? 65 : ext == "svg" ? 60 : 45 }
            else if name.hasPrefix("icon-512") || name.hasPrefix("icon-192") { score = 62 }
            else { return }
            if ext == "ico" { score -= 10 }
            score -= depth * 4
            guard score > (best?.score ?? 0) - 6 else { return }
            // In a notch slot a square mark reads; a wide wordmark does not.
            if let rep = NSImageRep(contentsOf: url), rep.pixelsHigh > 0 {
                let ratio = Double(rep.pixelsWide) / Double(rep.pixelsHigh)
                if ratio > 0.8 && ratio < 1.25 { score += 5 } else if ratio > 2 || ratio < 0.5 { score -= 12 }
                if rep.pixelsWide > 0 && rep.pixelsWide < 32 { score -= 15 }
            }
            if score > (best?.score ?? 0) { best = (score, url) }
        }
        // Breadth first, so a big repository's shallow files are seen before the cap.
        var queue: [(URL, Int)] = [(root, 0)]
        while !queue.isEmpty, seen < 8000 {
            let (dir, depth) = queue.removeFirst()
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                           options: [.skipsHiddenFiles]) else { continue }
            for item in items {
                seen += 1
                if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false {
                    let n = item.lastPathComponent
                    if depth < 4 && !skipped.contains(n) && !n.hasSuffix(".app") { queue.append((item, depth + 1)) }
                } else {
                    consider(item, depth: depth)
                }
            }
        }
        return best?.url
    }

    nonisolated private static func pixelSize(_ url: URL) -> Int {
        guard let rep = NSImageRep(contentsOf: url) else { return 0 }
        return rep.pixelsWide
    }

    nonisolated static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// A project's logo, or its initial on a colour derived from its name.
struct ProjectLogo: View {
    let name: String
    let path: String?
    var size: CGFloat = 16
    @ObservedObject private var logos = Logos.shared

    var body: some View {
        Group {
            if let image = logos.image(for: path) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                ZStack {
                    Self.color(for: name)
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.58, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }

    static func color(for name: String, brightness: Double = 0.62) -> Color {
        let hues: [Double] = [0.58, 0.47, 0.08, 0.75, 0.92, 0.36, 0.02, 0.66]
        let i = Int(Profiles.cksum(name) % UInt32(hues.count))
        return Color(hue: hues[i], saturation: 0.55, brightness: brightness)
    }
}
