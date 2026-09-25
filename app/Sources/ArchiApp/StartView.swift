// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import ArchiCore

/// Start screen shown in new windows until the user picks a template or opens a file.
struct StartView: View {
    @ObservedObject var model: AppModel
    @State private var recents: [URL] = []

    var body: some View {
        ZStack {
            Theme.canvas.opacity(0.97).ignoresSafeArea()
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 9).fill(Theme.accent).frame(width: 46, height: 46)
                            .overlay(Image(systemName: "building.columns.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.accentText))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Oanarina Archi Tool").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
                            Text("Drafting and building design for the Mac").font(.system(size: 12)).foregroundStyle(Theme.textDim)
                        }
                    }
                    Text("START").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.textDim).padding(.top, 6)
                    VStack(spacing: 8) {
                        StartTile(symbol: "square.and.pencil", title: "New Drawing", subtitle: "Metric · millimetres") { model.newDocument(.blankMetric) }
                        StartTile(symbol: "ruler", title: "New Drawing", subtitle: "Imperial · inches") { model.newDocument(.blankImperial) }
                        StartTile(symbol: "building.2", title: "New Building", subtitle: "Levels, structural grid and sheets") { model.newDocument(.building) }
                        StartTile(symbol: "folder", title: "Open…", subtitle: ".archi projects and DXF drawings") { model.files.openPanel() }
                        StartTile(symbol: "house", title: "Sample House", subtitle: "A small house built with commands", accent: true) {
                            model.newDocument(.sample)
                            model.buildSampleHouse()
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Image(systemName: "keyboard").foregroundStyle(Theme.accent)
                        Text("Tip: just start typing — LINE, WALL, DOOR, ROOM… Space or Enter repeats the last command.")
                    }
                    .font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                }
                .frame(width: 360)
                .padding(28)
                VSeparator()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("RECENT").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.textDim)
                        Spacer()
                        if !recents.isEmpty {
                            Button("Clear") { RecentFiles.clear(); recents = [] }.buttonStyle(FlatButtonStyle(compact: true))
                        }
                    }
                    if recents.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "clock").font(.system(size: 28)).foregroundStyle(Theme.textFaint)
                            Text("No recent documents").font(Theme.font).foregroundStyle(Theme.textDim)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(recents, id: \.self) { url in RecentRow(url: url) { model.files.load(url) } }
                            }
                        }
                    }
                }
                .frame(width: 380)
                .padding(28)
            }
            .frame(height: 470)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.separator, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                IconButton(symbol: "xmark", help: "Continue with an empty drawing") { model.showStart = false; model.canvas?.focus() }.padding(10)
            }
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        }
        .onAppear { recents = RecentFiles.urls }
    }
}

private struct StartTile: View {
    let symbol: String
    let title: String
    let subtitle: String
    var accent = false
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 17)).frame(width: 30)
                    .foregroundStyle(accent ? Theme.accent : Theme.text)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(subtitle).font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(hovering ? Theme.accent : Theme.textFaint)
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Theme.hover : Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(hovering ? Theme.accent.opacity(0.6) : Theme.separator, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct RecentRow: View {
    let url: URL
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: url.pathExtension.lowercased() == "dxf" ? "doc.text" : "building.columns")
                    .foregroundStyle(Theme.accent).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(Theme.fontSmall).foregroundStyle(Theme.textDim).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                    Text(d, style: .date).font(Theme.fontSmall).foregroundStyle(Theme.textFaint)
                }
            }
            .padding(.horizontal, 8).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.hover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(url.path)
    }
}

// MARK: - Sample house

extension AppModel {
    /// Builds a small single-storey house through the command line (like a user or an agent would),
    /// falling back to direct element creation for anything a command could not produce.
    func buildSampleHouse() {
        let ed = editor
        showStart = false
        Task { @MainActor in
            @MainActor func count(_ f: (BIMGeometry) -> Bool) -> Int { ed.doc.elements.filter { f($0.geometry) }.count }
            func isWall(_ g: BIMGeometry) -> Bool { if case .wall = g { return true }; return false }
            func isOpening(_ g: BIMGeometry, _ k: OpeningKind) -> Bool { if case .opening(let o) = g { return o.kind == k }; return false }
            ed.print("Building the sample house…")
            ed.settings.objectSnap = false
            ed.pickTolerance = 150
            let script: [String] = [
                "WALL 0,0 12000,0 12000,8000 0,8000 C",
                "WALL 5000,0 5000,8000",
                "WALL 5000,4500 12000,4500",
            ]
            for l in script { await ed.run(l) }
            if count(isWall) < 4 {
                ed.print("WALL command unavailable — creating walls directly.")
                ed.transaction("Sample walls") { d in
                    let segs: [(Vec2, Vec2)] = [(Vec2(0, 0), Vec2(12000, 0)), (Vec2(12000, 0), Vec2(12000, 8000)), (Vec2(12000, 8000), Vec2(0, 8000)), (Vec2(0, 8000), Vec2(0, 0)),
                                                (Vec2(5000, 0), Vec2(5000, 8000)), (Vec2(5000, 4500), Vec2(12000, 4500))]
                    for (a, b) in segs { d.addElement(.wall(WallGeom(start: a, end: b, thickness: a.y == b.y && (a.y == 0 || a.y == 8000) || a.x == b.x && (a.x == 0 || a.x == 12000) ? 300 : 120))) }
                }
            }
            let doors: [Vec2] = [Vec2(2500, 0), Vec2(5000, 6000), Vec2(8000, 4500)]
            let windows: [Vec2] = [Vec2(0, 4000), Vec2(8500, 0), Vec2(2500, 8000), Vec2(9000, 8000), Vec2(12000, 2200), Vec2(12000, 6200)]
            for p in doors { await ed.run("DOOR \(p.x),\(p.y)") }
            for p in windows { await ed.run("WINDOW \(p.x),\(p.y)") }
            func wallAt(_ p: Vec2, _ d: ArchiDocument) -> (EntityID, WallGeom)? {
                for el in d.elements { if case .wall(let w) = el.geometry, GeometryOps.distance(point: p, segA: w.start, segB: w.end) < 1 { return (el.id, w) } }
                return nil
            }
            if count({ isOpening($0, .door) }) == 0 || count({ isOpening($0, .window) }) == 0 {
                let needDoors = count({ isOpening($0, .door) }) == 0, needWindows = count({ isOpening($0, .window) }) == 0
                ed.transaction("Sample openings") { d in
                    for (list, kind) in [(needDoors ? doors : [], OpeningKind.door), (needWindows ? windows : [], OpeningKind.window)] {
                        for p in list {
                            guard let (id, w) = wallAt(p, d) else { continue }
                            let off = (p - w.start).dot(w.direction)
                            d.addElement(.opening(OpeningGeom(kind: kind, hostWall: id, offset: off, width: kind == .door ? 900 : 1200, height: kind == .door ? 2100 : 1200, sill: kind == .door ? 0 : 900)))
                        }
                    }
                }
            }
            await ed.run("SLAB -150,-150 12150,-150 12150,8150 -150,8150 C")
            if count({ if case .slab = $0 { return true }; return false }) == 0 {
                ed.transaction("Sample slab") { $0.addElement(.slab(SlabGeom(boundary: [Vec2(-150, -150), Vec2(12150, -150), Vec2(12150, 8150), Vec2(-150, 8150)]))) }
            }
            await ed.run("ROOF -150,-150 12150,-150 12150,8150 -150,8150 C")
            if count({ if case .roof = $0 { return true }; return false }) == 0 {
                ed.transaction("Sample roof") { $0.addElement(.roof(RoofGeom(boundary: [Vec2(-150, -150), Vec2(12150, -150), Vec2(12150, 8150), Vec2(-150, 8150)], kind: .gable, pitch: 30))) }
            }
            await ed.run("ROOM Name Living 2500,4000 Name Bedroom 8500,6250 Name Kitchen 8500,2250")
            if count({ if case .space = $0 { return true }; return false }) == 0 {
                ed.transaction("Sample rooms") { d in
                    let rooms: [(String, [Vec2])] = [("Living", [Vec2(0, 0), Vec2(5000, 0), Vec2(5000, 8000), Vec2(0, 8000)]),
                                                     ("Bedroom", [Vec2(5000, 4500), Vec2(12000, 4500), Vec2(12000, 8000), Vec2(5000, 8000)]),
                                                     ("Kitchen", [Vec2(5000, 0), Vec2(12000, 0), Vec2(12000, 4500), Vec2(5000, 4500)])]
                    for (i, r) in rooms.enumerated() { d.addElement(.space(SpaceGeom(boundary: r.1, name: r.0, number: "\(101 + i)"))) }
                }
            }
            for c in ["COMPONENT Bed 8500,6600", "COMPONENT Sofa 2500,6200", "COMPONENT Table 2500,3000", "COMPONENT Kitchen 8500,600"] { await ed.run(c) }
            let dimsBefore = ed.doc.entities.count
            await ed.run("DIMLINEAR 0,0 12000,0 6000,-1500")
            await ed.run("DIMLINEAR 12000,0 12000,8000 13500,4000")
            if ed.doc.entities.count == dimsBefore {
                ed.transaction("Sample dimensions") { d in
                    d.add(.dimension(DimensionGeom(kind: .linear, points: [Vec2(0, 0), Vec2(12000, 0), Vec2(6000, -1500)], rotation: 0, style: d.currentDimStyle)), layer: "A-ANNO-DIMS")
                    d.add(.dimension(DimensionGeom(kind: .linear, points: [Vec2(12000, 0), Vec2(12000, 8000), Vec2(13500, 4000)], rotation: .pi / 2, style: d.currentDimStyle)), layer: "A-ANNO-DIMS")
                }
            }
            ed.settings.objectSnap = true
            ed.selection = []
            ed.doc.info.name = "Sample House"
            ed.isDirty = true
            ed.print("Sample house ready: \(ed.doc.elements.count) building elements. Switch to 3D (View ▸ 3D) to explore it.")
            self.revision &+= 1
            self.zoomExtents()
        }
    }
}
