import Foundation

/// Five-field cron (minute hour day-of-month month day-of-week), local time.
struct Cron {
    let minutes: Set<Int>
    let hours: Set<Int>
    let days: Set<Int>
    let months: Set<Int>
    let weekdays: Set<Int>  // 0 = Sunday
    let dayRestricted: Bool
    let weekdayRestricted: Bool

    init?(_ expression: String) {
        let f = expression.split(separator: " ").map(String.init)
        guard f.count == 5,
              let mi = Cron.field(f[0], 0, 59), let h = Cron.field(f[1], 0, 23),
              let d = Cron.field(f[2], 1, 31), let mo = Cron.field(f[3], 1, 12),
              let w = Cron.field(f[4], 0, 7)
        else { return nil }
        minutes = mi; hours = h; days = d; months = mo
        weekdays = Set(w.map { $0 % 7 })
        dayRestricted = f[2] != "*"
        weekdayRestricted = f[4] != "*"
    }

    private static func field(_ s: String, _ lo: Int, _ hi: Int) -> Set<Int>? {
        var out = Set<Int>()
        for part in s.split(separator: ",") {
            let pieces = part.split(separator: "/")
            let step = pieces.count == 2 ? Int(pieces[1]) ?? 1 : 1
            var a = lo, b = hi
            let range = String(pieces[0])
            if range != "*" {
                let ends = range.split(separator: "-").compactMap { Int($0) }
                guard let first = ends.first else { return nil }
                a = first
                b = ends.count == 2 ? ends[1] : (pieces.count == 2 ? hi : first)
            }
            guard a >= lo, b <= hi, a <= b, step > 0 else { return nil }
            out.formUnion(stride(from: a, through: b, by: step))
        }
        return out
    }

    private func dayMatches(_ c: DateComponents) -> Bool {
        guard let m = c.month, months.contains(m), let d = c.day, let wd = c.weekday else { return false }
        let dayOK = days.contains(d), wdOK = weekdays.contains(wd - 1)
        if dayRestricted && weekdayRestricted { return dayOK || wdOK }
        return dayOK && wdOK
    }

    /// First firing strictly after `date` (forward) or strictly before it (backward).
    func fire(from date: Date, forward: Bool = true) -> Date? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let hs = hours.sorted(by: forward ? (<) : (>))
        let ms = minutes.sorted(by: forward ? (<) : (>))
        for offset in 0..<400 {
            guard let day = cal.date(byAdding: .day, value: forward ? offset : -offset, to: start) else { continue }
            guard dayMatches(cal.dateComponents([.month, .day, .weekday], from: day)) else { continue }
            for h in hs {
                for m in ms {
                    guard let t = cal.date(bySettingHour: h, minute: m, second: 0, of: day) else { continue }
                    if forward ? t > date : t < date { return t }
                }
            }
        }
        return nil
    }
}
