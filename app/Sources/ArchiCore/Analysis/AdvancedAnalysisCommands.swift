// Oanarina Archi Tool — GPL-3.0-or-later
// Commands for climate-based daylight, wind studies, generative design, sketch-to-model and editing time.
import Foundation

public enum AdvancedAnalysisCommands {
    public static var all: [CommandDef] { [daylightAnnual, cfdExport, windResults, genDesign, sketchToWalls, EditTime.command, ClashManager.command] }

    static func fail(_ e: Error) -> CommandError { CommandError.invalid((e as? LocalizedError)?.errorDescription ?? "\(e)") }

    @MainActor static func climate(_ ed: Editor, _ path: String?) throws -> HourlyClimate {
        if let p = path, !p.isEmpty {
            do { return try HourlyClimate.parseEPW(FileImport.readText(IOCommands.resolve(ed, p))) } catch { throw fail(error) }
        }
        let tz = Double(ed.doc.variable("UTCOFFSET") ?? "") ?? (ed.doc.info.longitude / 15).rounded()
        return HourlyClimate.clearSky(latitude: ed.doc.info.latitude, longitude: ed.doc.info.longitude, timeZone: tz)
    }

    static var daylightAnnual: CommandDef {
        CommandDef("DAYLIGHTANNUAL", aliases: ["SDA", "ASE", "CLIMATEDAYLIGHT", "LM83"], category: "Analysis",
                   summary: "Climate-based daylight per room from an EPW weather file (or a clear-sky year): spatial daylight autonomy sDA300/50% and annual sunlight exposure ASE1000,250h (IES LM-83), optionally drawing the work-plane grid coloured by autonomy.") { ed in
            let path = try await ed.getWord("EPW weather file <clear-sky year>")
            let c = try climate(ed, path)
            var o = ClimateDaylight.Options()
            o.gridSpacing = try await ed.getReal("Grid spacing mm <600>", defaultValue: 600).value ?? 600
            let draw = try await ed.getYesNo("Draw the grid results?", defaultValue: false)
            let r = ClimateDaylight.analyse(ed.doc, climate: c, options: o)
            guard !r.isEmpty else { throw CommandError.invalid("The model has no rooms.") }
            ed.print("Climate: \(c.city) (\(fmt(c.latitude, 2)), \(fmt(c.longitude, 2))), \(c.hours.count) hours.")
            for x in r {
                ed.print("\(x.name): sDA300/50% \(fmt(x.sDA, 1)) %, ASE1000,250h \(fmt(x.ASE, 1)) %, mean autonomy \(fmt(x.meanAutonomy, 1)) % (\(x.points.count) points)\(x.passesLM83 ? "" : " — below LM-83 targets")")
            }
            guard draw else { return }
            var d = ed.doc
            d.ensureLayer("DAYLIGHT-GRID")
            var ids: [EntityID] = []
            for x in r {
                for p in x.points {
                    let t = p.autonomy
                    let col = ColorRef.rgb(UInt8(255 * min(1, 2 * (1 - t))), UInt8(255 * min(1, 2 * t)), 40)
                    ids.append(d.add(Entity(layer: "DAYLIGHT-GRID", color: col, geometry: .point(p.p), props: ["autonomy": fmt(t * 100, 1), "sunHours": "\(p.sunHours)", "room": "\(x.id)"])))
                }
                if let i = d.elementIndex(x.id) { d.elements[i].props["sDA300"] = fmt(x.sDA, 1); d.elements[i].props["ASE1000"] = fmt(x.ASE, 1) }
            }
            ed.doc = d
            ed.print("Drew \(ids.count) grid points on DAYLIGHT-GRID.")
        }
    }

    static var cfdExport: CommandDef {
        CommandDef("CFDEXPORT", aliases: ["WINDCASE", "OPENFOAMOUT", "WINDSTUDY"], category: "Analysis",
                   summary: "Writes an OpenFOAM wind-study case (simpleFoam, atmospheric boundary layer inlet, snappyHexMesh around the building, pedestrian-level sampling) for the given wind speed and direction.", modifies: false) { ed in
            let dir = try await IOCommands.path(ed, "Enter case folder")
            var o = WindStudy.Options.from(ed.doc)
            o.speed = try await ed.getReal("Wind speed m/s at 10 m <\(fmt(o.speed, 1))>", defaultValue: o.speed).value ?? o.speed
            o.direction = try await ed.getReal("Wind from (degrees clockwise from north) <\(fmt(o.direction, 0))>", defaultValue: o.direction).value ?? o.direction
            o.roughness = try await ed.getReal("Terrain roughness z0 m <\(fmt(o.roughness, 2))>", defaultValue: o.roughness).value ?? o.roughness
            let files: [String]
            do { files = try WindStudy.writeCase(ed.doc, to: dir, options: o) } catch { throw fail(error) }
            ed.doc.setVariable("WINDSPEED", fmt(o.speed, 3)); ed.doc.setVariable("WINDDIRECTION", fmt(o.direction, 3)); ed.doc.setVariable("WINDROUGHNESS", fmt(o.roughness, 4))
            ed.print("Wrote \(files.count) case files to \(dir.path); run ./Allrun in OpenFOAM, then WINDRESULTS.")
        }
    }

    static var windResults: CommandDef {
        CommandDef("WINDRESULTS", aliases: ["CFDRESULTS", "WINDIMPORT"], category: "Analysis",
                   summary: "Imports an OpenFOAM pedestrian-level velocity sample (raw x y z Ux Uy Uz) as wind arrows coloured by speed with Lawson comfort classes (the case's wind direction is taken from WINDDIRECTION).") { ed in
            let url = try await IOCommands.path(ed, "Enter sample file (postProcessing/…/U_zPedestrian.raw)")
            let text: String
            do { text = try FileImport.readText(url) } catch { throw fail(error) }
            let s = WindStudy.parseSamples(text)
            guard !s.isEmpty else { throw CommandError.invalid("No samples in \(url.lastPathComponent).") }
            let spacing = try await ed.getReal("Arrow spacing m <2>", defaultValue: 2).value ?? 2
            let arrows = WindStudy.arrows(s, doc: ed.doc, options: WindStudy.Options.from(ed.doc), spacing: spacing)
            var d = ed.doc
            d.ensureLayer("WIND")
            for e in arrows { d.add(e) }
            ed.doc = d
            var classes: [String: Int] = [:]
            for x in s { classes[WindStudy.comfortClass(x.speed), default: 0] += 1 }
            ed.print("\(s.count) samples, max \(fmt(s.map(\.speed).max() ?? 0, 2)) m/s: " + classes.sorted { $0.key < $1.key }.map { "\($0.key) \(fmt(100 * Double($0.value) / Double(s.count), 0)) %" }.joined(separator: ", "))
        }
    }

    static var genDesign: CommandDef {
        CommandDef("GENDESIGN", aliases: ["GENERATIVEDESIGN", "OPTIMIZELAYOUT", "LAYOUTOPT"], category: "Architecture",
                   summary: "Generative design: optimises floor layouts for a room programme and gross area with a genetic algorithm (daylight, proportions, adjacencies, orientation, compactness); lists the Pareto-optimal designs and builds the chosen one after confirmation.") { ed in
            guard let text = try await ed.getString("Room programme (name area m², …)"), !text.isEmpty else { return }
            let rooms = PlanGenerator.parseBrief(text)
            guard !rooms.isEmpty else { throw CommandError.invalid("No rooms understood: write e.g. Living 25, Kitchen 12, Bath 6.") }
            let adj = GenerativeDesign.parseAdjacency(try await ed.getString("Must be adjacent (Kitchen-Living, …) <none>") ?? "")
            let facing = GenerativeDesign.parseFacing(try await ed.getString("Facing (Living:S, …) <none>") ?? "")
            let u = ed.doc.units.mm
            let total = rooms.reduce(0) { $0 + $1.area }
            let area = try await ed.getReal("Gross floor area m² <\(fmt(total, 1))>", defaultValue: total).value ?? total
            let origin = try await ed.getPoint("Lower-left corner <0,0>").point ?? .zero
            var o = GenerativeDesign.Options()
            o.northAngle = ed.doc.info.northAngle
            o.seed = UInt64(max(1, Int(ed.doc.variable("GENSEED") ?? "") ?? 1))
            let designs = GenerativeDesign.run(GenerativeDesign.Brief(rooms: rooms, adjacent: adj, facing: facing), area: area * 1_000_000 / (u * u), origin: origin, unitMM: u, options: o)
            guard !designs.isEmpty else { throw CommandError.invalid("No layout found.") }
            for (i, d) in designs.prefix(8).enumerated() {
                let ob = d.objectives
                ed.print("Design \(i + 1): score \(fmt(d.score, 2)) — \(fmt(d.width * u / 1000, 2)) × \(fmt(d.depth * u / 1000, 2)) m; no daylight \(Int(ob.daylight)), proportions \(fmt(ob.proportion, 2)), adjacency misses \(Int(ob.adjacency)), orientation misses \(Int(ob.orientation)), compactness \(fmt(ob.compactness, 3))")
            }
            let k = try await ed.getInteger("Design to build <1>", defaultValue: 1) ?? 1
            guard k >= 1, k <= min(designs.count, 8) else { throw CommandError.invalid("No design \(k).") }
            guard try await ed.getYesNo("Build design \(k) (\(designs[k - 1].option.rooms.count) rooms)?", defaultValue: true) else { return }
            var d = ed.doc
            let h = d.level(d.currentLevel)?.height ?? 3000 / u
            let r = PlanGenerator.build(designs[k - 1].option, into: &d, level: d.currentLevel, exterior: 300 / u, interior: 100 / u, height: h, unitMM: u)
            ed.doc = d
            ed.selection = Set(r.walls + r.rooms + r.doors + r.windows)
            ed.print("Built \(r.rooms.count) rooms, \(r.walls.count) walls, \(r.doors.count) doors, \(r.windows.count) windows.")
        }
    }

    static var sketchToWalls: CommandDef {
        CommandDef("SKETCHTOWALLS", aliases: ["IMAGETOWALLS", "TRACEWALLS", "PHOTOTOMODEL"], category: "Architecture",
                   summary: "Converts a scanned or photographed plan image (PNG/BMP/PGM) into walls: dark strokes within a thickness range become wall centre lines at a given scale; asks for confirmation before creating them (one undo step).") { ed in
            let url = try await IOCommands.path(ed, "Enter plan image (PNG/BMP/PGM)")
            let img: RasterImage
            do { img = try RasterImage.decode(Data(contentsOf: url)) } catch { throw fail(error) }
            var o = SketchToModel.Options()
            let mmPerPx = try await ed.getReal("Millimetres per pixel <20>", defaultValue: 20).value ?? 20
            o.scale = mmPerPx / ed.doc.units.mm
            o.origin = try await ed.getPoint("Lower-left corner <0,0>").point ?? .zero
            let fixed = try await ed.getReal("Wall thickness mm <measured>", defaultValue: 0).value ?? 0
            o.wallThickness = fixed / ed.doc.units.mm
            o.maxThickness = max(3, Int(600 / mmPerPx))
            o.minThickness = max(2, Int(80 / mmPerPx))
            o.minLength = max(o.maxThickness + 2, Int(400 / mmPerPx))
            let walls = SketchToModel.trace(img, options: o)
            guard !walls.isEmpty else { ed.print("No walls found in \(img.width)×\(img.height) px."); return }
            let len = walls.reduce(0) { $0 + $1.length } * ed.doc.units.mm / 1000
            guard try await ed.getYesNo("Create \(walls.count) walls (\(fmt(len, 1)) m)?", defaultValue: true) else { return }
            var d = ed.doc
            let h = d.level(d.currentLevel)?.height ?? 3000 / d.units.mm
            let ids = SketchToModel.build(walls, into: &d, level: d.currentLevel, height: h)
            ed.doc = d
            ed.selection = Set(ids)
            ed.print("Created \(ids.count) walls from \(url.lastPathComponent).")
        }
    }
}
