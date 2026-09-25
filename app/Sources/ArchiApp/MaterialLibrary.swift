// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import AppKit
import SceneKit
import ArchiCore

// MARK: - Library content

/// A library material with its category. Pattern textures are generated procedurally (no third-party images),
/// written once to Application Support, and referenced by absolute path from the material.
struct LibraryMaterial: Identifiable, Hashable {
    enum Pattern: String { case none, brick, tiles, planks, stone, grid }
    var id: String { material.name }
    var category: String
    var material: ArchiCore.Material
    var pattern: Pattern = .none
}

enum MaterialLibrary {
    static let categories = ["All", "In Drawing", "Masonry", "Concrete & Stone", "Wood", "Metal", "Glass", "Finishes", "Roofing", "Site"]

    static let items: [LibraryMaterial] = {
        func m(_ cat: String, _ name: String, _ hex: String, r: Double, metal: Double = 0, t: Double = 0, cut: String = "SOLID", _ p: LibraryMaterial.Pattern = .none, scale: Double = 1000) -> LibraryMaterial {
            LibraryMaterial(category: cat, material: Material(name: name, color: RGBA(hex: hex), roughness: r, metalness: metal, transparency: t, textureScale: scale, cutPattern: cut), pattern: p)
        }
        var list: [LibraryMaterial] = [
            m("Masonry", "Brick Red", "9E4A36", r: 0.85, cut: "ANSI31", .brick),
            m("Masonry", "Brick Yellow", "C9A56A", r: 0.85, cut: "ANSI31", .brick),
            m("Masonry", "Brick White Painted", "EDEBE6", r: 0.8, cut: "ANSI31", .brick),
            m("Masonry", "Concrete Block", "A7A7A2", r: 0.9, cut: "ANSI31", .brick, scale: 1600),
            m("Concrete & Stone", "Concrete Smooth", "B9B8B3", r: 0.75, cut: "AR-CONC"),
            m("Concrete & Stone", "Concrete Board-Formed", "A9A8A2", r: 0.9, cut: "AR-CONC", .planks, scale: 1200),
            m("Concrete & Stone", "Limestone", "D8CDB3", r: 0.8, cut: "AR-SAND", .stone, scale: 1500),
            m("Concrete & Stone", "Granite Dark", "4B4B4E", r: 0.35, cut: "AR-SAND"),
            m("Concrete & Stone", "Marble White", "EEEDEA", r: 0.15, cut: "AR-SAND", .stone, scale: 1200),
            m("Concrete & Stone", "Terrazzo", "CFC9BF", r: 0.3, cut: "AR-CONC"),
            m("Wood", "Oak", "B08A5B", r: 0.55, cut: "ANSI32", .planks, scale: 900),
            m("Wood", "Walnut", "5E4130", r: 0.5, cut: "ANSI32", .planks, scale: 900),
            m("Wood", "Pine", "D2B48C", r: 0.6, cut: "ANSI32", .planks, scale: 900),
            m("Wood", "Larch Cladding", "9C7A57", r: 0.7, cut: "ANSI32", .planks, scale: 1100),
            m("Wood", "Plywood", "D6BC8F", r: 0.6, cut: "ANSI32"),
            m("Metal", "Stainless Steel", "C2C5C9", r: 0.25, metal: 1, cut: "ANSI37"),
            m("Metal", "Brushed Aluminium", "B7BBC0", r: 0.4, metal: 1),
            m("Metal", "Corten", "8A4B2A", r: 0.8, metal: 0.4),
            m("Metal", "Copper", "B87333", r: 0.35, metal: 1),
            m("Metal", "Zinc", "8E9398", r: 0.5, metal: 0.9),
            m("Metal", "Black Steel", "2A2B2D", r: 0.45, metal: 1, cut: "ANSI37"),
            m("Glass", "Clear Glass", "A9CBD9", r: 0.03, t: 0.8),
            m("Glass", "Tinted Glass", "5E7A86", r: 0.05, t: 0.6),
            m("Glass", "Frosted Glass", "DCE6EA", r: 0.5, t: 0.45),
            m("Finishes", "White Paint", "F3F2EE", r: 0.85),
            m("Finishes", "Warm Grey Paint", "B8B2A8", r: 0.85),
            m("Finishes", "Ceramic Tiles White", "F0EFEB", r: 0.2, .tiles, scale: 600),
            m("Finishes", "Ceramic Tiles Grey", "9D9E9B", r: 0.25, .tiles, scale: 600),
            m("Finishes", "Carpet Grey", "6E6F71", r: 1),
            m("Finishes", "Linoleum", "7A8C6E", r: 0.5),
            m("Finishes", "Acoustic Ceiling", "E8E7E3", r: 1, .grid, scale: 600),
            m("Roofing", "Clay Roof Tiles", "9A4B32", r: 0.8, .tiles, scale: 400),
            m("Roofing", "Slate", "3F4449", r: 0.6, .tiles, scale: 500),
            m("Roofing", "Standing Seam Zinc", "7F858A", r: 0.45, metal: 0.8, .planks, scale: 500),
            m("Roofing", "Green Roof", "5E7F3E", r: 1),
            m("Site", "Lawn", "5B8A3A", r: 1),
            m("Site", "Gravel", "A39E92", r: 1, .stone, scale: 400),
            m("Site", "Asphalt", "3B3C3E", r: 0.95),
            m("Site", "Paving Stones", "9C958A", r: 0.85, .tiles, scale: 800),
            m("Site", "Water", "3E6F8C", r: 0.05, t: 0.35),
        ]
        list += Material.library.filter { lib in !list.contains { $0.material.name == lib.name } }.map { LibraryMaterial(category: "Finishes", material: $0) }
        return list
    }()

    /// The material to add to a document (with its generated pattern texture).
    @MainActor static func resolved(_ item: LibraryMaterial) -> ArchiCore.Material {
        var m = item.material
        if item.pattern != .none, let url = PatternTextures.url(for: item) { m.texture = url.path }
        return m
    }

    /// Adds library materials the document lacks; returns the names added.
    @MainActor @discardableResult
    static func add(_ items: [LibraryMaterial], to doc: inout ArchiDocument) -> [String] {
        var added: [String] = []
        for it in items where doc.material(it.material.name) == nil {
            doc.materials.append(resolved(it)); added.append(it.material.name)
        }
        return added
    }
}

/// Procedural seamless pattern textures (brick, tiles, planks, stone, ceiling grid) tinted by the material color.
@MainActor
enum PatternTextures {
    static var folder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let u = base.appendingPathComponent("Oanarina Archi Tool/Materials", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func url(for item: LibraryMaterial) -> URL? {
        guard let f = folder else { return nil }
        let u = f.appendingPathComponent(item.material.name.replacingOccurrences(of: "/", with: "-") + ".png")
        if FileManager.default.fileExists(atPath: u.path) { return u }
        guard let img = image(item.pattern, color: item.material.color, size: 512),
              let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        do { try png.write(to: u); return u } catch { return nil }
    }

    static func image(_ p: LibraryMaterial.Pattern, color c: RGBA, size s: CGFloat) -> NSImage? {
        guard p != .none else { return nil }
        let base = NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
        let joint = NSColor(srgbRed: c.r * 0.55 + 0.35, green: c.g * 0.55 + 0.33, blue: c.b * 0.55 + 0.3, alpha: 1)
        var rng = SplitMix(seed: c.hex.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 })
        func vary(_ k: Double) -> NSColor {
            let d = (rng.next() - 0.5) * k
            return NSColor(srgbRed: min(max(c.r + d, 0), 1), green: min(max(c.g + d, 0), 1), blue: min(max(c.b + d * 0.9, 0), 1), alpha: 1)
        }
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        base.setFill(); NSRect(x: 0, y: 0, width: s, height: s).fill()
        switch p {
        case .brick:
            // 8 courses, 4 bricks per course, running bond; mortar joints 4 px.
            joint.setFill(); NSRect(x: 0, y: 0, width: s, height: s).fill()
            let rows = 8, cols = 4, h = s / CGFloat(rows), w = s / CGFloat(cols), j: CGFloat = s / 128
            for r in 0..<rows { for k in -1..<cols {
                let x = CGFloat(k) * w + (r % 2 == 0 ? 0 : w / 2)
                vary(0.12).setFill(); NSRect(x: x + j / 2, y: CGFloat(r) * h + j / 2, width: w - j, height: h - j).fill()
            } }
        case .tiles, .grid:
            joint.setFill(); NSRect(x: 0, y: 0, width: s, height: s).fill()
            let n = p == .grid ? 2 : 4, w = s / CGFloat(n), j: CGFloat = p == .grid ? s / 90 : s / 160
            for r in 0..<n { for k in 0..<n {
                vary(p == .grid ? 0.02 : 0.06).setFill(); NSRect(x: CGFloat(k) * w + j / 2, y: CGFloat(r) * w + j / 2, width: w - j, height: w - j).fill()
            } }
        case .planks:
            let n = 6, h = s / CGFloat(n)
            for r in 0..<n {
                vary(0.1).setFill(); NSRect(x: 0, y: CGFloat(r) * h, width: s, height: h).fill()
                // Grain lines.
                for _ in 0..<10 {
                    let y = CGFloat(r) * h + CGFloat(rng.next()) * h
                    NSColor(white: 0, alpha: 0.06 + rng.next() * 0.06).setStroke()
                    let path = NSBezierPath(); path.move(to: NSPoint(x: 0, y: y))
                    path.curve(to: NSPoint(x: s, y: y), controlPoint1: NSPoint(x: s * 0.33, y: y + CGFloat(rng.next() - 0.5) * h * 0.4),
                               controlPoint2: NSPoint(x: s * 0.66, y: y + CGFloat(rng.next() - 0.5) * h * 0.4))
                    path.lineWidth = 1 + CGFloat(rng.next()) * 1.5; path.stroke()
                }
                joint.withAlphaComponent(0.6).setFill(); NSRect(x: 0, y: CGFloat(r) * h, width: s, height: max(1, s / 256)).fill()
            }
        case .stone:
            for _ in 0..<900 {
                let r = CGFloat(2 + rng.next() * 7)
                vary(0.22).withAlphaComponent(0.55).setFill()
                let x = CGFloat(rng.next()) * s, y = CGFloat(rng.next()) * s
                for dx in [-s, 0, s] { for dy in [-s, 0, s] { NSBezierPath(ovalIn: NSRect(x: x + dx - r, y: y + dy - r, width: 2 * r, height: 2 * r)).fill() } }
            }
        case .none: break
        }
        img.unlockFocus()
        return img
    }

    /// Small deterministic PRNG (textures look the same on every machine).
    struct SplitMix { var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
        mutating func next() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
    }
}

// MARK: - Thumbnails (rendered PBR spheres)

@MainActor
enum MaterialThumbnails {
    private static var cache: [ArchiCore.Material: NSImage] = [:]
    private static var renderer: SCNRenderer?
    private static var sphere: SCNNode?

    static func image(_ m: ArchiCore.Material, size: CGFloat = 96) -> NSImage? {
        if let i = cache[m] { return i }
        if renderer == nil {
            guard let dev = MTLCreateSystemDefaultDevice() else { return nil }
            let r = SCNRenderer(device: dev, options: nil)
            let scene = SCNScene()
            let env = Scene3DBuilder.gradient(top: NSColor(srgbRed: 0.75, green: 0.82, blue: 0.92, alpha: 1), bottom: NSColor(white: 0.25, alpha: 1))
            scene.lightingEnvironment.contents = env
            scene.lightingEnvironment.intensity = 1.4
            scene.background.contents = NSColor(white: 0.16, alpha: 1)
            let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional; key.light?.intensity = 900
            key.eulerAngles = SCNVector3(-0.7, 0.6, 0); scene.rootNode.addChildNode(key)
            let s = SCNNode(geometry: SCNSphere(radius: 1)); (s.geometry as? SCNSphere)?.segmentCount = 64
            scene.rootNode.addChildNode(s)
            let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera?.fieldOfView = 30; cam.position = SCNVector3(0, 0, 4.1)
            scene.rootNode.addChildNode(cam)
            r.scene = scene; r.pointOfView = cam
            renderer = r; sphere = s
        }
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        let color = NSColor(srgbRed: m.color.r, green: m.color.g, blue: m.color.b, alpha: 1)
        mat.diffuse.contents = color
        if let img = MaterialTextures.image(m.texture) {
            mat.diffuse.contents = img
            mat.diffuse.wrapS = .repeat; mat.diffuse.wrapT = .repeat
            mat.diffuse.contentsTransform = SCNMatrix4MakeScale(2, 1, 1)
        }
        mat.roughness.contents = NSNumber(value: min(max(m.roughness, 0.03), 1))
        mat.metalness.contents = NSNumber(value: min(max(m.metalness, 0), 1))
        if m.transparency > 0 { mat.transparency = CGFloat(1 - min(m.transparency, 0.9)); mat.transparencyMode = .dualLayer }
        sphere?.geometry?.materials = [mat]
        guard let img = renderer?.snapshot(atTime: 0, with: CGSize(width: size * 2, height: size * 2), antialiasingMode: .multisampling4X) else { return nil }
        cache[m] = img
        return img
    }
}

// MARK: - Browser window

@MainActor
enum MaterialLibraryWindow {
    private static var window: NSWindow?
    static func show(model: AppModel) {
        let view = MaterialLibraryBrowser(model: model).preferredColorScheme(.dark)
        if let w = window { w.contentViewController = NSHostingController(rootView: view); w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Material Library"
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentViewController = NSHostingController(rootView: view)
        w.center(); w.makeKeyAndOrderFront(nil)
        window = w
    }
}

struct MaterialLibraryBrowser: View {
    @ObservedObject var model: AppModel
    @State private var category = "All"
    @State private var query = ""
    @State private var selected: String?
    @State private var status = ""

    private var entries: [LibraryMaterial] {
        let doc = model.doc
        var list: [LibraryMaterial]
        if category == "In Drawing" { list = doc.materials.map { LibraryMaterial(category: "In Drawing", material: $0) } }
        else { list = MaterialLibrary.items.filter { category == "All" || $0.category == category } }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { list = list.filter { $0.material.name.lowercased().contains(q) || $0.category.lowercased().contains(q) } }
        return list
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(MaterialLibrary.categories, id: \.self) { c in
                    Button { category = c } label: {
                        Text(c).font(Theme.font).foregroundStyle(category == c ? Theme.accentText : Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).frame(height: 24)
                            .background(RoundedRectangle(cornerRadius: 4).fill(category == c ? Theme.accent : Color.clear))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(8).frame(width: 160).background(Theme.ribbonTabBar)
            VStack(spacing: 0) {
                HStack {
                    TextField("Search materials", text: $query).darkField().frame(maxWidth: 260)
                    Spacer()
                    Text("\(entries.count) materials").font(Theme.fontSmall).foregroundStyle(Theme.textDim)
                }
                .padding(10)
                HSeparator()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 12) {
                        ForEach(entries) { e in tile(e) }
                    }
                    .padding(12)
                }
                .background(Theme.panel)
                HSeparator()
                HStack(spacing: 8) {
                    if !status.isEmpty { Text(status).font(Theme.fontSmall).foregroundStyle(Theme.accent).lineLimit(1) }
                    Spacer()
                    Button("Add to Drawing") { if let e = selectedEntry { add(e) } }.buttonStyle(FlatButtonStyle()).disabled(selectedEntry == nil)
                    Button("Assign to Selection") { if let e = selectedEntry { assign(e) } }.buttonStyle(FlatButtonStyle(prominent: true))
                        .disabled(selectedEntry == nil || model.selectedElements.isEmpty)
                        .help("Assign the material to the selected building elements")
                }
                .padding(10)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .background(Theme.panel)
    }

    private var selectedEntry: LibraryMaterial? { entries.first { $0.id == selected } }

    private func tile(_ e: LibraryMaterial) -> some View {
        let isSel = selected == e.id
        let inDoc = model.doc.material(e.material.name) != nil
        let mat = category == "In Drawing" ? e.material : (model.doc.material(e.material.name) ?? MaterialLibrary.resolved(e))
        return VStack(spacing: 4) {
            Group {
                if let img = MaterialThumbnails.image(mat) { Image(nsImage: img).resizable().scaledToFit() }
                else { MaterialSwatch(material: mat, size: 80) }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(e.material.name).font(.system(size: 10.5)).foregroundStyle(Theme.text).lineLimit(1)
            Text(inDoc ? "In drawing" : e.category).font(.system(size: 9)).foregroundStyle(inDoc ? Theme.accent : Theme.textDim).lineLimit(1)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSel ? Theme.hover : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSel ? Theme.accent : Theme.separator, lineWidth: isSel ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { selected = e.id; if model.selectedElements.isEmpty { add(e) } else { assign(e) } }
        .onTapGesture { selected = e.id }
        .onDrag { NSItemProvider(object: ("archi-material:" + e.material.name) as NSString) }
        .help("\(e.material.name) — roughness \(fmt(e.material.roughness, 2)), metalness \(fmt(e.material.metalness, 2))\(e.material.transparency > 0 ? ", transparency \(fmt(e.material.transparency, 2))" : "")\nDouble-click: assign to the selection (or add to the drawing)")
    }

    private func add(_ e: LibraryMaterial) {
        var added: [String] = []
        model.editor.transaction("Add Material") { d in added = MaterialLibrary.add([e], to: &d) }
        status = added.isEmpty ? "\(e.material.name) is already in the drawing." : "Added \(e.material.name)."
    }

    private func assign(_ e: LibraryMaterial) {
        let ids = Set(model.selectedElements.map(\.id))
        guard !ids.isEmpty else { return }
        let name = e.material.name
        model.editor.transaction("Assign Material") { d in
            if d.material(name) == nil { MaterialLibrary.add([e], to: &d) }
            for i in d.elements.indices where ids.contains(d.elements[i].id) { d.elements[i].material = name }
        }
        status = "\(name) assigned to \(ids.count) element(s)."
    }
}
