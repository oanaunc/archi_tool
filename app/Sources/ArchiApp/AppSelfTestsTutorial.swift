// Oanarina Archi Tool — GPL-3.0-or-later
import AppKit
import AVFoundation
import ArchiCore

/// Checks of the tutorial recorder: script parsing, bundled scripts, overlay drawing, window capture and MP4 writing.
@MainActor
extension AppSelfTests {
    static func tutorialChecks(_ check: (Bool, String) -> Void) {
        // Command and menu entry.
        check(CommandRegistry.shared.lookup("TUTORIALRECORD") != nil, "TUTORIALRECORD is registered")
        check(CommandCatalog.coverageMenus.flatMap(\.1).contains { $0.names.contains("TUTORIALRECORD") }, "TUTORIALRECORD has a menu entry")

        // Parsing.
        let text = """
        # sample
        title: Walls
        summary: Walls and doors
        ---
        open new
        caption "Walls" "Thickness and height"
        type WALL Thickness 300 0,0 6000,0 ;
        typeline LINE 0,0 1000,0  
        type TEXT 0,0 250 0 "Living room"
        click ribbon wall
        click mode 3D
        click panel Layers
        click button "Render" in "Render"
        pick 3000,0
        drag 0,0 100,100
        note "Pick the wall" at 3000,0 for 2
        note "Ribbon" at ribbon WALL
        orbit 90 4
        camera Front
        style Realistic
        zoom window 0,0 6000,4000
        wait 1.5
        js archi.run("LINE 0,0 1,1 ")
        run LEVEL New Upper 3000 3000
        """
        do {
            let s = try TutorialScript.parse(text, name: "04-walls")
            check(s.title == "Walls" && s.summary == "Walls and doors" && s.steps.count == 20, "tutorial script header and \(s.steps.count) steps")
            check(s.steps[0] == .open("new", nil) && s.steps[1] == .caption("Walls", "Thickness and height"), "open and caption steps")
            check(s.steps[2] == .type("WALL Thickness 300 0,0 6000,0 ;"), "type step keeps the command text")
            check(TutorialScript.typedTokens("WALL Thickness 300 0,0 6000,0 ;") == ["WALL", "Thickness", "300", "0,0", "6000,0", ""], "typed tokens with Enter")
            check(TutorialScript.typedTokens("TEXT 0,0 250 0 \"Living room\"").last == "Living room", "quoted text is typed without quotes")
            check(s.steps[5] == .click(.ribbon("WALL")) && s.steps[6] == .click(.mode("3D")) && s.steps[7] == .click(.panel("Layers")), "click targets")
            check(s.steps[8] == .click(.button("Render", window: "Render")), "button in another window")
            check(s.steps[9] == .pick(3000, 0) && s.steps[10] == .drag(0, 0, 100, 100), "pick and drag")
            check(s.steps[11] == .note("Pick the wall", .model(3000, 0), 2) && s.steps[12] == .note("Ribbon", .ui(.ribbon("WALL")), 3.5), "notes with anchors")
            check(s.steps[13] == .orbit(90, 4) && s.steps[14] == .camera("Front") && s.steps[15] == .style("Realistic"), "orbit, camera, style")
            check(s.steps[16] == .zoom("window 0,0 6000,4000") && s.steps[17] == .wait(1.5), "zoom window and wait")
            check(s.steps[18] == .js("archi.run(\"LINE 0,0 1,1 \")") && s.steps[19] == .run("LEVEL New Upper 3000 3000"), "js and run steps")
            let est = s.estimatedSeconds()
            check(est > 20 && est < 90, "estimated duration \(Int(est)) s")
        } catch { check(false, "tutorial script parses: \(error)") }
        for bad in ["---\nfly away", "---\npick 1,2,3", "---\nwait forever", "---\nclick mode 4D", "---\nopen sample"] {
            var failed = false
            do { _ = try TutorialScript.parse(bad) } catch let e as TutorialScript.ParseError { failed = e.line == 2 } catch {}
            check(failed, "tutorial parse error with line number: \(bad.split(separator: "\n").last ?? "")")
        }
        check(TutorialLaunch.filter(["--record-tutorials", "/tmp/x", "a.archi", "--only", "01", "--dry-run", "-c", "ZOOM E"]) == ["a.archi", "-c", "ZOOM E"], "recorder launch flags are not opened as files")
        let o = TutorialLaunch.options(["app", "--record-tutorials", "/tmp/v", "--only", "01", "--only", "02", "--dry-run", "--tutorial-scale", "1"])
        check(o?.outputDir.path == "/tmp/v" && o?.only == ["01", "02"] && o?.dryRun == true && o?.scale == 1 && o?.quitWhenDone == true, "recorder launch options")
        check(TutorialLaunch.options(["app", "x.archi"]) == nil, "no recorder without the flag")
        check(TutorialRecorder.matches("01-getting-started", ["01"]) && !TutorialRecorder.matches("02-command-line", ["01"]) && TutorialRecorder.matches("x", []), "tutorial name filter")
        check(TutorialRecorder.ribbonTitles("WALL").contains("Wall"), "ribbon title of WALL")

        // Bundled scripts parse, use known commands and fit 45–120 s.
        let urls = TutorialRecorder.scriptURLs(source: nil)
        if !urls.isEmpty {
            check(urls.count >= 12, "\(urls.count) tutorial scripts bundled")
            for u in urls {
                do {
                    let s = try TutorialRecorder.load(u)
                    let est = s.estimatedSeconds()
                    check(est >= 40 && est <= 150, "\(s.name) lasts about \(Int(est)) s")
                    var unknown: [String] = []
                    for st in s.steps {
                        let line: String
                        switch st { case .type(let l), .typeLine(let l), .run(let l): line = l; default: continue }
                        guard let first = TutorialScript.typedTokens(line).first, !first.isEmpty, first.first?.isLetter == true else { continue }
                        // Only lines that start a command: the first word must be a command or alias.
                        // Snap overrides and point modifiers answer a running command's prompt.
                        let modifiers: Set<String> = ["END", "MID", "CEN", "GCEN", "INT", "EXT", "PER", "TAN", "NEA", "NON", "QUA", "NOD", "INS", "APP", "PAR", "FROM", "M2P", "TT", "MTP"]
                        if CommandRegistry.shared.lookup(first) == nil && first == first.uppercased() && first.count > 1 && !modifiers.contains(first) { unknown.append(first) }
                    }
                    check(unknown.isEmpty, "\(s.name) uses registered commands\(unknown.isEmpty ? "" : ": " + unknown.joined(separator: ", "))")
                } catch { check(false, "\(u.lastPathComponent) parses: \(error)") }
            }
        }

        // Overlay drawing (captions, pill, cursor, notes, cards) changes pixels.
        var ov = TutorialOverlay()
        ov.size = CGSize(width: 320, height: 200)
        ov.captionBaseline = 20
        ov.time = 5
        ov.caption("Walls", "Thickness")
        ov.time = 6
        ov.cursorVisible = true; ov.cursor = CGPoint(x: 160, y: 100)
        ov.pill = "WALL"; ov.pillTime = 5.5
        ov.click(at: CGPoint(x: 100, y: 100))
        ov.time = 6.2
        if let ctx = CGContext(data: nil, width: 320, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.setFillColor(CGColor(gray: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
            ov.draw(in: ctx)
            let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
            var changed = 0
            for i in stride(from: 0, to: 320 * 200 * 4, by: 4) where abs(Int(p[i]) - 128) > 6 { changed += 1 }
            check(changed > 2000, "overlay draws captions, pill and cursor (\(changed) px)")
        } else { check(false, "overlay context") }

        // Capture of an (off-screen) window and a short MP4.
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 160, height: 100))
        v.wantsLayer = true; v.layer?.backgroundColor = NSColor.systemYellow.cgColor
        w.contentView = v
        let layers = TutorialCapture.layers(main: w, includeOthers: false)
        check(layers.count == 1 && layers[0].image.width >= 160, "window capture (\(layers.first?.image.width ?? 0) px)")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archi-tutorial-selftest.mp4")
        do {
            let wr = try TutorialVideoWriter(url: url, width: 160, height: 100)
            for i in 0..<15 {
                try wr.append { ctx in
                    ctx.setFillColor(CGColor(red: CGFloat(i) / 15, green: 0.5, blue: 0.2, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
                    for l in layers { ctx.draw(l.image, in: CGRect(x: 10, y: 10, width: 80, height: 50)) }
                }
            }
            let sem = DispatchSemaphore(value: 0)
            var ok = false
            Task.detached { do { try await wr.finish(); ok = true } catch {}; sem.signal() }
            // The main actor is blocked here, so pump the run loop until the writer finishes.
            let deadline = Date().addingTimeInterval(10)
            while sem.wait(timeout: .now()) == .timedOut && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? 0
            check(ok && size > 500, "MP4 written (\(size) bytes)")
            let asset = AVURLAsset(url: url)
            let secs = CMTimeGetSeconds(asset.duration)
            check(abs(secs - 0.5) < 0.05, "MP4 lasts 15 frames at 30 fps (\(secs) s)")
            check(asset.tracks(withMediaType: .video).first.map { $0.naturalSize == CGSize(width: 160, height: 100) } == true, "MP4 frame size")
            try? FileManager.default.removeItem(at: url)
        } catch { check(false, "MP4 writer: \(error.localizedDescription)") }
    }
}
