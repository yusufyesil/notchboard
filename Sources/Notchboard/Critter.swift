import SwiftUI

/// A small pixel creature in a project's colour that acts out a state:
/// types while working, waves when it needs you, hops on a new reply,
/// slumps with red eyes on a failure, and sleeps otherwise.
struct Critter: View {
    let state: RunState
    let color: Color
    var pixel: CGFloat = 2

    private enum Act { case typing, waving, hopping, sad, sleeping }

    private var act: Act {
        switch state {
        case .running: return .typing
        case .needsYou: return .waving
        case .unread: return .hopping
        case .failed, .missed: return .sad
        default: return .sleeping
        }
    }

    private var fps: Double {
        switch act {
        case .typing: return 5
        case .waving: return 3
        case .hopping: return 3
        case .sad: return 0.5
        case .sleeping: return 1
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1 / fps)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate * fps)
            let (frame, lift) = Self.frame(for: act, tick: tick)
            Canvas { ctx, _ in
                for (y, row) in frame.enumerated() {
                    for (x, ch) in row.enumerated() {
                        guard let fill = paint(ch) else { continue }
                        let rect = CGRect(x: CGFloat(x) * pixel, y: CGFloat(y + 1 - lift) * pixel, width: pixel, height: pixel)
                        ctx.fill(Path(rect), with: .color(fill))
                    }
                }
            }
            .frame(width: pixel * 10, height: pixel * 9)
        }
    }

    private func paint(_ ch: Character) -> Color? {
        switch ch {
        case "B": return color
        case "D": return .black.opacity(0.8)
        case "K": return .white.opacity(0.22)
        case "Z": return .white.opacity(0.6)
        case "R": return Color(red: 1, green: 0.3, blue: 0.3)
        default: return nil
        }
    }

    // 10 × 8 frames. B body, D eyes, K keyboard, Z sleep, R red eyes.
    private static let typing = [
        ["..BBBBBB..", ".BBBBBBBB.", ".BBBBBBBB.", ".BDBBBBDB.", ".BBBBBBBB.", "BBBBBBBBB.", "..B.BB.B.B", "KKKKKKKKKK"],
        ["..BBBBBB..", ".BBBBBBBB.", ".BBBBBBBB.", ".BDBBBBDB.", ".BBBBBBBB.", ".BBBBBBBBB", "B.B.BB.B..", "KKKKKKKKKK"],
    ]
    private static let waving = [
        ["..BBBBBB.B", ".BBBBBBBBB", ".BDBBBBDB.", ".BDBBBBDB.", ".BBBBBBBB.", ".BBBBBBBB.", "..B.BB.B..", ".........."],
        ["..BBBBBB..", ".BBBBBBBBB", ".BDBBBBDBB", ".BDBBBBDB.", ".BBBBBBBB.", ".BBBBBBBB.", "..B.BB.B..", ".........."],
    ]
    private static let open =
        ["..BBBBBB..", ".BBBBBBBB.", ".BDBBBBDB.", ".BDBBBBDB.", ".BBBBBBBB.", ".BBBBBBBB.", "..B.BB.B..", ".........."]
    private static let sad = [
        ["..........", "..BBBBBB..", ".BBBBBBBB.", ".BRBBBBRB.", ".BBBBBBBB.", ".BBDDDDBB.", ".BBBBBBBB.", "..B.BB.B.."],
    ]
    private static let sleeping = [
        ["........Z.", "..........", "..BBBBBB..", ".BBBBBBBB.", ".DDBBBBDD.", ".BBBBBBBB.", ".BBBBBBBB.", "..BBBBBB.."],
        [".......Z..", "........Z.", "..........", "..BBBBBB..", ".BBBBBBBB.", ".DDBBBBDD.", ".BBBBBBBB.", ".BBBBBBBB."],
    ]

    /// The frame for a tick, and how many pixels it is lifted (for the hop).
    private static func frame(for act: Act, tick: Int) -> ([String], Int) {
        switch act {
        case .typing: return (typing[tick % 2], 0)
        case .waving: return (waving[tick % 2], 0)
        case .hopping: return (open, tick % 2 == 0 ? 0 : 1)
        case .sad: return (sad[0], 0)
        case .sleeping: return (sleeping[tick % 2], 0)
        }
    }
}
