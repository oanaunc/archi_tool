// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// A scripted tutorial (tutorials/*.tut): a header (title, summary) and a list of steps that the tutorial recorder plays
/// against the real app while capturing video. The format is line based; see tutorials/README.md.
///
///     title: Getting started
///     summary: The interface and the Cedar House sample.
///     ---
///     open start
///     caption "The start screen" "New drawings, templates and samples"
///     wait 2
///     type WALL 0,0 6000,0 6000,4000 ;
///     pick 3000,2000
struct TutorialScript: Equatable {
    var name: String = ""
    var title: String = ""
    var summary: String = ""
    var steps: [TutorialStep] = []

    /// A parse problem with its 1-based line number.
    struct ParseError: Error, Equatable, CustomStringConvertible {
        var line: Int
        var message: String
        var description: String { "line \(line): \(message)" }
    }

    static let fileExtension = "tut"
}

/// Where a note points.
enum TutorialAnchor: Equatable {
    case top                    // top centre of the canvas area
    case model(Double, Double)  // model coordinates on the plan
    case ui(TutorialTarget)     // a UI element
}

/// A named UI element the recorder can move the cursor to and press.
enum TutorialTarget: Equatable {
    case ribbon(String)          // ribbon button of a command (switches to its ribbon tab first)
    case ribbonTab(String)       // ribbon tab by name
    case mode(String)            // workspace mode button: 2D, 3D, Split, Sheet
    case panel(String)           // side panel tab: Properties, Layers, Levels, Browser, Materials…
    case button(String, window: String?) // any button by its label, optionally in another window (title prefix)
    case commandLine             // the command line input
    case statusBar(String)       // a status bar toggle by its label (OSNAP, ORTHO…)
}

enum TutorialStep: Equatable {
    case open(String, String?)               // start | new | imperial | building | sample NAME | file PATH
    case caption(String, String)             // lower-third title + subtitle ("" title hides it)
    case note(String, TutorialAnchor, Double)
    case type(String)                        // command tokens, each followed by Enter (Space in the app)
    case typeLine(String)                    // whole line typed, then Enter
    case enter
    case escape
    case click(TutorialTarget)
    case hover(TutorialTarget)
    case pick(Double, Double)                // canvas click at model coordinates
    case move(Double, Double)                // cursor move on the canvas
    case drag(Double, Double, Double, Double) // window/crossing selection on the plan
    case orbit(Double, Double)               // degrees, seconds
    case camera(String)                      // CAMERA name (typed)
    case style(String)                       // VSCURRENT style (typed)
    case zoom(String)                        // extents | in | out | window x1,y1 x2,y2 | a factor
    case wait(Double)
    case speed(Double)                       // typing speed, characters per second
    case js(String)                          // appends a line to the script console editor (typed)
    case jsClear
    case run(String)                         // silent command line (setup, not shown as typing)
    case runFile(String)                     // silent command lines of a .scr file next to the scripts (shared setup)
    case closeWindow(String)                 // closes another window by title prefix
    case panels(Bool)                        // show / hide the side panels
}

extension TutorialScript {
    /// Splits a line into words; "double quoted" words keep spaces (\" and \\ escape).
    static func words(_ s: String) -> [String] {
        var out: [String] = [], cur = "", inQuote = false, had = false, esc = false
        for ch in s {
            if esc { cur.append(ch == "n" ? "\n" : ch); esc = false; continue }
            if inQuote && ch == "\\" { esc = true; continue }
            if ch == "\"" { inQuote.toggle(); had = true; continue }
            if (ch == " " || ch == "\t") && !inQuote {
                if had || !cur.isEmpty { out.append(cur) }
                cur = ""; had = false; continue
            }
            cur.append(ch)
        }
        if had || !cur.isEmpty { out.append(cur) }
        return out
    }

    static func point(_ s: String) -> (Double, Double)? {
        let p = s.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard p.count == 2, let x = p[0], let y = p[1], x.isFinite, y.isFinite else { return nil }
        return (x, y)
    }

    static func seconds(_ s: String) -> Double? {
        var t = s.lowercased()
        if t.hasSuffix("s") { t.removeLast() }
        guard let v = Double(t), v >= 0, v <= 600 else { return nil }
        return v
    }

    static func target(_ w: [String]) -> TutorialTarget? {
        if w.first?.lowercased() == "commandline" { return .commandLine }
        guard let k = w.first?.lowercased(), w.count >= 2 else { return nil }
        let v = w[1]
        switch k {
        case "ribbon": return .ribbon(v.uppercased())
        case "tab": return .ribbonTab(v)
        case "mode": return ["2D", "3D", "SPLIT", "SHEET"].contains(v.uppercased()) ? .mode(v.uppercased() == "SPLIT" ? "Split" : v.uppercased() == "SHEET" ? "Sheet" : v.uppercased()) : nil
        case "panel": return .panel(v)
        case "button":
            if w.count >= 4, w[2].lowercased() == "in" { return .button(v, window: w[3]) }
            return .button(v, window: nil)
        case "start": return .button(v, window: nil)
        case "status": return .statusBar(v)
        default: return nil
        }
    }

    /// Parses a .tut script.
    static func parse(_ text: String, name: String = "") throws -> TutorialScript {
        var s = TutorialScript(name: name)
        var inBody = false
        for (i, raw) in text.components(separatedBy: .newlines).enumerated() {
            let n = i + 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if !inBody {
                if line == "---" { inBody = true; continue }
                if let c = line.firstIndex(of: ":"), !line.contains(" ") || line[..<c].allSatisfy({ $0.isLetter }) {
                    let key = line[..<c].lowercased(), value = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
                    switch key {
                    case "title": s.title = value; continue
                    case "summary": s.summary = value; continue
                    default: break
                    }
                }
                inBody = true
            }
            let w = words(line)
            guard let verb = w.first?.lowercased() else { continue }
            let rest = w.dropFirst().map { $0 }
            // Command text keeps the original spelling (quotes included) after the verb.
            let tail: String = {
                guard let r = line.range(of: w[0]) else { return "" }
                return String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }()
            func fail(_ m: String) -> ParseError { ParseError(line: n, message: m) }
            switch verb {
            case "open":
                guard let k = rest.first?.lowercased(), ["start", "new", "imperial", "building", "sample", "file"].contains(k) else { throw fail("open start|new|imperial|building|sample NAME|file PATH") }
                if k == "sample" || k == "file" {
                    guard rest.count >= 2 else { throw fail("open \(k) needs a name") }
                    s.steps.append(.open(k, rest[1]))
                } else { s.steps.append(.open(k, nil)) }
            case "caption":
                if rest.first?.lowercased() == "off" || rest.isEmpty { s.steps.append(.caption("", "")) }
                else { s.steps.append(.caption(rest[0], rest.count > 1 ? rest[1] : "")) }
            case "note":
                guard let text = rest.first else { throw fail("note \"text\" [at x,y | at ribbon WALL | top] [for N]") }
                var anchor = TutorialAnchor.top, dur = 3.5
                var j = 1
                while j < rest.count {
                    let k = rest[j].lowercased()
                    if k == "for", j + 1 < rest.count, let d = seconds(rest[j + 1]) { dur = d; j += 2; continue }
                    if k == "top" { anchor = .top; j += 1; continue }
                    if k == "at", j + 1 < rest.count {
                        if let p = point(rest[j + 1]) { anchor = .model(p.0, p.1); j += 2; continue }
                        if rest[j + 1].lowercased() == "commandline" { anchor = .ui(.commandLine); j += 2; continue }
                        if j + 2 < rest.count, let t = target([rest[j + 1], rest[j + 2]]) { anchor = .ui(t); j += 3; continue }
                    }
                    throw fail("unexpected \"\(rest[j])\" in note")
                }
                s.steps.append(.note(text, anchor, dur))
            case "type":
                guard !tail.isEmpty else { throw fail("type needs command text") }
                s.steps.append(.type(tail))
            case "typeline":
                guard !tail.isEmpty else { throw fail("typeline needs command text") }
                s.steps.append(.typeLine(tail))
            case "enter": s.steps.append(.enter)
            case "escape", "esc": s.steps.append(.escape)
            case "click", "hover":
                guard let t = target(rest) else { throw fail("\(verb) ribbon CMD | tab NAME | mode 2D|3D|Split|Sheet | panel NAME | button \"Label\" [in \"Window\"] | start \"Label\" | status NAME | commandline") }
                s.steps.append(verb == "click" ? .click(t) : .hover(t))
            case "pick", "move":
                guard rest.count == 1, let p = point(rest[0]) else { throw fail("\(verb) x,y (model coordinates)") }
                s.steps.append(verb == "pick" ? .pick(p.0, p.1) : .move(p.0, p.1))
            case "drag":
                guard rest.count == 2, let a = point(rest[0]), let b = point(rest[1]) else { throw fail("drag x1,y1 x2,y2") }
                s.steps.append(.drag(a.0, a.1, b.0, b.1))
            case "orbit":
                guard let d = rest.first.flatMap(Double.init), abs(d) <= 720 else { throw fail("orbit DEGREES [SECONDS]") }
                let t = rest.count > 1 ? seconds(rest[1]) : 3
                guard let t, t > 0 else { throw fail("orbit duration must be positive") }
                s.steps.append(.orbit(d, t))
            case "camera":
                guard !tail.isEmpty else { throw fail("camera NAME") }
                s.steps.append(.camera(rest.joined(separator: " ")))
            case "style", "vs":
                guard !tail.isEmpty else { throw fail("style NAME") }
                s.steps.append(.style(rest.joined(separator: " ")))
            case "zoom":
                guard let k = rest.first?.lowercased() else { throw fail("zoom extents|in|out|window x1,y1 x2,y2|FACTOR") }
                if k == "window" {
                    guard rest.count == 3, point(rest[1]) != nil, point(rest[2]) != nil else { throw fail("zoom window x1,y1 x2,y2") }
                    s.steps.append(.zoom("window " + rest[1] + " " + rest[2]))
                } else if ["extents", "in", "out"].contains(k) || Double(k).map({ $0 > 0 }) == true {
                    s.steps.append(.zoom(k))
                } else { throw fail("zoom extents|in|out|window x1,y1 x2,y2|FACTOR") }
            case "wait", "pause":
                guard rest.count == 1, let d = seconds(rest[0]) else { throw fail("wait SECONDS") }
                s.steps.append(.wait(d))
            case "speed":
                guard rest.count == 1, let v = Double(rest[0]), v >= 1, v <= 200 else { throw fail("speed CHARS_PER_SECOND (1–200)") }
                s.steps.append(.speed(v))
            case "js":
                // The code is taken verbatim (quotes included), keeping the indentation after "js ".
                let code: String = {
                    guard let r = raw.range(of: w[0]) else { return tail }
                    var c = String(raw[r.upperBound...])
                    if c.hasPrefix(" ") { c.removeFirst() }
                    return c
                }()
                s.steps.append(tail.lowercased() == "clear" ? .jsClear : .js(code))
            case "run":
                guard !tail.isEmpty else { throw fail("run needs a command line") }
                s.steps.append(.run(tail))
            case "runfile":
                guard let f = rest.first else { throw fail("runfile FILE.scr") }
                s.steps.append(.runFile(f))
            case "close":
                guard let t = rest.first else { throw fail("close \"Window title\"") }
                s.steps.append(.closeWindow(t))
            case "panels":
                guard let v = rest.first?.lowercased(), v == "on" || v == "off" else { throw fail("panels on|off") }
                s.steps.append(.panels(v == "on"))
            default:
                throw fail("unknown step \"\(w[0])\"")
            }
        }
        if s.title.isEmpty { s.title = name }
        return s
    }

    /// Command tokens as the recorder types them: quoted words are typed without their quotes (as the user types text at
    /// a text prompt), ";" is a bare Enter.
    static func typedTokens(_ line: String) -> [String] {
        words(line).map { $0 == ";" ? "" : $0 }
    }

    /// Rough playing time in seconds (used by the dry run report and the self-test); command execution time is excluded.
    func estimatedSeconds(charsPerSecond: Double = 14) -> Double {
        var t = TutorialTiming.intro + TutorialTiming.outro
        var cps = charsPerSecond
        for st in steps {
            switch st {
            case .open: t += 1.2
            case .caption(let a, _): t += a.isEmpty ? 0.2 : 0.6
            case .note: t += 0.3
            case .type(let l):
                let toks = TutorialScript.typedTokens(l)
                for tok in toks { t += Double(tok.count) * 1.02 / cps + 0.19 + TutorialTiming.betweenInputs }
                t += TutorialTiming.afterEnter - TutorialTiming.betweenInputs
            case .typeLine(let l): t += Double(l.count) / cps + TutorialTiming.afterEnter
            case .enter, .escape: t += TutorialTiming.afterEnter
            case .click, .hover, .pick, .move: t += 1.1
            case .drag: t += 1.8
            case .orbit(_, let s): t += s
            case .camera(let n): t += Double(7 + n.count) / cps + 2 * TutorialTiming.afterEnter + 0.8
            case .style(let n): t += Double(10 + n.count) / cps + 2 * TutorialTiming.afterEnter
            case .zoom: t += 0.8
            case .wait(let s): t += s
            case .speed(let v): cps = v
            case .js(let l): t += Double(l.count + 1) / cps
            case .jsClear, .run, .runFile, .closeWindow, .panels: t += 0.1
            }
        }
        return t
    }
}

enum TutorialTiming {
    static let fps = 30
    static let intro = 2.6
    static let outro = 2.4
    static let afterEnter = 0.45
    /// Pause after answering a prompt while the command goes on.
    static let betweenInputs = 0.22
}
