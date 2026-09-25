// Oanarina Archi Tool — GPL-3.0-or-later
// FBX exchange (IO-039), written from the public descriptions of the format (Blender's io_scene_fbx notes, the
// "FBX binary file format specification" by Blender developers): binary FBX 7.4 export of the model's meshes with
// materials (diffuse colour, opacity), millimetre units (UnitScaleFactor 0.1) and Z up; import of binary (7.x, zlib
// arrays) and ASCII FBX meshes with their model transforms (translation, rotation XYZ, scaling), units, up axis and
// material colours.
import Foundation

public indirect enum FBXValue: Equatable {
    case i(Int64), d(Double), s(String), b(Bool), raw(Data)
    case ia([Int64]), da([Double])
    var int: Int64? { if case .i(let v) = self { return v }; if case .d(let v) = self { return Int64(v) }; return nil }
    var double: Double? { if case .d(let v) = self { return v }; if case .i(let v) = self { return Double(v) }; return nil }
    var string: String? { if case .s(let v) = self { return v }; return nil }
    var doubles: [Double] { if case .da(let a) = self { return a }; if case .ia(let a) = self { return a.map(Double.init) }; return [] }
    var ints: [Int64] { if case .ia(let a) = self { return a }; if case .da(let a) = self { return a.map { Int64($0) } }; return [] }
}

public final class FBXNode {
    public var name: String
    public var props: [FBXValue]
    public var children: [FBXNode]
    public init(_ name: String, _ props: [FBXValue] = [], _ children: [FBXNode] = []) { self.name = name; self.props = props; self.children = children }
    public func child(_ n: String) -> FBXNode? { children.first { $0.name == n } }
    public func all(_ n: String) -> [FBXNode] { children.filter { $0.name == n } }
    /// Properties70 value by name: `P: "Name", "type", "label", "flags", values…`.
    public func p70(_ n: String) -> [FBXValue]? { child("Properties70")?.all("P").first { $0.props.first?.string == n }.map { Array($0.props.dropFirst(4)) } }
}

public enum FBX {
    public struct FBXError: Error, LocalizedError { public let message: String; public var errorDescription: String? { message } }
    static let magic = Array("Kaydara FBX Binary  ".utf8) + [0x00, 0x1A, 0x00]

    // MARK: binary writer

    static func writeBinary(_ nodes: [FBXNode], version: UInt32 = 7400) -> Data {
        var out = Data(magic)
        func u32(_ v: UInt32) { var x = v.littleEndian; out.append(Data(bytes: &x, count: 4)) }
        func put32(_ v: UInt32, at o: Int) { var x = v.littleEndian; out.replaceSubrange(o..<(o + 4), with: Data(bytes: &x, count: 4)) }
        u32(version)
        func prop(_ p: FBXValue) {
            switch p {
            case .i(let v):
                if v >= Int64(Int32.min) && v <= Int64(Int32.max) { out.append(UInt8(ascii: "I")); var x = Int32(v).littleEndian; out.append(Data(bytes: &x, count: 4)) }
                else { out.append(UInt8(ascii: "L")); var x = v.littleEndian; out.append(Data(bytes: &x, count: 8)) }
            case .d(let v): out.append(UInt8(ascii: "D")); var x = v.bitPattern.littleEndian; out.append(Data(bytes: &x, count: 8))
            case .b(let v): out.append(UInt8(ascii: "C")); out.append(v ? 1 : 0)
            case .s(let v): out.append(UInt8(ascii: "S")); let d = Data(v.utf8); u32(UInt32(d.count)); out.append(d)
            case .raw(let d): out.append(UInt8(ascii: "R")); u32(UInt32(d.count)); out.append(d)
            case .ia(let a):
                out.append(UInt8(ascii: "i")); u32(UInt32(a.count)); u32(0); u32(UInt32(a.count * 4))
                for v in a { var x = Int32(clamping: v).littleEndian; out.append(Data(bytes: &x, count: 4)) }
            case .da(let a):
                out.append(UInt8(ascii: "d")); u32(UInt32(a.count)); u32(0); u32(UInt32(a.count * 8))
                for v in a { var x = v.bitPattern.littleEndian; out.append(Data(bytes: &x, count: 8)) }
            }
        }
        func node(_ n: FBXNode) {
            let start = out.count
            u32(0); u32(UInt32(n.props.count)); u32(0)
            let name = Data(n.name.utf8); out.append(UInt8(name.count)); out.append(name)
            let ps = out.count
            n.props.forEach(prop)
            put32(UInt32(out.count - ps), at: start + 8)
            if !n.children.isEmpty || n.props.isEmpty {
                n.children.forEach(node)
                out.append(Data(count: 13))
            }
            put32(UInt32(out.count), at: start)
        }
        nodes.forEach(node)
        out.append(Data(count: 13))
        // Footer: id, padding to 16, version, 120 zero bytes, magic.
        out.append(Data([0xfa, 0xbc, 0xab, 0x09, 0xd0, 0xc8, 0xd4, 0x66, 0xb1, 0x76, 0xfb, 0x83, 0x1c, 0xf7, 0x26, 0x7e]))
        out.append(Data(count: 4))
        let pad = (16 - out.count % 16) % 16
        out.append(Data(count: pad))
        u32(version)
        out.append(Data(count: 120))
        out.append(Data([0xf8, 0x5a, 0x8c, 0x6a, 0xde, 0xf5, 0xd9, 0x7e, 0xec, 0xe9, 0x0c, 0xe3, 0x75, 0x8f, 0x29, 0x0b]))
        return out
    }

    // MARK: binary reader

    public static func readBinary(_ data: Data) throws -> [FBXNode] {
        let b = [UInt8](data)
        guard b.count > 27, Array(b[0..<21]) == Array(magic.prefix(21)) else { throw FBXError(message: "Not a binary FBX file.") }
        var i = 23
        func u32() throws -> UInt64 { guard i + 4 <= b.count else { throw FBXError(message: "Truncated FBX.") }; defer { i += 4 }; return UInt64(b[i]) | UInt64(b[i + 1]) << 8 | UInt64(b[i + 2]) << 16 | UInt64(b[i + 3]) << 24 }
        func u64() throws -> UInt64 { let lo = try u32(); let hi = try u32(); return lo | hi << 32 }
        let version = try u32()
        let wide = version >= 7500
        func readNode() throws -> FBXNode? {
            let end = wide ? try u64() : try u32()
            let np = wide ? try u64() : try u32()
            _ = wide ? try u64() : try u32()
            guard i < b.count else { throw FBXError(message: "Truncated FBX.") }
            let nameLen = Int(b[i]); i += 1
            if end == 0 { return nil }
            guard i + nameLen <= b.count, Int(end) <= b.count else { throw FBXError(message: "Truncated FBX node.") }
            let name = String(decoding: b[i..<(i + nameLen)], as: UTF8.self); i += nameLen
            var props: [FBXValue] = []
            for _ in 0..<np {
                guard i < b.count else { throw FBXError(message: "Truncated FBX property.") }
                let t = b[i]; i += 1
                func scalar(_ n: Int) throws -> [UInt8] { guard i + n <= b.count else { throw FBXError(message: "Truncated FBX.") }; defer { i += n }; return Array(b[i..<(i + n)]) }
                func le(_ bytes: [UInt8]) -> UInt64 { bytes.enumerated().reduce(0) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) } }
                switch t {
                case UInt8(ascii: "Y"): props.append(.i(Int64(Int16(bitPattern: UInt16(le(try scalar(2)))))))
                case UInt8(ascii: "C"): let c = try scalar(1); props.append(.b(c[0] != 0))
                case UInt8(ascii: "I"): props.append(.i(Int64(Int32(bitPattern: UInt32(le(try scalar(4)))))))
                case UInt8(ascii: "F"): props.append(.d(Double(Float(bitPattern: UInt32(le(try scalar(4)))))))
                case UInt8(ascii: "D"): props.append(.d(Double(bitPattern: le(try scalar(8)))))
                case UInt8(ascii: "L"): props.append(.i(Int64(bitPattern: le(try scalar(8)))))
                case UInt8(ascii: "S"), UInt8(ascii: "R"):
                    let n = Int(try u32())
                    let bytes = try scalar(n)
                    props.append(t == UInt8(ascii: "S") ? .s(String(decoding: bytes, as: UTF8.self)) : .raw(Data(bytes)))
                case UInt8(ascii: "f"), UInt8(ascii: "d"), UInt8(ascii: "l"), UInt8(ascii: "i"), UInt8(ascii: "b"):
                    let count = Int(try u32()), enc = try u32(), clen = Int(try u32())
                    var raw = Data(try scalar(clen))
                    if enc == 1 {
                        // zlib stream: skip the 2-byte header, inflate the raw DEFLATE data.
                        // zlib = 2-byte header + DEFLATE + 4-byte Adler-32.
                        guard raw.count > 6 else { throw FBXError(message: "Cannot inflate an FBX array.") }
                        if let d = try? (raw.subdata(in: 2..<(raw.count - 4)) as NSData).decompressed(using: .zlib) as Data { raw = d }
                        else if let d = try? (raw.subdata(in: 2..<raw.count) as NSData).decompressed(using: .zlib) as Data { raw = d }
                        else { throw FBXError(message: "Cannot inflate an FBX array.") }
                    }
                    let r = [UInt8](raw)
                    let size = t == UInt8(ascii: "f") || t == UInt8(ascii: "i") ? 4 : t == UInt8(ascii: "b") ? 1 : 8
                    guard r.count >= count * size else { throw FBXError(message: "Bad FBX array.") }
                    func at(_ k: Int) -> UInt64 { (0..<size).reduce(0) { $0 | UInt64(r[k * size + $1]) << (8 * UInt64($1)) } }
                    switch t {
                    case UInt8(ascii: "f"): props.append(.da((0..<count).map { Double(Float(bitPattern: UInt32(at($0)))) }))
                    case UInt8(ascii: "d"): props.append(.da((0..<count).map { Double(bitPattern: at($0)) }))
                    case UInt8(ascii: "i"): props.append(.ia((0..<count).map { Int64(Int32(bitPattern: UInt32(at($0)))) }))
                    case UInt8(ascii: "l"): props.append(.ia((0..<count).map { Int64(bitPattern: at($0)) }))
                    default: props.append(.ia((0..<count).map { Int64(r[$0]) }))
                    }
                default: throw FBXError(message: "Unknown FBX property type \(Character(UnicodeScalar(t))).")
                }
            }
            var children: [FBXNode] = []
            while i < Int(end) {
                guard let c = try readNode() else { break }
                children.append(c)
            }
            i = Int(end)
            return FBXNode(name, props, children)
        }
        var out: [FBXNode] = []
        while i < b.count - 13 {
            guard let n = try readNode() else { break }
            out.append(n)
        }
        return out
    }

    // MARK: ASCII reader

    public static func readASCII(_ text: String) throws -> [FBXNode] {
        let s = Array(text.unicodeScalars)
        var i = 0
        func ws() {
            while i < s.count {
                if s[i] == ";" { while i < s.count && s[i] != "\n" { i += 1 } }
                else if CharacterSet.whitespacesAndNewlines.contains(s[i]) { i += 1 } else { break }
            }
        }
        func ident() -> String { var o = ""; while i < s.count, CharacterSet.alphanumerics.contains(s[i]) || s[i] == "_" || s[i] == "|" { o.unicodeScalars.append(s[i]); i += 1 }; return o }
        func value() -> FBXValue? {
            ws()
            guard i < s.count else { return nil }
            if s[i] == "\"" {
                i += 1; var o = ""
                while i < s.count && s[i] != "\"" { o.unicodeScalars.append(s[i]); i += 1 }
                i += 1; return .s(o)
            }
            if s[i] == "*" {
                // Array: *N { a: v,v,v }
                i += 1; while i < s.count, CharacterSet.decimalDigits.contains(s[i]) { i += 1 }
                ws(); guard i < s.count, s[i] == "{" else { return nil }
                i += 1; ws()
                _ = ident(); ws(); if i < s.count, s[i] == ":" { i += 1 }
                var nums: [Double] = [], cur = "", isInt = true
                while i < s.count && s[i] != "}" {
                    let c = s[i]
                    if c == "," || CharacterSet.whitespacesAndNewlines.contains(c) { if let v = Double(cur) { nums.append(v); if cur.contains(".") || cur.contains("e") || cur.contains("E") { isInt = false } }; cur = "" }
                    else { cur.unicodeScalars.append(c) }
                    i += 1
                }
                if let v = Double(cur) { nums.append(v); if cur.contains(".") || cur.contains("e") { isInt = false } }
                i += 1
                return isInt ? .ia(nums.map { Int64($0) }) : .da(nums)
            }
            var tok = ""
            while i < s.count, !",{}\n\r".unicodeScalars.contains(s[i]) { tok.unicodeScalars.append(s[i]); i += 1 }
            tok = tok.trimmingCharacters(in: .whitespaces)
            if tok == "T" || tok == "Y" { return .b(true) }
            if tok == "F" || tok == "N" { return .b(false) }
            if let v = Int64(tok) { return .i(v) }
            if let v = Double(tok) { return .d(v) }
            return tok.isEmpty ? nil : .s(tok)
        }
        func nodes(untilBrace: Bool) -> [FBXNode] {
            var out: [FBXNode] = []
            while true {
                ws()
                guard i < s.count else { break }
                if s[i] == "}" { if untilBrace { i += 1 }; break }
                let name = ident()
                ws()
                guard !name.isEmpty, i < s.count, s[i] == ":" else { i += 1; continue }
                i += 1
                var props: [FBXValue] = []
                var children: [FBXNode] = []
                while true {
                    ws()
                    guard i < s.count else { break }
                    if s[i] == "{" { i += 1; children = nodes(untilBrace: true); break }
                    if s[i] == "}" || (s[i] != "\"" && s[i] != "*" && s[i] != "-" && !CharacterSet.decimalDigits.contains(s[i]) && !props.isEmpty && s[i] != ",") { break }
                    if s[i] == "," { i += 1; continue }
                    guard let v = value() else { break }
                    props.append(v)
                    // A new line ends the property list unless a '{' or ',' follows.
                    var j = i
                    while j < s.count, s[j] == " " || s[j] == "\t" { j += 1 }
                    if j < s.count, s[j] == "\n" || s[j] == "\r" {
                        var k = j
                        while k < s.count, CharacterSet.whitespacesAndNewlines.contains(s[k]) { k += 1 }
                        if k < s.count, s[k] == "{" { i = k; continue }
                        i = j; break
                    }
                }
                out.append(FBXNode(name, props, children))
            }
            return out
        }
        let out = nodes(untilBrace: false)
        guard out.contains(where: { $0.name == "Objects" }) else { throw FBXError(message: "Not an FBX file (no Objects).") }
        return out
    }

    public static func read(_ data: Data) throws -> [FBXNode] {
        if data.starts(with: Array("Kaydara FBX Binary".utf8)) { return try readBinary(data) }
        return try readASCII(String(decoding: data, as: UTF8.self))
    }

    // MARK: import to entities

    /// Meshes of an FBX file as mesh solids in millimetres, Z up, with materials (diffuse colour, opacity).
    public static func entities(_ data: Data) throws -> (entities: [Entity], materials: [Material]) {
        let top = try read(data)
        guard let objects = top.first(where: { $0.name == "Objects" }) else { throw FBXError(message: "No Objects in the FBX file.") }
        let gs = top.first { $0.name == "GlobalSettings" }
        let unitCM = gs?.p70("UnitScaleFactor")?.first?.double ?? 1
        let k = unitCM * 10   // file units → mm
        let upAxis = gs?.p70("UpAxis")?.first?.int ?? 1
        // Connections: child → parents.
        var parents: [Int64: [Int64]] = [:]
        for c in top.first(where: { $0.name == "Connections" })?.all("C") ?? [] {
            guard c.props.count >= 3, let a = c.props[1].int, let b = c.props[2].int else { continue }
            parents[a, default: []].append(b)
        }
        var models: [Int64: FBXNode] = [:], materialsByID: [Int64: Material] = [:]
        for m in objects.all("Model") { if let id = m.props.first?.int { models[id] = m } }
        for m in objects.all("Material") {
            guard let id = m.props.first?.int else { continue }
            let raw = m.props.count > 1 ? (m.props[1].string ?? "Material") : "Material"
            let name = raw.components(separatedBy: "\u{0}\u{1}").first.map { $0.hasPrefix("Material::") ? String($0.dropFirst(10)) : $0 } ?? raw
            let c = m.p70("DiffuseColor") ?? m.p70("Diffuse")
            let col = c.map { v -> RGBA in let d = v.compactMap(\.double); return d.count >= 3 ? RGBA(d[0], d[1], d[2]) : RGBA(0.8, 0.8, 0.8) } ?? RGBA(0.8, 0.8, 0.8)
            var mat = Material(name: name.isEmpty ? "FBX material" : name, color: col)
            if let o = m.p70("Opacity")?.first?.double { mat.transparency = max(0, min(1, 1 - o)) }
            else if let t = m.p70("TransparencyFactor")?.first?.double, t > 0 { mat.transparency = max(0, min(1, t)) }
            materialsByID[id] = mat
        }
        func matrix(_ m: FBXNode) -> USDMatrix {
            let t = m.p70("Lcl Translation")?.compactMap(\.double) ?? [0, 0, 0]
            let r = m.p70("Lcl Rotation")?.compactMap(\.double) ?? [0, 0, 0]
            let s = m.p70("Lcl Scaling")?.compactMap(\.double) ?? [1, 1, 1]
            var mm = USDMatrix.op("xformOp:translate", t) ?? .identity
            if let rot = USDMatrix.op("xformOp:rotateXYZ", r) { mm = mm * rot }
            if let sc = USDMatrix.op("xformOp:scale", s) { mm = mm * sc }
            return mm
        }
        func world(_ modelID: Int64, depth: Int = 0) -> USDMatrix {
            guard depth < 32, let m = models[modelID] else { return .identity }
            let parent = (parents[modelID] ?? []).first { models[$0] != nil }
            return (parent.map { world($0, depth: depth + 1) } ?? .identity) * matrix(m)
        }
        var ents: [Entity] = []
        var usedMats: [Material] = []
        for g in objects.all("Geometry") {
            guard let gid = g.props.first?.int, let v = g.child("Vertices")?.props.first?.doubles, let idx = g.child("PolygonVertexIndex")?.props.first?.ints, v.count >= 9 else { continue }
            let model = (parents[gid] ?? []).first { models[$0] != nil }
            let wm = model.map { world($0) } ?? .identity
            let verts = stride(from: 0, to: v.count - 2, by: 3).map { i -> Vec3 in
                var p = wm.apply(Vec3(v[i], v[i + 1], v[i + 2])) * k
                if upAxis == 1 { p = Vec3(p.x, -p.z, p.y) }
                return p
            }
            var tris: [Int] = []
            var poly: [Int] = []
            for raw in idx {
                let end = raw < 0
                poly.append(Int(end ? ~raw : raw))
                if end {
                    if poly.count >= 3, poly.allSatisfy({ $0 >= 0 && $0 < verts.count }) { for j in 1..<(poly.count - 1) { tris += [poly[0], poly[j], poly[j + 1]] } }
                    poly = []
                }
            }
            guard !tris.isEmpty else { continue }
            var e = Entity(layer: "IMPORT-FBX", geometry: .solid(SolidGeom(kind: .mesh, origin: .zero, meshVertices: verts, meshTriangles: tris)))
            let name = model.flatMap { models[$0]?.props.dropFirst().first?.string }?.components(separatedBy: "\u{0}\u{1}").first ?? ""
            e.props["name"] = name.hasPrefix("Model::") ? String(name.dropFirst(7)) : name
            if let mid = model, let matID = (parents.filter { $0.value.contains(mid) && materialsByID[$0.key] != nil }).keys.sorted().first, let mat = materialsByID[matID] {
                e.props["material"] = mat.name
                if !usedMats.contains(where: { $0.name == mat.name }) { usedMats.append(mat) }
            }
            ents.append(e)
        }
        guard !ents.isEmpty else { throw FBXError(message: "The FBX file has no meshes.") }
        return (ents, usedMats)
    }

    // MARK: export

    /// Binary FBX 7.4 of mesh groups (drawing units `unitMM`), one model + geometry per group, materials shared by name.
    public static func export(_ groups: [MeshGroup], materials: [Material], unitMM: Double, name: String = "Model") -> Data {
        var nextID: Int64 = 1_000_000
        func id() -> Int64 { nextID += 1; return nextID }
        func P(_ n: String, _ t: String, _ l: String, _ f: String, _ v: [FBXValue]) -> FBXNode { FBXNode("P", [.s(n), .s(t), .s(l), .s(f)] + v) }
        var objects: [FBXNode] = [], conns: [FBXNode] = []
        var matIDs: [String: Int64] = [:]
        var nModels = 0, nGeoms = 0
        for g in groups {
            let tris = MeshExport.triangles(g.mesh)
            guard !tris.isEmpty else { continue }
            let gid = id(), mid = id()
            let verts = g.mesh.positions.flatMap { [$0.x * unitMM, $0.y * unitMM, $0.z * unitMM] }
            var pvi: [Int64] = []
            var t = 0
            while t + 2 < tris.count { pvi += [Int64(tris[t]), Int64(tris[t + 1]), ~Int64(tris[t + 2])]; t += 3 }
            let label = "\(g.kind)\(g.id.map { " \($0)" } ?? "")"
            objects.append(FBXNode("Geometry", [.i(gid), .s("\(label)\u{0}\u{1}Geometry"), .s("Mesh")], [
                FBXNode("Vertices", [.da(verts)]), FBXNode("PolygonVertexIndex", [.ia(pvi)]), FBXNode("GeometryVersion", [.i(124)]),
                FBXNode("LayerElementMaterial", [.i(0)], [FBXNode("Version", [.i(101)]), FBXNode("Name", [.s("")]), FBXNode("MappingInformationType", [.s("AllSame")]),
                                                          FBXNode("ReferenceInformationType", [.s("IndexToDirect")]), FBXNode("Materials", [.ia([0])])]),
                FBXNode("Layer", [.i(0)], [FBXNode("Version", [.i(100)]), FBXNode("LayerElement", [], [FBXNode("Type", [.s("LayerElementMaterial")]), FBXNode("TypedIndex", [.i(0)])])]),
            ]))
            objects.append(FBXNode("Model", [.i(mid), .s("\(label)\u{0}\u{1}Model"), .s("Mesh")], [
                FBXNode("Version", [.i(232)]),
                FBXNode("Properties70", [], [P("Lcl Translation", "Lcl Translation", "", "A", [.d(0), .d(0), .d(0)]), P("Lcl Rotation", "Lcl Rotation", "", "A", [.d(0), .d(0), .d(0)]),
                                             P("Lcl Scaling", "Lcl Scaling", "", "A", [.d(1), .d(1), .d(1)])]),
                FBXNode("Shading", [.b(true)]), FBXNode("Culling", [.s("CullingOff")]),
            ]))
            nModels += 1; nGeoms += 1
            conns.append(FBXNode("C", [.s("OO"), .i(mid), .i(0)]))
            conns.append(FBXNode("C", [.s("OO"), .i(gid), .i(mid)]))
            let mname = g.material.isEmpty ? "Default" : g.material
            let matID: Int64
            if let m = matIDs[mname.lowercased()] { matID = m } else {
                matID = id(); matIDs[mname.lowercased()] = matID
                let m = materials.first { $0.name.caseInsensitiveCompare(mname) == .orderedSame } ?? Material(name: mname, color: RGBA(0.8, 0.8, 0.8))
                objects.append(FBXNode("Material", [.i(matID), .s("\(m.name)\u{0}\u{1}Material"), .s("")], [
                    FBXNode("Version", [.i(102)]), FBXNode("ShadingModel", [.s("phong")]), FBXNode("MultiLayer", [.i(0)]),
                    FBXNode("Properties70", [], [P("DiffuseColor", "Color", "", "A", [.d(m.color.r), .d(m.color.g), .d(m.color.b)]),
                                                 P("Opacity", "double", "Number", "", [.d(1 - m.transparency)]),
                                                 P("Shininess", "double", "Number", "", [.d(max(2, (1 - m.roughness) * 100))])]),
                ]))
            }
            conns.append(FBXNode("C", [.s("OO"), .i(matID), .i(mid)]))
        }
        let header = FBXNode("FBXHeaderExtension", [], [FBXNode("FBXHeaderVersion", [.i(1003)]), FBXNode("FBXVersion", [.i(7400)]), FBXNode("Creator", [.s("Oanarina Archi Tool")])])
        let global = FBXNode("GlobalSettings", [], [FBXNode("Version", [.i(1000)]), FBXNode("Properties70", [], [
            P("UpAxis", "int", "Integer", "", [.i(2)]), P("UpAxisSign", "int", "Integer", "", [.i(1)]), P("FrontAxis", "int", "Integer", "", [.i(1)]),
            P("FrontAxisSign", "int", "Integer", "", [.i(-1)]), P("CoordAxis", "int", "Integer", "", [.i(0)]), P("CoordAxisSign", "int", "Integer", "", [.i(1)]),
            P("OriginalUpAxis", "int", "Integer", "", [.i(2)]), P("UnitScaleFactor", "double", "Number", "", [.d(0.1)]), P("OriginalUnitScaleFactor", "double", "Number", "", [.d(0.1)]),
        ])])
        let defs = FBXNode("Definitions", [], [FBXNode("Version", [.i(100)]), FBXNode("Count", [.i(Int64(nModels + nGeoms + matIDs.count + 1))]),
                                               FBXNode("ObjectType", [.s("GlobalSettings")], [FBXNode("Count", [.i(1)])]),
                                               FBXNode("ObjectType", [.s("Model")], [FBXNode("Count", [.i(Int64(nModels))])]),
                                               FBXNode("ObjectType", [.s("Geometry")], [FBXNode("Count", [.i(Int64(nGeoms))])]),
                                               FBXNode("ObjectType", [.s("Material")], [FBXNode("Count", [.i(Int64(matIDs.count))])])])
        let docs = FBXNode("Documents", [], [FBXNode("Count", [.i(1)]), FBXNode("Document", [.i(1), .s(name), .s("Scene")], [FBXNode("RootNode", [.i(0)])])])
        return writeBinary([header, global, docs, FBXNode("References"), defs, FBXNode("Objects", [], objects), FBXNode("Connections", [], conns)])
    }
}
