// Oanarina Archi Tool — GPL-3.0-or-later
// Editing time statistics (ANL-011, AutoCAD TIME): creation and last-update dates, total editing time with idle gaps
// removed, and a user elapsed timer that can be switched on, off and reset. Stored in document variables so they
// travel with the drawing: TDCREATE / TDUPDATE (Julian dates), TDINDWG / TDUSRTIMER (days), USRTIMER (1/0) and
// EDITTIMELAST (Unix time of the last recorded activity). `touch` records activity (commands call it).
import Foundation

public enum EditTime {
    /// Activity gaps longer than this (seconds) are idle time and are not counted.
    public static var idleLimit: TimeInterval = 300

    static func julian(_ d: Date) -> Double { d.timeIntervalSince1970 / 86400 + 2440587.5 }
    static func date(julian j: Double) -> Date { Date(timeIntervalSince1970: (j - 2440587.5) * 86400) }

    /// Records editing activity at `now`: adds the time since the previous activity unless it was an idle gap.
    public static func touch(_ doc: inout ArchiDocument, now: Date = Date()) {
        let t = now.timeIntervalSince1970
        if doc.variables["TDCREATE"] == nil { doc.variables["TDCREATE"] = fmt(julian(now), 8) }
        if let last = Double(doc.variables["EDITTIMELAST"] ?? ""), t > last, t - last <= idleLimit {
            let days = (t - last) / 86400
            doc.variables["TDINDWG"] = fmt((Double(doc.variables["TDINDWG"] ?? "") ?? 0) + days, 10)
            if doc.variables["USRTIMER"] != "0" { doc.variables["TDUSRTIMER"] = fmt((Double(doc.variables["TDUSRTIMER"] ?? "") ?? 0) + days, 10) }
        }
        doc.variables["EDITTIMELAST"] = fmt(t, 3)
        doc.variables["TDUPDATE"] = fmt(julian(now), 8)
    }

    public struct Report: Hashable {
        public var created: Date?, updated: Date?
        public var editing: TimeInterval, userTimer: TimeInterval
        public var timerOn: Bool
    }

    public static func report(_ doc: ArchiDocument) -> Report {
        Report(created: Double(doc.variables["TDCREATE"] ?? "").map { date(julian: $0) }, updated: Double(doc.variables["TDUPDATE"] ?? "").map { date(julian: $0) },
               editing: (Double(doc.variables["TDINDWG"] ?? "") ?? 0) * 86400, userTimer: (Double(doc.variables["TDUSRTIMER"] ?? "") ?? 0) * 86400,
               timerOn: doc.variables["USRTIMER"] != "0")
    }

    public static func setTimer(_ doc: inout ArchiDocument, on: Bool) { doc.variables["USRTIMER"] = on ? "1" : "0" }
    public static func resetTimer(_ doc: inout ArchiDocument) { doc.variables["TDUSRTIMER"] = "0" }

    /// "d days hh:mm:ss".
    public static func format(_ s: TimeInterval) -> String {
        let t = Int(s.rounded())
        let d = t / 86400, h = t % 86400 / 3600, m = t % 3600 / 60, sec = t % 60
        return (d > 0 ? "\(d) days " : "") + String(format: "%02d:%02d:%02d", h, m, sec)
    }

    static var command: CommandDef {
        CommandDef("TIME", aliases: ["EDITTIME", "DRAWINGTIME"], category: "Inquiry",
                   summary: "Shows the drawing's creation and last-update dates, total editing time (idle gaps over 5 minutes excluded) and the user elapsed timer; ON/OFF/Reset control the timer.", modifies: false) { ed in
            var d = ed.doc
            touch(&d)
            let k = try await ed.getKeyword("Option [Display/ON/OFF/Reset]", ["Display", "ON", "OFF", "Reset"], defaultValue: "Display") ?? "Display"
            switch k {
            case "ON": setTimer(&d, on: true)
            case "OFF": setTimer(&d, on: false)
            case "Reset": resetTimer(&d)
            default: break
            }
            ed.doc = d
            let r = report(d)
            let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .medium; f.locale = Locale(identifier: "en_US_POSIX")
            ed.print("Current time:             \(f.string(from: Date()))")
            ed.print("Created:                  \(r.created.map { f.string(from: $0) } ?? "—")")
            ed.print("Last updated:             \(r.updated.map { f.string(from: $0) } ?? "—")")
            ed.print("Total editing time:       \(format(r.editing))")
            ed.print("Elapsed timer (\(r.timerOn ? "on" : "off")):     \(format(r.userTimer))")
        }
    }
}
