// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// A parametric component family (furniture, fixture, casework, entourage). Geometry flexes with the
/// instance size: width = X, depth = Y (front faces −Y), height = Z.
public struct ComponentFamily: Hashable {
    public var id: String
    public var name: String
    public var category: String
    public var size: Vec3
    /// Default height of the component base above its level (wall cabinets hang at 1450).
    public var baseOffset: Double
    public var aliases: [String]
    public init(_ id: String, _ name: String, _ category: String, _ size: Vec3, baseOffset: Double = 0, aliases: [String] = []) {
        self.id = id; self.name = name; self.category = category; self.size = size; self.baseOffset = baseOffset; self.aliases = aliases
    }
}

/// One 2D plan symbol line in component-local coordinates.
public struct ComponentSymbolLine: Hashable {
    public var points: [Vec2]
    public var closed: Bool
    /// true = outline (projection weight), false = detail (fine weight).
    public var outline: Bool
    /// Drawn dashed (elements above the cut plane, e.g. wall cabinets).
    public var hidden: Bool
}

/// Built-in library of parametric families with 3D meshes and 2D plan symbols.
public enum ComponentLibrary {
    /// Point-placed families (see also `runFamilies`, placed along a path).
    public static let families: [ComponentFamily] = [
        ComponentFamily("bed-single", "Single Bed", "Furniture", Vec3(900, 2000, 500), aliases: ["SingleBed"]),
        ComponentFamily("bed-double", "Double Bed", "Furniture", Vec3(1600, 2000, 500), aliases: ["Bed", "DoubleBed"]),
        ComponentFamily("sofa", "Sofa", "Furniture", Vec3(2000, 900, 800), aliases: ["Couch"]),
        ComponentFamily("armchair", "Armchair", "Furniture", Vec3(850, 850, 800)),
        ComponentFamily("chair", "Chair", "Furniture", Vec3(450, 500, 900)),
        ComponentFamily("table", "Dining Table", "Furniture", Vec3(1600, 900, 750), aliases: ["Table", "DiningTable"]),
        ComponentFamily("table-round", "Round Table", "Furniture", Vec3(1000, 1000, 750), aliases: ["RoundTable"]),
        ComponentFamily("coffee-table", "Coffee Table", "Furniture", Vec3(1100, 600, 400), aliases: ["CoffeeTable"]),
        ComponentFamily("desk", "Desk", "Furniture", Vec3(1400, 700, 750)),
        ComponentFamily("wardrobe", "Wardrobe", "Casework", Vec3(1200, 600, 2200), aliases: ["Closet"]),
        ComponentFamily("bookshelf", "Bookshelf", "Furniture", Vec3(900, 350, 2000), aliases: ["Shelf", "Bookcase"]),
        ComponentFamily("nightstand", "Nightstand", "Furniture", Vec3(450, 400, 500), aliases: ["BedsideTable"]),
        ComponentFamily("kitchen-base", "Kitchen Base Units", "Casework", Vec3(2400, 600, 900), aliases: ["Kitchen", "BaseCabinet"]),
        ComponentFamily("kitchen-wall", "Kitchen Wall Units", "Casework", Vec3(2400, 350, 700), baseOffset: 1450, aliases: ["WallCabinet", "UpperCabinet"]),
        ComponentFamily("kitchen-sink", "Kitchen Sink Unit", "Casework", Vec3(1000, 600, 900), aliases: ["SinkUnit"]),
        ComponentFamily("fridge", "Refrigerator", "Appliances", Vec3(600, 650, 1850), aliases: ["Refrigerator"]),
        ComponentFamily("range", "Cooker", "Appliances", Vec3(600, 600, 900), aliases: ["Cooker", "Stove", "Oven"]),
        ComponentFamily("washer", "Washing Machine", "Appliances", Vec3(600, 600, 850), aliases: ["WashingMachine"]),
        ComponentFamily("wc", "WC", "Plumbing", Vec3(380, 700, 800), aliases: ["Toilet"]),
        ComponentFamily("basin", "Washbasin", "Plumbing", Vec3(600, 450, 850), aliases: ["Sink", "Lavatory", "Washbasin"]),
        ComponentFamily("shower", "Shower", "Plumbing", Vec3(900, 900, 2000)),
        ComponentFamily("bath", "Bathtub", "Plumbing", Vec3(700, 1700, 550), aliases: ["Bathtub", "Tub"]),
        ComponentFamily("car", "Car", "Entourage", Vec3(1800, 4500, 1500)),
        ComponentFamily("person-standing", "Person Standing", "Entourage", Vec3(500, 300, 1750), aliases: ["Person", "People", "Man", "Woman", "Standing"]),
        ComponentFamily("person-walking", "Person Walking", "Entourage", Vec3(500, 650, 1750), aliases: ["Walking", "Pedestrian"]),
        ComponentFamily("person-child", "Child", "Entourage", Vec3(330, 220, 1150), aliases: ["Kid"]),
        ComponentFamily("bicycle", "Bicycle", "Entourage", Vec3(600, 1750, 1050), aliases: ["Bike", "Cycle"]),
        ComponentFamily("tree", "Tree", "Planting", Vec3(4000, 4000, 6000)),
        ComponentFamily("shrub", "Shrub", "Planting", Vec3(1200, 1200, 1000), aliases: ["Bush"]),
        ComponentFamily("parking", "Parking Space", "Site", Vec3(2500, 5000, 5), aliases: ["ParkingSpace"]),
        ComponentFamily("outlet", "Power Outlet", "Electrical", Vec3(80, 45, 80), baseOffset: 300, aliases: ["Receptacle", "Socket"]),
        ComponentFamily("switch", "Light Switch", "Electrical", Vec3(80, 45, 80), baseOffset: 1100, aliases: ["Switch"]),
        ComponentFamily("light-ceiling", "Ceiling Light", "Lighting", Vec3(400, 400, 100), baseOffset: 2600, aliases: ["Light", "CeilingLight", "Luminaire"]),
        ComponentFamily("light-wall", "Wall Light", "Lighting", Vec3(250, 150, 250), baseOffset: 1800, aliases: ["Sconce", "WallLight"]),
        ComponentFamily("panel", "Electrical Panel", "Electrical", Vec3(450, 150, 600), baseOffset: 1300, aliases: ["DistributionBoard", "Panelboard"]),
        ComponentFamily("smoke-detector", "Smoke Detector", "Electrical", Vec3(120, 120, 50), baseOffset: 2650, aliases: ["SmokeDetector"]),
        ComponentFamily("data-outlet", "Data Outlet", "Communications", Vec3(80, 45, 80), baseOffset: 300, aliases: ["DataOutlet", "Network", "RJ45"]),
        ComponentFamily("air-supply", "Supply Air Diffuser", "Mechanical", Vec3(600, 600, 300), baseOffset: 2700, aliases: ["Diffuser", "SupplyDiffuser", "AirTerminal"]),
        ComponentFamily("air-return", "Return Air Grille", "Mechanical", Vec3(600, 600, 300), baseOffset: 2700, aliases: ["ReturnGrille", "Grille"]),
        ComponentFamily("radiator", "Radiator", "Mechanical", Vec3(1000, 100, 600), baseOffset: 150, aliases: ["Heater", "PanelRadiator"]),
        ComponentFamily("elevator", "Elevator Car", "Vertical Circulation", Vec3(1100, 1400, 2300), aliases: ["Lift", "Elevator", "LiftCar"]),
        ComponentFamily("escalator", "Escalator", "Vertical Circulation", Vec3(1600, 12_600, 4000), aliases: ["Escalator", "MovingStair"]),
        ComponentFamily("truss-pratt", "Pratt Truss", "Structural", Vec3(12000, 100, 1500), baseOffset: 3000, aliases: ["Truss", "PrattTruss"]),
        ComponentFamily("truss-howe", "Howe Truss", "Structural", Vec3(12000, 100, 1500), baseOffset: 3000, aliases: ["HoweTruss"]),
        ComponentFamily("truss-warren", "Warren Truss", "Structural", Vec3(12000, 100, 1500), baseOffset: 3000, aliases: ["WarrenTruss"]),
        ComponentFamily("truss-fink", "Fink Roof Truss", "Structural", Vec3(9000, 50, 2600), baseOffset: 3000, aliases: ["FinkTruss", "RoofTruss"]),
    ]

    /// Families placed along a path (ComponentGeom.path): size.x = diameter/width, size.z = height.
    public static let runFamilies: [ComponentFamily] = [
        ComponentFamily("pipe", "Pipe", "Plumbing", Vec3(50, 50, 50), baseOffset: 2700, aliases: ["PipeRun"]),
        ComponentFamily("conduit", "Conduit", "Electrical", Vec3(25, 25, 25), baseOffset: 2800),
        ComponentFamily("duct", "Duct", "Mechanical", Vec3(400, 400, 250), baseOffset: 2800, aliases: ["DuctRun"]),
        ComponentFamily("cabletray", "Cable Tray", "Electrical", Vec3(300, 300, 60), baseOffset: 2900, aliases: ["Tray"]),
        ComponentFamily("retaining-wall", "Retaining Wall", "Site", Vec3(300, 300, 1500), aliases: ["RetainingWall"]),
    ]
    public static func runFamily(_ id: String?) -> ComponentFamily? { runFamilies.first { $0.id == id } }

    /// Materials the families use (added to a document when a family is placed).
    public static let materials: [Material] = [
        Material(name: "Fabric", color: RGBA(0.42, 0.47, 0.55), roughness: 1),
        Material(name: "Linen", color: RGBA(0.93, 0.92, 0.88), roughness: 1),
        Material(name: "Ceramic", color: RGBA(0.97, 0.97, 0.96), roughness: 0.15),
        Material(name: "Laminate", color: RGBA(0.90, 0.89, 0.86), roughness: 0.4),
        Material(name: "Worktop", color: RGBA(0.30, 0.30, 0.32), roughness: 0.3, cutPattern: "AR-SAND"),
        Material(name: "Leaves", color: RGBA(0.27, 0.47, 0.22), roughness: 1),
        Material(name: "Bark", color: RGBA(0.36, 0.26, 0.18), roughness: 1),
        Material(name: "Car Paint", color: RGBA(0.62, 0.10, 0.10), roughness: 0.25, metalness: 0.6),
        Material(name: "Rubber", color: RGBA(0.08, 0.08, 0.09), roughness: 0.9),
        Material(name: "Road Paint", color: RGBA(0.96, 0.96, 0.94), roughness: 0.8),
        Material(name: "Skin", color: RGBA(0.80, 0.62, 0.50), roughness: 0.7),
        Material(name: "Clothing", color: RGBA(0.25, 0.32, 0.45), roughness: 0.95),
        Material(name: "Clothing Light", color: RGBA(0.78, 0.74, 0.66), roughness: 0.95),
    ]

    /// Family by id, name or alias (case-insensitive, ignoring spaces, dashes and underscores).
    public static func family(_ key: String?) -> ComponentFamily? {
        guard let key = key else { return nil }
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let k = norm(key)
        guard !k.isEmpty else { return nil }
        return families.first { norm($0.id) == k || norm($0.name) == k || $0.aliases.contains { norm($0) == k } }
    }

    /// Adds the library materials a document lacks.
    public static func ensureMaterials(_ doc: inout ArchiDocument) {
        for m in materials where doc.material(m.name) == nil { doc.materials.append(m) }
    }

    // MARK: 3D

    /// Mesh accumulator per material role, in family-local coordinates.
    struct Parts {
        var accs: [String: MeshAcc] = [:]
        var order: [String] = []
        mutating func acc(_ m: String, _ f: (inout MeshAcc) -> Void) {
            if accs[m] == nil { accs[m] = MeshAcc(); order.append(m) }
            f(&accs[m]!)
        }
        mutating func box(_ m: String, _ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, _ z0: Double, _ z1: Double) {
            guard x1 - x0 > 1e-6, y1 - y0 > 1e-6, z1 - z0 > 1e-6 else { return }
            acc(m) { $0.prism([Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1)], z0: z0, z1: z1) }
        }
        mutating func rbox(_ m: String, _ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, _ z0: Double, _ z1: Double, r: Double) {
            guard x1 - x0 > 1e-6, y1 - y0 > 1e-6, z1 - z0 > 1e-6 else { return }
            let loop = ComponentLibrary.roundedRect(x0, x1, y0, y1, r)
            acc(m) { $0.prism(loop, z0: z0, z1: z1, smooth: true) }
        }
        mutating func cyl(_ m: String, _ c: Vec2, _ r: Double, _ z0: Double, _ z1: Double) {
            guard r > 1e-6, z1 - z0 > 1e-6 else { return }
            acc(m) { $0.prism(RG.circle(c, r, segments: 24), z0: z0, z1: z1, smooth: true) }
        }
        mutating func ellipsePrism(_ m: String, _ c: Vec2, _ rx: Double, _ ry: Double, _ z0: Double, _ z1: Double) {
            guard rx > 1e-6, ry > 1e-6, z1 - z0 > 1e-6 else { return }
            acc(m) { $0.prism(ComponentLibrary.ellipse(c, rx, ry), z0: z0, z1: z1, smooth: true) }
        }
        /// Ellipsoid (tree crowns, shrubs).
        mutating func ellipsoid(_ m: String, _ c: Vec3, _ rx: Double, _ ry: Double, _ rz: Double) {
            guard rx > 1e-6, ry > 1e-6, rz > 1e-6 else { return }
            var a = MeshAcc()
            MeshBuilder.solid(SolidGeom(kind: .sphere, origin: .zero, size: Vec3(1, 0, 0)), into: &a)
            a.mesh.positions = a.mesh.positions.map { Vec3(c.x + $0.x * rx, c.y + $0.y * ry, c.z + $0.z * rz) }
            a.mesh.normals = a.mesh.normals.map { Vec3($0.x / rx, $0.y / ry, $0.z / rz).normalized }
            a.edges = []
            acc(m) { $0.mesh.append(a.mesh) }
        }
        /// Profile in a vertical plane (x along `ax`, z up) extruded along `ay` from y0 to y1; origin in local plan coordinates.
        mutating func plate(_ m: String, _ profile: [(x: Double, z: Double)], origin: Vec2, ax: Vec2, ay: Vec2, _ y0: Double, _ y1: Double) {
            guard profile.count >= 3, abs(y1 - y0) > 1e-6 else { return }
            acc(m) { $0.verticalPlate(profile, origin: origin, ax: ax, ay: ay, y0: min(y0, y1), y1: max(y0, y1)) }
        }
    }

    static func roundedRect(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, _ r0: Double, segments: Int = 4) -> [Vec2] {
        let r = max(0, min(r0, (x1 - x0) / 2 - 1e-6, (y1 - y0) / 2 - 1e-6))
        if r < 1e-6 { return [Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1)] }
        var pts: [Vec2] = []
        let corners = [(Vec2(x1 - r, y0 + r), -Double.pi / 2), (Vec2(x1 - r, y1 - r), 0), (Vec2(x0 + r, y1 - r), Double.pi / 2), (Vec2(x0 + r, y0 + r), Double.pi)]
        for (c, a0) in corners { for k in 0...segments { pts.append(c + Vec2.polar(r, a0 + Double.pi / 2 * Double(k) / Double(segments))) } }
        return pts
    }
    static func ellipse(_ c: Vec2, _ rx: Double, _ ry: Double, segments: Int = 32) -> [Vec2] {
        (0..<segments).map { let a = 2 * Double.pi * Double($0) / Double(segments); return c + Vec2(rx * cos(a), ry * sin(a)) }
    }
    static func circleProfile(_ cx: Double, _ cz: Double, _ r: Double, segments: Int = 20) -> [(x: Double, z: Double)] {
        (0..<segments).map { let a = 2 * Double.pi * Double($0) / Double(segments); return (cx + r * cos(a), cz + r * sin(a)) }
    }

    /// Local 3D parts (material → mesh) of a family at a size.
    static func parts(_ f: ComponentFamily, size s: Vec3) -> Parts {
        var p = Parts()
        let W = max(s.x, 1), D = max(s.y, 1), H = max(s.z, 1)
        let x0 = -W / 2, x1 = W / 2, y0 = -D / 2, y1 = D / 2
        switch f.id {
        case "elevator":
            // Car: floor, walls on three sides, ceiling, and a two-panel centre-opening door on the front (−Y).
            let t = 30.0
            p.box("Steel", x0, x1, y0, y1, 0, 60)
            p.box("Steel", x0, x0 + t, y0 + 80, y1, 60, H - 60); p.box("Steel", x1 - t, x1, y0 + 80, y1, 60, H - 60)
            p.box("Steel", x0, x1, y1 - t, y1, 60, H - 60)
            p.box("Steel", x0, x1, y0, y1, H - 60, H)
            let dw = min(W * 0.8, 900.0) / 2
            p.box("Aluminium", -dw, -2, y0, y0 + 25, 60, min(2100, H - 80)); p.box("Aluminium", 2, dw, y0, y0 + 25, 60, min(2100, H - 80))
            p.box("Steel", x0, -dw, y0, y0 + 80, 60, H - 60); p.box("Steel", dw, x1, y0, y0 + 80, 60, H - 60)
            p.box("Glass", x0 + t, x0 + t + 6, y0 + 200, y1 - 200, 900, H - 300)
        case "escalator":
            let e = Escalators.Section(width: W, length: D, rise: H)
            // Step band with a sawtooth top between the balustrades, side decks, glass balustrades and handrails.
            p.plate("Aluminium", e.sawtooth() + e.underside(to: e.y0 + e.landing), origin: .zero, ax: Vec2(0, 1), ay: Vec2(1, 0), -e.stepWidth / 2, e.stepWidth / 2)
            p.box("Aluminium", -e.stepWidth / 2, e.stepWidth / 2, e.y0, e.y0 + e.landing, 0, 20)   // lower landing plate
            for sgn in [-1.0, 1.0] {
                let inner = sgn * e.stepWidth / 2, outer = sgn * W / 2
                p.plate("Steel", e.stepLine(dz: 100) + e.underside(to: e.y0), origin: .zero, ax: Vec2(0, 1), ay: Vec2(1, 0), min(inner, outer), max(inner, outer))
                let gx = sgn * (e.stepWidth / 2 + 60)
                p.plate("Glass", e.stepLine(dz: 100) + e.stepLine(dz: 950).reversed(), origin: .zero, ax: Vec2(0, 1), ay: Vec2(1, 0), gx - 8, gx + 8)
                p.plate("Rubber", e.stepLine(dz: 950) + e.stepLine(dz: 1000).reversed(), origin: .zero, ax: Vec2(0, 1), ay: Vec2(1, 0), gx - 40, gx + 40)
            }
        case "bed-single", "bed-double":
            let leg = min(100, H * 0.2), frameTop = H * 0.6
            for (cx, cy) in [(x0 + 60, y0 + 60), (x1 - 60, y0 + 60), (x0 + 60, y1 - 60), (x1 - 60, y1 - 60)] { p.cyl("Wood", Vec2(cx, cy), 25, 0, leg) }
            p.box("Wood", x0, x1, y0, y1 - 60, leg, frameTop)
            p.box("Wood", x0, x1, y1 - 60, y1, 0, max(H + 450, 900))
            p.rbox("Linen", x0 + 20, x1 - 20, y0 + 20, y1 - 80, frameTop, H, r: 60)
            let foldY = y0 + (D - 80) * 0.7
            p.box("Fabric", x0 + 10, x1 - 10, y0 + 10, foldY, H, H + 30)
            let n = W >= 1200 ? 2 : 1
            let pw = (W - 60 - 40 * Double(n - 1)) / Double(n)
            for i in 0..<n {
                let px = x0 + 30 + Double(i) * (pw + 40)
                p.rbox("Linen", px, px + pw, y1 - 80 - 380, y1 - 100, H, H + 120, r: 60)
            }
        case "sofa", "armchair":
            let arm = min(180, W * 0.2), leg = 100.0, seatZ = min(420, H * 0.55), back = min(200, D * 0.25)
            for (cx, cy) in [(x0 + 50, y0 + 50), (x1 - 50, y0 + 50), (x0 + 50, y1 - 50), (x1 - 50, y1 - 50)] { p.cyl("Wood", Vec2(cx, cy), 20, 0, leg) }
            p.box("Fabric", x0 + arm, x1 - arm, y0, y1 - back, leg, seatZ - 120)
            p.rbox("Fabric", x0, x0 + arm, y0, y1, leg, min(H * 0.78, seatZ + 200), r: 40)
            p.rbox("Fabric", x1 - arm, x1, y0, y1, leg, min(H * 0.78, seatZ + 200), r: 40)
            p.box("Fabric", x0 + arm, x1 - arm, y1 - back, y1, leg, H)
            let n = f.id == "armchair" ? 1 : (W - 2 * arm > 1500 ? 3 : 2)
            let cw = (W - 2 * arm) / Double(n)
            for i in 0..<n {
                let cx = x0 + arm + Double(i) * cw
                p.rbox("Linen", cx + 5, cx + cw - 5, y0 + 10, y1 - back, seatZ - 120, seatZ, r: 50)
                p.rbox("Linen", cx + 10, cx + cw - 10, y1 - back - 160, y1 - back, seatZ, H - 60, r: 50)
            }
        case "chair":
            let seat = min(450, H * 0.5), t = 35.0
            for (cx, cy) in [(x0, y0), (x1 - t, y0), (x0, y1 - t), (x1 - t, y1 - t)] { p.box("Wood", cx, cx + t, cy, cy + t, 0, seat - 40) }
            p.box("Wood", x0, x1, y0, y1, seat - 40, seat)
            p.box("Wood", x0, x0 + t, y1 - t, y1, seat, H); p.box("Wood", x1 - t, x1, y1 - t, y1, seat, H)
            p.box("Wood", x0 + t, x1 - t, y1 - 25, y1, seat + (H - seat) * 0.45, H)
        case "table", "coffee-table", "desk":
            let top = f.id == "coffee-table" ? 30.0 : 40.0
            p.box("Wood", x0, x1, y0, y1, H - top, H)
            if f.id == "desk" {
                let ped = min(400, W * 0.35)
                p.box("Laminate", x0 + 10, x0 + ped, y0 + 10, y1 - 10, 0, H - top)
                p.box("Wood", x1 - 60, x1 - 10, y0 + 30, y0 + 80, 0, H - top); p.box("Wood", x1 - 60, x1 - 10, y1 - 80, y1 - 30, 0, H - top)
                p.box("Laminate", x0 + ped, x1 - 60, y1 - 30, y1 - 10, H * 0.35, H - top)
                for k in 1..<3 { let z = (H - top) * Double(k) / 3; p.box("Steel", x0 + ped / 2 - 60, x0 + ped / 2 + 60, y0 - 15, y0 + 10, z - 10, z + 10) }
            } else {
                let lg = f.id == "coffee-table" ? 40.0 : 60.0, ins = 40.0
                for (cx, cy) in [(x0 + ins, y0 + ins), (x1 - ins - lg, y0 + ins), (x0 + ins, y1 - ins - lg), (x1 - ins - lg, y1 - ins - lg)] { p.box("Wood", cx, cx + lg, cy, cy + lg, 0, H - top) }
                if f.id == "coffee-table" { p.box("Wood", x0 + ins, x1 - ins, y0 + ins, y1 - ins, 80, 100) }
            }
        case "table-round":
            let r = min(W, D) / 2
            p.ellipsePrism("Wood", .zero, W / 2, D / 2, H - 40, H)       // round, or oval when width ≠ depth
            p.cyl("Wood", .zero, max(40, r * 0.1), 40, H - 40)
            p.ellipsePrism("Wood", .zero, W * 0.22, D * 0.22, 0, 40)
        case "wardrobe", "bookshelf", "nightstand":
            let t = 20.0
            if f.id == "bookshelf" {
                p.box("Wood", x0, x0 + t, y0, y1, 0, H); p.box("Wood", x1 - t, x1, y0, y1, 0, H)
                p.box("Wood", x0 + t, x1 - t, y1 - 8, y1, 0, H)
                let shelves = max(2, Int((H / 350).rounded()))
                for k in 0...shelves { let z = min(H - t, Double(k) * (H - t) / Double(shelves)); p.box("Wood", x0 + t, x1 - t, y0, y1 - 8, z, z + t) }
                // A few books on each shelf.
                for k in 0..<shelves {
                    let z = Double(k) * (H - t) / Double(shelves) + t
                    let gap = (H - t) / Double(shelves) - t
                    var x = x0 + t + 10
                    var i = 0
                    while x < x1 - t - 120 && i < 40 {
                        let bw = 25 + Double((i * 37 + k * 11) % 20), bh = gap * (0.62 + Double((i * 13 + k * 7) % 25) / 100)
                        if (i + k) % 7 != 6 { p.box(i % 3 == 0 ? "Fabric" : (i % 3 == 1 ? "Laminate" : "Car Paint"), x, x + bw, y0 + 30, y1 - 30, z, z + bh) }
                        x += bw + 2; i += 1
                    }
                }
            } else {
                p.box("Wood", x0, x1, y0 + t, y1, 0, H)
                let n = f.id == "wardrobe" ? max(2, Int((W / 600).rounded())) : 1
                let dw = W / Double(n)
                if f.id == "nightstand" {
                    p.box("Laminate", x0 + 3, x1 - 3, y0, y0 + t, H * 0.55, H - 30); p.box("Laminate", x0 + 3, x1 - 3, y0, y0 + t, 60, H * 0.55 - 6)
                    p.box("Steel", -60, 60, y0 - 15, y0, H * 0.78 - 8, H * 0.78 + 8)
                } else {
                    for i in 0..<n {
                        let a = x0 + Double(i) * dw + 2, b = a + dw - 4
                        p.box("Laminate", a, b, y0, y0 + t, 60, H - 10)
                        let hx = i % 2 == 0 ? b - 50 : a + 30
                        p.box("Steel", hx, hx + 20, y0 - 20, y0, H * 0.45, H * 0.45 + 250)
                    }
                }
            }
        case "kitchen-base", "kitchen-sink", "range", "washer", "fridge":
            let plinth = f.id == "fridge" || f.id == "washer" ? 0.0 : 100.0
            let top = f.id == "fridge" ? 0.0 : 40.0
            if plinth > 0 { p.box("Laminate", x0, x1, y0 + 60, y1, 0, plinth) }
            let bodyMat = f.id == "range" || f.id == "fridge" || f.id == "washer" ? "Aluminium" : "Laminate"
            p.box(bodyMat, x0, x1, y0 + 20, y1, plinth, H - top)
            if top > 0 && f.id != "washer" && f.id != "range" {
                if f.id == "kitchen-sink" {
                    // Worktop around a sink bowl.
                    let bw = min(W - 200, 800), bd = min(D - 200, 420), bx0 = -bw / 2, bx1 = bw / 2, by0 = y0 + (D - bd) / 2 - 20, by1 = by0 + bd
                    p.box("Worktop", x0, x1, y0, by0, H - top, H); p.box("Worktop", x0, x1, by1, y1, H - top, H)
                    p.box("Worktop", x0, bx0, by0, by1, H - top, H); p.box("Worktop", bx1, x1, by0, by1, H - top, H)
                    p.box("Steel", bx0, bx1, by0, by1, H - 200, H - 190)
                    p.box("Steel", bx0, bx1, by0, by0 + 2, H - 200, H - top); p.box("Steel", bx0, bx1, by1 - 2, by1, H - 200, H - top)
                    p.box("Steel", bx0, bx0 + 2, by0, by1, H - 200, H - top); p.box("Steel", bx1 - 2, bx1, by0, by1, H - 200, H - top)
                    p.cyl("Steel", Vec2(0, by1 + 45), 22, H, H + 280)
                    p.plate("Steel", [(0, H + 250), (180, H + 250), (180, H + 275), (0, H + 275)], origin: Vec2(-12, by1 + 45), ax: Vec2(0, -1), ay: Vec2(1, 0), 0, 24)
                } else {
                    p.box("Worktop", x0, x1, y0, y1, H - top, H)
                }
            }
            switch f.id {
            case "range":
                p.box("Worktop", x0, x1, y0, y1, H - 30, H)
                for (cx, cy) in [(-W / 4, -D / 5), (W / 4, -D / 5), (-W / 4, D / 5), (W / 4, D / 5)] { p.cyl("Rubber", Vec2(cx, cy), min(W, D) * 0.14, H, H + 12) }
                p.box("Glass", x0 + 40, x1 - 40, y0, y0 + 20, plinth + 80, H - 200)
                p.box("Steel", x0 + 60, x1 - 60, y0 - 30, y0, H - 170, H - 150)
            case "washer":
                p.box("Aluminium", x0, x1, y0, y1, H - 20, H)
                p.plate("Glass", circleProfile(0, H * 0.45, min(W, H) * 0.3), origin: Vec2(0, y0 + 20), ax: Vec2(1, 0), ay: Vec2(0, -1), 0, 25)
                p.box("Laminate", x0 + 30, x0 + W * 0.4, y0, y0 + 20, H - 140, H - 50)
            case "fridge":
                let split = H * 0.62
                p.box("Aluminium", x0 + 2, x1 - 2, y0, y0 + 20, split + 5, H - 5); p.box("Aluminium", x0 + 2, x1 - 2, y0, y0 + 20, 5, split - 5)
                p.box("Steel", x1 - 60, x1 - 40, y0 - 30, y0, split + 80, split + 480); p.box("Steel", x1 - 60, x1 - 40, y0 - 30, y0, split - 330, split - 80)
            default:
                let n = max(1, Int((W / 600).rounded()))
                let dw = W / Double(n)
                for i in 0..<n {
                    let a = x0 + Double(i) * dw + 2, b = a + dw - 4
                    p.box("Laminate", a, b, y0, y0 + 20, plinth + 10, H - top - 10)
                    p.box("Steel", (a + b) / 2 - 80, (a + b) / 2 + 80, y0 - 20, y0, H - top - 90, H - top - 70)
                }
            }
        case "kitchen-wall":
            p.box("Laminate", x0, x1, y0 + 20, y1, 0, H)
            let n = max(1, Int((W / 600).rounded()))
            let dw = W / Double(n)
            for i in 0..<n {
                let a = x0 + Double(i) * dw + 2, b = a + dw - 4
                p.box("Laminate", a, b, y0, y0 + 20, 0, H)
                p.box("Steel", (a + b) / 2 - 80, (a + b) / 2 + 80, y0 - 20, y0, 40, 60)
            }
        case "wc":
            let cist = min(180, D * 0.28), seatZ = min(420, H * 0.55)
            let bl = D - cist, bc = Vec2(0, y0 + bl / 2)
            p.ellipsePrism("Ceramic", bc + Vec2(0, 20), W * 0.32, bl * 0.32, 0, seatZ * 0.5)
            p.ellipsePrism("Ceramic", bc, W / 2, bl / 2, seatZ * 0.5, seatZ - 20)
            p.ellipsePrism("Ceramic", bc, W / 2 - 5, bl / 2 - 5, seatZ - 20, seatZ)
            p.box("Ceramic", x0, x1, y1 - cist, y1, seatZ * 0.5, H)
            p.box("Steel", -30, 30, y1 - cist / 2 - 15, y1 - cist / 2 + 15, H, H + 8)
        case "basin":
            let bowlTop = H
            p.cyl("Ceramic", Vec2(0, y1 - 120), 90, 0, bowlTop - 150)
            p.rbox("Ceramic", x0, x1, y0, y1, bowlTop - 150, bowlTop, r: 80)
            p.cyl("Steel", Vec2(0, y1 - 50), 18, bowlTop, bowlTop + 150)
            p.plate("Steel", [(0, bowlTop + 120), (120, bowlTop + 120), (120, bowlTop + 142), (0, bowlTop + 142)], origin: Vec2(-10, y1 - 50), ax: Vec2(0, -1), ay: Vec2(1, 0), 0, 20)
        case "shower":
            p.box("Ceramic", x0, x1, y0, y1, 0, 60)
            p.cyl("Rubber", .zero, 45, 60, 63)
            p.box("Glass", x0, x1, y0, y0 + 8, 60, H)
            p.box("Glass", x0, x0 + 8, y0 + 8, y1, 60, H)
            p.box("Aluminium", x0, x1, y0, y0 + 10, H - 30, H)
            p.cyl("Steel", Vec2(x1 - 80, y1 - 40), 12, 900, H - 100)
            p.cyl("Steel", Vec2(x1 - 80, y1 - 140), 80, H - 120, H - 100)
            p.box("Steel", x1 - 92, x1 - 68, y1 - 140, y1 - 40, H - 115, H - 100)
        case "bath":
            let t = min(70, W * 0.1)
            p.box("Ceramic", x0, x1, y0, y0 + t, 0, H); p.box("Ceramic", x0, x1, y1 - t, y1, 0, H)
            p.box("Ceramic", x0, x0 + t, y0 + t, y1 - t, 0, H); p.box("Ceramic", x1 - t, x1, y0 + t, y1 - t, 0, H)
            p.box("Ceramic", x0 + t, x1 - t, y0 + t, y1 - t, 0, 100)
            p.cyl("Rubber", Vec2(0, y1 - t - 120), 30, 100, 102)
            p.cyl("Steel", Vec2(0, y1 - 35), 16, H, H + 120)
        case "car":
            let L = D
            func tz(_ t: Double, _ z: Double) -> (x: Double, z: Double) { (t * L, z * H) }
            let body = [tz(0, 0.22), tz(1, 0.22), tz(1, 0.58), tz(0.93, 0.63), tz(0.77, 0.95), tz(0.42, 0.95), tz(0.29, 0.56), tz(0.03, 0.51), tz(0, 0.45)]
            p.plate("Car Paint", body, origin: Vec2(x0 + 30, y0), ax: Vec2(0, 1), ay: Vec2(1, 0), 0, W - 60)
            let win = [tz(0.33, 0.58), tz(0.88, 0.62), tz(0.76, 0.91), tz(0.44, 0.91)]
            p.plate("Glass", win, origin: Vec2(x0 + 25, y0), ax: Vec2(0, 1), ay: Vec2(1, 0), 0, 6)
            p.plate("Glass", win, origin: Vec2(x1 - 31, y0), ax: Vec2(0, 1), ay: Vec2(1, 0), 0, 6)
            p.plate("Glass", [tz(0.29, 0.58), tz(0.305, 0.58), tz(0.425, 0.935), tz(0.41, 0.935)], origin: Vec2(x0 + 60, y0), ax: Vec2(0, 1), ay: Vec2(1, 0), 0, W - 120)
            let r = min(0.22 * H, 0.08 * L)
            for t in [0.17, 0.80] {
                p.plate("Rubber", circleProfile(t * L, r, r), origin: Vec2(x0 + 10, y0), ax: Vec2(0, 1), ay: Vec2(1, 0), 0, 210)
                p.plate("Rubber", circleProfile(t * L, r, r), origin: Vec2(x1 - 220, y0), ax: Vec2(0, 1), ay: Vec2(1, 0), 0, 210)
            }
            p.box("Glass", x0 + 180, x0 + 480, y0 - 2, y0 + 5, H * 0.40, H * 0.47); p.box("Glass", x1 - 480, x1 - 180, y0 - 2, y0 + 5, H * 0.40, H * 0.47)
        case "outlet", "switch", "light-ceiling", "light-wall", "panel", "smoke-detector":
            electricalParts(f.id, &p, W: W, D: D, H: H)
        case let id where terminalIDs.contains(id):
            terminalParts(id, &p, W: W, D: D, H: H)
        case let id where Trusses.kind(of: id) != nil:
            Trusses.parts(Trusses.kind(of: id)!, &p, W: W, D: D, H: H)
        case "person-standing", "person-walking", "person-child":
            Entourage.person(&p, width: W, depth: D, height: H, walking: f.id == "person-walking")
        case "bicycle":
            Entourage.bicycle(&p, width: W, depth: D, height: H)
        case "tree":
            let rx = W / 2, ry = D / 2, trunk = max(60, min(rx, ry) * 0.06)
            p.cyl("Bark", .zero, trunk, 0, H * 0.45)
            p.ellipsoid("Leaves", Vec3(0, 0, H * 0.63), rx * 0.85, ry * 0.85, H * 0.32)
            for k in 0..<4 {
                let a = Double(k) * Double.pi / 2 + 0.4
                p.ellipsoid("Leaves", Vec3(cos(a) * rx * 0.45, sin(a) * ry * 0.45, H * (0.55 + 0.08 * Double(k % 2))), rx * 0.5, ry * 0.5, H * 0.2)
            }
        case "shrub":
            let rx = W / 2, ry = D / 2
            p.ellipsoid("Leaves", Vec3(0, 0, H * 0.5), rx * 0.85, ry * 0.85, H * 0.5)
            p.ellipsoid("Leaves", Vec3(rx * 0.35, ry * 0.2, H * 0.4), rx * 0.55, ry * 0.55, H * 0.4)
            p.ellipsoid("Leaves", Vec3(-rx * 0.3, -ry * 0.25, H * 0.42), rx * 0.55, ry * 0.55, H * 0.42)
        case "parking":
            let lw = 100.0, t = max(min(H, 20), 2)
            p.box("Road Paint", x0, x0 + lw, y0, y1, 0, t); p.box("Road Paint", x1 - lw, x1, y0, y1, 0, t)
            p.box("Road Paint", x0 + lw, x1 - lw, y1 - lw, y1, 0, t)
        default:
            p.box("Wood", x0, x1, y0, y1, 0, H)
        }
        return p
    }

    /// World-space mesh groups of a family instance.
    static func meshGroups(_ f: ComponentFamily, _ g: ComponentGeom, id: EntityID?, z0: Double, overrides: [String: String]) -> [MeshGroup] {
        let parts = parts(f, size: g.size)
        let c = cos(g.rotation), s = sin(g.rotation)
        func P(_ p: Vec3) -> Vec3 { Vec3(g.position.x + p.x * c - p.y * s, g.position.y + p.x * s + p.y * c, z0 + p.z) }
        func N(_ n: Vec3) -> Vec3 { Vec3(n.x * c - n.y * s, n.x * s + n.y * c, n.z) }
        var out: [MeshGroup] = []
        for role in parts.order {
            guard var a = parts.accs[role], !a.mesh.isEmpty else { continue }
            a.mesh.positions = a.mesh.positions.map(P)
            a.mesh.normals = a.mesh.normals.map(N)
            a.edges = a.edges.map { $0.map(P) }
            out.append(MeshGroup(id: id, kind: "component", material: overrides["material." + role.lowercased()] ?? role, mesh: a.mesh, edges: a.edges))
        }
        return out
    }

    // MARK: 2D plan symbols

    /// Plan symbol lines in family-local coordinates.
    public static func symbol(_ f: ComponentFamily, size s: Vec3) -> [ComponentSymbolLine] {
        let W = max(s.x, 1), D = max(s.y, 1)
        let x0 = -W / 2, x1 = W / 2, y0 = -D / 2, y1 = D / 2
        var out: [ComponentSymbolLine] = []
        func add(_ pts: [Vec2], closed: Bool = false, outline: Bool = false, hidden: Bool = false) { out.append(ComponentSymbolLine(points: pts, closed: closed, outline: outline, hidden: hidden)) }
        func rect(_ a: Double, _ b: Double, _ c: Double, _ d: Double, outline: Bool = false, hidden: Bool = false) {
            add([Vec2(a, c), Vec2(b, c), Vec2(b, d), Vec2(a, d)], closed: true, outline: outline, hidden: hidden)
        }
        switch f.id {
        case "elevator":
            rect(x0, x1, y0, y1, outline: true)
            add([Vec2(x0, y0), Vec2(x1, y1)]); add([Vec2(x0, y1), Vec2(x1, y0)])
            let dw = min(W * 0.8, 900.0) / 2
            add([Vec2(-dw, y0 - 60), Vec2(dw, y0 - 60)], outline: true)
        case "escalator":
            // Outline, balustrades, treads, travel arrow; the part above the plan cut plane is dashed beyond a cut line.
            let e = Escalators.Section(width: W, length: D, rise: max(s.z, 1))
            let cutY = e.y(atHeight: Escalators.planCutHeight)
            rect(x0, x1, y0, y1, outline: true)
            let hw = e.stepWidth / 2
            for x in [-hw - 60, hw + 60] {
                add([Vec2(x, y0), Vec2(x, cutY)], outline: true)
                if cutY < y1 { add([Vec2(x, cutY), Vec2(x, y1)], hidden: true) }
            }
            for y in e.treadLines() { add([Vec2(-hw, y), Vec2(hw, y)], hidden: y > cutY) }
            // Cut line: double zig-zag across the flight at the cut position.
            let z = min(150.0, hw / 3)
            add([Vec2(x0, cutY - z), Vec2(-z, cutY - z), Vec2(0, cutY + z), Vec2(z, cutY - z), Vec2(x1, cutY - z)], outline: true)
            // Travel arrow (up direction) from the lower landing to the cut.
            let a0 = y0 + e.landing / 2, a1 = max(a0 + 1, cutY - 2 * z)
            add([Vec2(0, a0), Vec2(0, a1)])
            add([Vec2(-z, a1 - 2 * z), Vec2(0, a1), Vec2(z, a1 - 2 * z)])
            add([Vec2(-hw / 2, y0 + 60), Vec2(hw / 2, y0 + 60)], outline: true)   // comb plate
        case "bed-single", "bed-double":
            rect(x0, x1, y0, y1, outline: true)
            rect(x0, x1, y1 - 60, y1)
            let n = W >= 1200 ? 2 : 1
            let pw = (W - 60 - 40 * Double(n - 1)) / Double(n)
            for i in 0..<n { let px = x0 + 30 + Double(i) * (pw + 40); add(roundedRect(px, px + pw, y1 - 460, y1 - 100, 60), closed: true) }
            let foldY = y0 + (D - 80) * 0.7
            add([Vec2(x0, foldY), Vec2(x1, foldY)])
            add([Vec2(x1 - 10, foldY), Vec2(x1 - 10 - min(300, W * 0.3), foldY - min(300, W * 0.3)), Vec2(x1 - 10, foldY - min(300, W * 0.3))])
        case "sofa", "armchair":
            let arm = min(180, W * 0.2), back = min(200, D * 0.25)
            add(roundedRect(x0, x1, y0, y1, 40), closed: true, outline: true)
            rect(x0, x0 + arm, y0, y1); rect(x1 - arm, x1, y0, y1); rect(x0 + arm, x1 - arm, y1 - back, y1)
            let n = f.id == "armchair" ? 1 : (W - 2 * arm > 1500 ? 3 : 2)
            let cw = (W - 2 * arm) / Double(n)
            for i in 1..<max(n, 1) where n > 1 { let x = x0 + arm + Double(i) * cw; add([Vec2(x, y0), Vec2(x, y1 - back)]) }
        case "chair":
            rect(x0, x1, y0, y1, outline: true)
            rect(x0, x1, y1 - 35, y1)
        case "table", "desk":
            rect(x0, x1, y0, y1, outline: true)
            if f.id == "desk" { let ped = min(400, W * 0.35); add([Vec2(x0 + ped, y0), Vec2(x0 + ped, y1)], hidden: true) }
        case "coffee-table":
            rect(x0, x1, y0, y1, outline: true); rect(x0 + 40, x1 - 40, y0 + 40, y1 - 40)
        case "table-round":
            add(ellipse(.zero, W / 2, D / 2, segments: 48), closed: true, outline: true)
        case "wardrobe":
            rect(x0, x1, y0, y1, outline: true)
            add([Vec2(x0, y0 + 20), Vec2(x1, y0 + 20)])
            let yc = (y0 + 20 + y1) / 2
            add([Vec2(x0 + 30, yc), Vec2(x1 - 30, yc)])
            var x = x0 + 120
            while x < x1 - 100 { add([Vec2(x - 60, yc - (D - 20) * 0.35), Vec2(x + 60, yc + (D - 20) * 0.35)]); x += 150 }
        case "bookshelf", "nightstand", "kitchen-base", "fridge", "washer":
            rect(x0, x1, y0, y1, outline: true)
            add([Vec2(x0, y0 + 20), Vec2(x1, y0 + 20)])
            if f.id == "kitchen-base" {
                let n = max(1, Int((W / 600).rounded()))
                for i in 1..<max(n, 1) where n > 1 { let x = x0 + W * Double(i) / Double(n); add([Vec2(x, y0), Vec2(x, y0 + 20)]) }
            }
            if f.id == "fridge" { add([Vec2(x0, y0), Vec2(x1, y1)]); add([Vec2(x1, y0), Vec2(x0, y1)]) }
            if f.id == "washer" { add(RG.circle(Vec2(0, 0), min(W, D) * 0.3, segments: 32), closed: true) }
        case "kitchen-wall":
            rect(x0, x1, y0, y1, outline: true, hidden: true)
            add([Vec2(x0, y0), Vec2(x1, y1)], hidden: true)
        case "kitchen-sink":
            rect(x0, x1, y0, y1, outline: true)
            let bw = min(W - 200, 800), bd = min(D - 200, 420), by0 = y0 + (D - bd) / 2 - 20
            add(roundedRect(-bw / 2, bw / 2, by0, by0 + bd, 60), closed: true)
            add(RG.circle(Vec2(0, by0 + bd / 2), 30, segments: 16), closed: true)
            add(RG.circle(Vec2(0, by0 + bd + 45), 22, segments: 16), closed: true)
        case "range":
            rect(x0, x1, y0, y1, outline: true)
            for (cx, cy) in [(-W / 4, -D / 5), (W / 4, -D / 5), (-W / 4, D / 5), (W / 4, D / 5)] { add(RG.circle(Vec2(cx, cy), min(W, D) * 0.14, segments: 24), closed: true) }
        case "wc":
            let cist = min(180, D * 0.28), bl = D - cist
            rect(x0, x1, y1 - cist, y1, outline: true)
            add(ellipse(Vec2(0, y0 + bl / 2), W / 2, bl / 2), closed: true, outline: true)
            add(ellipse(Vec2(0, y0 + bl / 2 + 20), W * 0.32, bl * 0.32), closed: true)
        case "basin":
            add(roundedRect(x0, x1, y0, y1, 80), closed: true, outline: true)
            add(ellipse(Vec2(0, -D * 0.05), W * 0.36, D * 0.3), closed: true)
            add(RG.circle(Vec2(0, y1 - 50), 18, segments: 12), closed: true)
        case "shower":
            rect(x0, x1, y0, y1, outline: true)
            add([Vec2(x0, y0), Vec2(x1, y1)]); add([Vec2(x1, y0), Vec2(x0, y1)])
            add(RG.circle(.zero, 45, segments: 16), closed: true)
        case "bath":
            let t = min(70, W * 0.1)
            add(roundedRect(x0, x1, y0, y1, 30), closed: true, outline: true)
            add(roundedRect(x0 + t, x1 - t, y0 + t, y1 - t, min(W, D) * 0.25, segments: 6), closed: true)
            add(RG.circle(Vec2(0, y1 - t - 120), 30, segments: 12), closed: true)
        case "car":
            add(roundedRect(x0 + 30, x1 - 30, y0, y1, min(W, D) * 0.12, segments: 5), closed: true, outline: true)
            add([Vec2(x0 + 80, y0 + D * 0.29), Vec2(x1 - 80, y0 + D * 0.29)])
            add([Vec2(x0 + 110, y0 + D * 0.42), Vec2(x1 - 110, y0 + D * 0.42), Vec2(x1 - 110, y0 + D * 0.77), Vec2(x0 + 110, y0 + D * 0.77)], closed: true)
            add([Vec2(x0 + 80, y0 + D * 0.90), Vec2(x1 - 80, y0 + D * 0.90)])
            rect(x0 - 10, x0 + 30, y0 + D * 0.27, y0 + D * 0.31); rect(x1 - 30, x1 + 10, y0 + D * 0.27, y0 + D * 0.31)
        case "tree", "shrub":
            let r = min(W, D) / 2, sx = W / 2 / r, sy = D / 2 / r
            let lobes = f.id == "tree" ? 11 : 8
            var canopy: [Vec2] = []
            for i in 0..<(lobes * 6) {
                let a = 2 * Double.pi * Double(i) / Double(lobes * 6)
                let k = Double(i % 6) / 6
                let q = Vec2.polar(r * (0.9 + 0.1 * sin(k * Double.pi)), a)
                canopy.append(Vec2(q.x * sx, q.y * sy))
            }
            add(canopy, closed: true, outline: true)
            if f.id == "tree" {
                add(RG.circle(.zero, max(60, r * 0.06), segments: 16), closed: true)
                for k in 0..<6 { let a = Double(k) * Double.pi / 3 + 0.2; add([Vec2.polar(r * 0.1, a), Vec2.polar(r * 0.55, a + 0.15)]) }
            } else {
                add(RG.circle(.zero, r * 0.45, segments: 24), closed: true)
            }
        case "parking":
            add([Vec2(x0, y0), Vec2(x0, y1), Vec2(x1, y1), Vec2(x1, y0)], outline: true)
        case "outlet", "switch", "light-ceiling", "light-wall", "panel", "smoke-detector":
            out += electricalSymbol(f.id, W: W, D: D)
        case let id where terminalIDs.contains(id):
            out += terminalSymbol(id, W: W, D: D)
        case let id where Trusses.kind(of: id) != nil:
            rect(x0, x1, y0, y1, outline: true)
            add([Vec2(x0, 0), Vec2(x1, 0)])
        case "person-standing", "person-walking", "person-child", "bicycle":
            for l in Entourage.symbol(f.id, width: W, depth: D, height: max(s.z, 1)) { add(l.points, closed: l.closed, outline: l.outline) }
        default:
            rect(x0, x1, y0, y1, outline: true)
        }
        return out
    }

    /// Plan symbol of an instance in world coordinates.
    public static func worldSymbol(_ f: ComponentFamily, _ g: ComponentGeom) -> [ComponentSymbolLine] {
        let t = Transform2D.translation(g.position) * Transform2D.rotation(g.rotation)
        return symbol(f, size: g.size).map { var l = $0; l.points = l.points.map(t.apply); return l }
    }
}
