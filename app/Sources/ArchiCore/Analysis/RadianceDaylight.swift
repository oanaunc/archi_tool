// Oanarina Archi Tool — GPL-3.0-or-later
// Climate-based daylight with Radiance (ANL-022), the validated reference engine for sDA and ASE (IES LM-83): the model
// is written as a Radiance scene (metres; plastic materials from the drawing's materials with their reflectance, glass
// with the transmissivity that gives the glazing's normal transmittance), the rooms' work-plane sensors (the same grid
// as DAYLIGHTANNUAL), a sky/ground receiver for rfluxmtx and a run script for the daylight-coefficient method
// (epw2wea, gendaymtx, rfluxmtx, dctimestep, rmtxop). After the script has run, the hourly illuminance matrices
// (total, and direct-only for ASE) are read back and sDA300/50% and ASE1000,250h computed per room over the occupied
// hours of the weather file.
import Foundation

public enum RadianceDaylight {
    public struct ExportError: Error, LocalizedError { public var message: String; public var errorDescription: String? { message } }

    /// Radiance transmissivity for a glazing transmittance at normal incidence (Radiance "glass" definition).
    public static func transmissivity(_ tn: Double) -> Double {
        let t = max(0.01, min(0.99, tn))
        return ((0.8402528435 + 0.0072522239 * t * t).squareRoot() - 0.9166530661) / 0.0036261119 / t
    }

    static func radName(_ s: String) -> String {
        let t = s.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return "m_" + String(t)
    }

    public struct Export { public var files: [String]; public var sensors: Int; public var rooms: Int; public var polygons: Int }

    /// Writes the Radiance study into `dir` (an EPW weather file is copied in when given).
    @discardableResult
    public static func write(_ doc: ArchiDocument, to dir: URL, weather: URL?, options o: ClimateDaylight.Options = ClimateDaylight.Options()) throws -> Export {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let m = doc.units.mm / 1000       // drawing units → metres
        // Materials.
        var mats = "# Materials (reflectance from the drawing's material colours)\n"
        var used: [String: String] = [:]
        func material(_ name: String) -> String {
            if let n = used[name] { return n }
            let n = radName(name)
            used[name] = n
            let mat = doc.materials.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } ?? Material.library.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            if name.lowercased().contains("glass") || (mat?.transparency ?? 0) > 0.3 {
                let tn = transmissivity(o.transmittance)
                mats += "void glass \(n)\n0\n0\n3 \(fmt(tn, 4)) \(fmt(tn, 4)) \(fmt(tn, 4))\n\n"
            } else {
                let c = mat?.color ?? RGBA(0.6, 0.6, 0.6)
                // Keep reflectances physical (0.05 … 0.85) and slightly diffuse.
                func ch(_ v: Double) -> String { fmt(max(0.05, min(0.85, v * 0.85)), 3) }
                mats += "void plastic \(n)\n0\n0\n5 \(ch(c.r)) \(ch(c.g)) \(ch(c.b)) 0 0.05\n\n"
            }
            return n
        }
        var scene = "# Scene: \(doc.info.name) (metres)\n"
        var polys = 0
        for (gi, g) in MeshBuilder.build(doc: doc).enumerated() where !["datum"].contains(g.kind) {
            let mn = material(g.kind.lowercased().contains("glass") ? "Glass" : g.material)
            let p = g.mesh.positions, ix = g.mesh.indices
            var i = 0
            while i + 2 < ix.count {
                let a = p[Int(ix[i])] * m, b = p[Int(ix[i + 1])] * m, c = p[Int(ix[i + 2])] * m
                if (b - a).cross(c - a).length > 1e-10 {
                    scene += "\(mn) polygon g\(gi)_\(i / 3)\n0\n0\n9 \(fmt(a.x, 5)) \(fmt(a.y, 5)) \(fmt(a.z, 5)) \(fmt(b.x, 5)) \(fmt(b.y, 5)) \(fmt(b.z, 5)) \(fmt(c.x, 5)) \(fmt(c.y, 5)) \(fmt(c.z, 5))\n"
                    polys += 1
                }
                i += 3
            }
        }
        // Sensors.
        var pts = "", map = "sensor,room,name,x_mm,y_mm\n"
        var n = 0, rooms = 0
        let mm = doc.units.mm
        for el in doc.elements {
            guard case .space(let sp) = el.geometry, sp.boundary.count >= 3 else { continue }
            let lev = (doc.level(el.level)?.elevation ?? 0) * mm
            let poly = sp.boundary.map { $0 * mm }
            let grid = ClimateDaylight.sensorGrid(poly, o)
            rooms += 1
            let name = (sp.number.isEmpty ? sp.name : "\(sp.number) \(sp.name)").replacingOccurrences(of: ",", with: " ")
            for q in grid {
                pts += "\(fmt(q.x / 1000, 4)) \(fmt(q.y / 1000, 4)) \(fmt((lev + o.workPlane) / 1000, 4)) 0 0 1\n"
                map += "\(n),\(el.id),\(name),\(fmt(q.x, 1)),\(fmt(q.y, 1))\n"
                n += 1
            }
        }
        guard n > 0 else { throw ExportError(message: "Radiance sensors come from rooms: add rooms (ROOM / SPACE) first.") }
        let sky = """
        #@rfluxmtx h=u u=Y
        void glow groundglow
        0
        0
        4 1 1 1 0

        groundglow source ground
        0
        0
        4 0 0 -1 180

        #@rfluxmtx h=r1 u=Y
        void glow skyglow
        0
        0
        4 1 1 1 0

        skyglow source skydome
        0
        0
        4 0 0 1 180

        """
        let north = doc.info.northAngle
        let script = """
        #!/bin/sh
        # Radiance daylight-coefficient study written by Oanarina Archi Tool. Needs Radiance 5.x on the PATH
        # (https://www.radiance-online.org). Produces total.ill and direct.ill (lux, one row per sensor, one column per hour).
        set -e
        cd "$(dirname "$0")"
        N=$(wc -l < sensors.pts | tr -d ' ')
        if [ -f weather.epw ]; then epw2wea weather.epw weather.wea; fi
        # Sky vectors: total and direct-sun-only (Reinhart MF:1 = 145 patches + ground), visible radiation, rotated for north.
        gendaymtx -m 1 -O0 -r \(fmt(-north, 3)) weather.wea > sky.smx
        gendaymtx -m 1 -O0 -d -r \(fmt(-north, 3)) weather.wea > sun.smx
        oconv materials.rad scene.rad > scene.oct
        rfluxmtx -I+ -y "$N" -ab 5 -ad 10000 -lw 1e-4 - sky.rad -i scene.oct < sensors.pts > dc.mtx
        rfluxmtx -I+ -y "$N" -ab 0 -ad 10000 -lw 1e-4 - sky.rad -i scene.oct < sensors.pts > dcd.mtx
        dctimestep dc.mtx sky.smx | rmtxop -fa -c 47.4 119.9 11.6 - > total.ill
        dctimestep dcd.mtx sun.smx | rmtxop -fa -c 47.4 119.9 11.6 - > direct.ill
        echo "Done: total.ill, direct.ill"

        """
        var files = ["materials.rad", "scene.rad", "sensors.pts", "sensors.csv", "sky.rad", "run.sh"]
        try mats.write(to: dir.appendingPathComponent("materials.rad"), atomically: true, encoding: .utf8)
        try scene.write(to: dir.appendingPathComponent("scene.rad"), atomically: true, encoding: .utf8)
        try pts.write(to: dir.appendingPathComponent("sensors.pts"), atomically: true, encoding: .utf8)
        try map.write(to: dir.appendingPathComponent("sensors.csv"), atomically: true, encoding: .utf8)
        try sky.write(to: dir.appendingPathComponent("sky.rad"), atomically: true, encoding: .utf8)
        try script.write(to: dir.appendingPathComponent("run.sh"), atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.appendingPathComponent("run.sh").path)
        if let w = weather {
            let dest = dir.appendingPathComponent("weather.epw")
            try? fm.removeItem(at: dest)
            try fm.copyItem(at: w, to: dest)
            files.append("weather.epw")
        }
        return Export(files: files, sensors: n, rooms: rooms, polygons: polys)
    }

    /// Reads a Radiance ASCII matrix (optional header up to the first blank line): rows of numbers.
    static func matrix(_ text: String) -> [[Double]] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.first?.hasPrefix("#?RADIANCE") == true, let blank = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            lines = Array(lines[(blank + 1)...])
        }
        return lines.compactMap { l -> [Double]? in
            let v = l.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Double($0) }
            return v.isEmpty ? nil : v
        }
    }

    /// Occupied flags of the weather hours (wea: "month day hour dn df" after the header; hour in local standard time).
    static func occupied(_ wea: String, first: Int, last: Int) -> [Bool] {
        wea.split(separator: "\n").compactMap { l -> Bool? in
            let v = l.split(separator: " ").compactMap { Double($0) }
            guard v.count >= 5, !l.hasPrefix("place"), !l.hasPrefix("latitude"), !l.hasPrefix("longitude") else { return nil }
            return v[2] > Double(first) && v[2] <= Double(last)
        }
    }

    /// sDA / ASE per room from the Radiance results in `dir`.
    public static func results(_ dir: URL, options o: ClimateDaylight.Options = ClimateDaylight.Options()) throws -> [ClimateDaylight.RoomResult] {
        func read(_ n: String) throws -> String {
            guard let s = try? String(contentsOf: dir.appendingPathComponent(n), encoding: .utf8) else { throw ExportError(message: "\(n) not found in \(dir.path): run run.sh with Radiance first.") }
            return s
        }
        let total = matrix(try read("total.ill")), direct = (try? read("direct.ill")).map(matrix) ?? []
        let occ = (try? read("weather.wea")).map { occupied($0, first: o.firstHour, last: o.lastHour) } ?? []
        let rows = try read("sensors.csv").split(separator: "\n").dropFirst().map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        guard total.count == rows.count else { throw ExportError(message: "total.ill has \(total.count) rows for \(rows.count) sensors.") }
        struct Acc { var name: String; var pts: [ClimateDaylight.PointResult] = [] }
        var rooms: [EntityID: Acc] = [:], order: [EntityID] = []
        for (i, r) in rows.enumerated() where r.count >= 5 {
            guard let id = Int(r[1]), let x = Double(r[3]), let y = Double(r[4]) else { continue }
            let hours = total[i]
            let occHours = hours.indices.filter { occ.isEmpty ? true : ($0 < occ.count && occ[$0]) }
            let ok = occHours.filter { hours[$0] >= o.threshold }.count
            let sun = i < direct.count ? occHours.filter { $0 < direct[i].count && direct[i][$0] >= o.aseThreshold }.count : 0
            if rooms[id] == nil { rooms[id] = Acc(name: r[2]); order.append(id) }
            rooms[id]!.pts.append(ClimateDaylight.PointResult(p: Vec2(x, y), autonomy: Double(ok) / Double(max(1, occHours.count)), sunHours: sun))
        }
        return order.map { id in
            let a = rooms[id]!, n = Double(max(1, a.pts.count))
            return ClimateDaylight.RoomResult(id: id, name: a.name, level: 0,
                                              sDA: 100 * Double(a.pts.filter { $0.autonomy >= o.fraction }.count) / n,
                                              ASE: 100 * Double(a.pts.filter { $0.sunHours > o.aseHours }.count) / n,
                                              meanAutonomy: 100 * a.pts.reduce(0) { $0 + $1.autonomy } / n, points: a.pts)
        }
    }

    static var command: CommandDef {
        CommandDef("DAYLIGHTRADIANCE", aliases: ["RADIANCEDAYLIGHT", "RADIANCEEXPORT", "SDARADIANCE"], category: "Analysis",
                   summary: "Climate-based daylight with Radiance: Export a Radiance study (scene, materials, room sensors, sky, run.sh for the daylight-coefficient method with an EPW) or Import its results as sDA300/50% and ASE1000,250h per room (IES LM-83).", modifies: false) { ed in
            let k = try await ed.getKeyword("Enter an option [Export/Import]", ["Export", "Import"], defaultValue: "Export") ?? "Export"
            let dir = try await IOCommands.path(ed, "Enter study folder")
            if k == "Export" {
                let w = try await ed.getWord("EPW weather file <none>")
                do {
                    let r = try write(ed.doc, to: dir, weather: (w?.isEmpty ?? true) ? nil : IOCommands.resolve(ed, w!))
                    ed.print("Radiance study: \(r.polygons) polygons, \(r.sensors) sensors in \(r.rooms) room(s) → \(dir.path). Run run.sh (Radiance 5), then DAYLIGHTRADIANCE Import.")
                } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
            } else {
                do {
                    let res = try results(dir)
                    for r in res { ed.print("\(r.name): sDA300/50% \(fmt(r.sDA, 1)) %, ASE1000,250h \(fmt(r.ASE, 1)) % — \(r.passesLM83 ? "meets" : "does not meet") LM-83 (\(r.points.count) points)") }
                } catch { throw CommandError.invalid((error as? LocalizedError)?.errorDescription ?? "\(error)") }
            }
        }
    }
}
