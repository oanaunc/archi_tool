// Oanarina Archi Tool — GPL-3.0-or-later
// BIM Collaboration Format 2.1 (buildingSMART): markups exported as topics (markup.bcf with comments and a
// viewpoint.bcfv holding the camera and the selected components by IFC GlobalId) in a .bcfzip, and imported back.
import Foundation

public struct BCFTopic: Hashable {
    public var guid: String
    public var title: String
    public var status: String          // Open / Closed
    public var type: String
    public var author: String
    public var date: String
    public var description: String
    public var comments: [BCFComment]
    public var viewpoint: BCFViewpoint?
}

public struct BCFComment: Hashable {
    public var guid: String
    public var author: String
    public var date: String
    public var text: String
}

public struct BCFViewpoint: Hashable {
    public var guid: String
    /// Camera in metres (BCF world coordinates).
    public var position: Vec3
    public var direction: Vec3
    public var up: Vec3
    /// Perspective field of view (degrees) or orthogonal view-to-world scale (m); `orthogonal` selects which.
    public var fieldOfView: Double
    public var viewToWorldScale: Double
    public var orthogonal: Bool
    public var selection: [String]
}

public enum BCFError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let m) = self { return "Invalid BCF: \(m)" }; return nil }
}

public enum BCF {
    static func esc(_ s: String) -> String { XLSX.esc(s) }
    static func n(_ v: Double) -> String { fmt(v, 6) }

    static func uuid(_ s: String) -> String {
        if UUID(uuidString: s) != nil { return s.lowercased() }
        // Deterministic UUID-shaped id from any string (markup ids are UUIDs already).
        var h: UInt64 = 1469598103934665603, h2: UInt64 = 1099511628211
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211; h2 = (h2 ^ UInt64(b)) &* 14695981039346656037 }
        let hex = String(format: "%016llx%016llx", h, h2)
        let c = Array(hex)
        return String(c[0..<8]) + "-" + String(c[8..<12]) + "-4" + String(c[13..<16]) + "-a" + String(c[17..<20]) + "-" + String(c[20..<32])
    }

    /// IFC GlobalId of a BIM element or entity, as the IFC exporter writes it.
    public static func ifcGuid(_ id: EntityID, doc: ArchiDocument) -> String {
        if let el = doc.element(id) {
            if let v = el.props["ifcGuid"], IFCExporter.isValidGuid(v) { return v }
            return IFCExporter.guid("element:\(id)")
        }
        if let e = doc.entity(id), let v = e.props["ifcGuid"], IFCExporter.isValidGuid(v) { return v }
        return IFCExporter.guid("entity:\(id)")
    }

    /// Topics from the document's markups; cameras converted to metres at the markup's level elevation.
    public static func topics(_ doc: ArchiDocument) -> [BCFTopic] {
        let m = doc.units.mm / 1000
        return Markups.list(doc).map { mk in
            let elev = mk.level.flatMap { doc.level($0)?.elevation } ?? 0
            var vp: BCFViewpoint
            if let c = mk.camera {
                let d = (c.target - c.eye)
                let dir = d.length > 1e-12 ? d / d.length : Vec3(0, 1, 0)
                var up = Vec3(0, 0, 1) - dir * dir.z
                up = up.length > 1e-9 ? up / up.length : Vec3(0, 1, 0)
                vp = BCFViewpoint(guid: uuid(mk.id + ":vp"), position: c.eye * m, direction: dir, up: up, fieldOfView: c.fov,
                                  viewToWorldScale: mk.viewHeight * m, orthogonal: c.orthographic, selection: [])
            } else {
                vp = BCFViewpoint(guid: uuid(mk.id + ":vp"), position: Vec3(mk.viewCenter.x * m, mk.viewCenter.y * m, (elev + (doc.level(mk.level ?? 0)?.height ?? 3000) * 3) * m),
                                  direction: Vec3(0, 0, -1), up: Vec3(0, 1, 0), fieldOfView: 60, viewToWorldScale: mk.viewHeight * m, orthogonal: true, selection: [])
            }
            vp.selection = mk.elements.map { ifcGuid($0, doc: doc) }
            let comments = [BCFComment(guid: uuid(mk.id + ":c0"), author: mk.author, date: mk.date, text: mk.comment)] +
                mk.replies.enumerated().map { BCFComment(guid: uuid(mk.id + ":c\($0.offset + 1)"), author: $0.element.author, date: $0.element.date, text: $0.element.text) }
            return BCFTopic(guid: uuid(mk.id), title: mk.title.isEmpty ? String(mk.comment.prefix(60)) : mk.title, status: mk.isResolved ? "Closed" : "Open",
                            type: "Issue", author: mk.author, date: mk.date, description: mk.comment, comments: comments, viewpoint: vp)
        }
    }

    static func v3(_ tag: String, _ v: Vec3) -> String { "<\(tag)><X>\(n(v.x))</X><Y>\(n(v.y))</Y><Z>\(n(v.z))</Z></\(tag)>" }

    public static func markupXML(_ t: BCFTopic, projectFile: String) -> String {
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Markup xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">\n"
        x += "<Header><File IfcProject=\"\(IFCExporter.guid("project"))\" isExternal=\"true\"><Filename>\(esc(projectFile))</Filename><Date>\(esc(t.date))</Date></File></Header>\n"
        x += "<Topic Guid=\"\(t.guid)\" TopicType=\"\(esc(t.type))\" TopicStatus=\"\(esc(t.status))\"><Title>\(esc(t.title))</Title>"
        x += "<CreationDate>\(esc(t.date))</CreationDate><CreationAuthor>\(esc(t.author))</CreationAuthor><Description>\(esc(t.description))</Description></Topic>\n"
        for c in t.comments {
            x += "<Comment Guid=\"\(c.guid)\"><Date>\(esc(c.date))</Date><Author>\(esc(c.author))</Author><Comment>\(esc(c.text))</Comment>"
            if let vp = t.viewpoint { x += "<Viewpoint Guid=\"\(vp.guid)\"/>" }
            x += "</Comment>\n"
        }
        if let vp = t.viewpoint { x += "<Viewpoints Guid=\"\(vp.guid)\"><Viewpoint>viewpoint.bcfv</Viewpoint></Viewpoints>\n" }
        return x + "</Markup>\n"
    }

    public static func viewpointXML(_ vp: BCFViewpoint) -> String {
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<VisualizationInfo Guid=\"\(vp.guid)\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\">\n<Components>"
        if !vp.selection.isEmpty { x += "<Selection>" + vp.selection.map { "<Component IfcGuid=\"\(esc($0))\"/>" }.joined() + "</Selection>" }
        x += "<Visibility DefaultVisibility=\"true\"/></Components>\n"
        let tag = vp.orthogonal ? "OrthogonalCamera" : "PerspectiveCamera"
        x += "<\(tag)>" + v3("CameraViewPoint", vp.position) + v3("CameraDirection", vp.direction) + v3("CameraUpVector", vp.up)
        x += vp.orthogonal ? "<ViewToWorldScale>\(n(vp.viewToWorldScale))</ViewToWorldScale>" : "<FieldOfView>\(n(vp.fieldOfView))</FieldOfView>"
        return x + "</\(tag)>\n</VisualizationInfo>\n"
    }

    /// .bcfzip with bcf.version, project.bcfp and one folder per topic.
    public static func export(_ doc: ArchiDocument, projectFile: String = "model.ifc") -> Data {
        var entries: [ZipArchive.Entry] = []
        entries.append(.init(name: "bcf.version", data: Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Version VersionId=\"2.1\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><DetailedVersion>2.1</DetailedVersion></Version>\n".utf8)))
        entries.append(.init(name: "project.bcfp", data: Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ProjectExtension><Project ProjectId=\"\(uuid(IFCExporter.guid("project")))\"><Name>\(esc(doc.info.name))</Name></Project><ExtensionSchema></ExtensionSchema></ProjectExtension>\n".utf8)))
        for t in topics(doc) {
            entries.append(.init(name: "\(t.guid)/markup.bcf", data: Data(markupXML(t, projectFile: projectFile).utf8)))
            if let vp = t.viewpoint { entries.append(.init(name: "\(t.guid)/viewpoint.bcfv", data: Data(viewpointXML(vp).utf8))) }
        }
        return ZipArchive.write(entries, compress: true)
    }

    static func tree(_ data: Data) -> GBXMLValidator.Node? {
        let tb = GBXMLValidator.TreeBuilder()
        let p = XMLParser(data: data); p.delegate = tb
        guard p.parse() else { return nil }
        return tb.root
    }
    static func child(_ n: GBXMLValidator.Node?, _ name: String) -> GBXMLValidator.Node? { n?.children.first { $0.name == name } }
    static func text(_ n: GBXMLValidator.Node?, _ name: String) -> String { child(n, name)?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    static func vec(_ n: GBXMLValidator.Node?) -> Vec3? {
        guard let n, let x = Double(text(n, "X")), let y = Double(text(n, "Y")), let z = Double(text(n, "Z")) else { return nil }
        return Vec3(x, y, z)
    }

    /// Topics of a .bcfzip (BCF 2.0/2.1/3.0 markup layout).
    public static func read(_ data: Data) throws -> [BCFTopic] {
        let entries = try ZipArchive.read(data)
        var files: [String: Data] = [:]
        for e in entries { files[e.name] = e.data }
        guard files.keys.contains(where: { $0.hasSuffix("markup.bcf") }) else { throw BCFError.invalid("no markup.bcf topics") }
        var out: [BCFTopic] = []
        for name in files.keys.sorted() where name.hasSuffix("/markup.bcf") {
            let folder = String(name.dropLast("markup.bcf".count))
            guard let root = tree(files[name]!), let topic = child(root, "Topic") else { continue }
            var comments: [BCFComment] = []
            for c in root.children where c.name == "Comment" {
                comments.append(BCFComment(guid: c.attrs["Guid"] ?? "", author: text(c, "Author"), date: text(c, "Date"), text: text(c, "Comment")))
            }
            for c in (child(topic, "Comments")?.children ?? []) where c.name == "Comment" {     // BCF 3.0 nests comments in the topic
                comments.append(BCFComment(guid: c.attrs["Guid"] ?? "", author: text(c, "Author"), date: text(c, "Date"), text: text(c, "Comment")))
            }
            var vp: BCFViewpoint?
            let vpNode = root.children.first { $0.name == "Viewpoints" } ?? child(child(topic, "Viewpoints"), "ViewPoint")
            let vpFile = vpNode.map { text($0, "Viewpoint") }.flatMap { $0.isEmpty ? nil : $0 } ?? "viewpoint.bcfv"
            if let vd = files[folder + vpFile], let v = tree(vd) {
                let ortho = child(v, "OrthogonalCamera"), persp = child(v, "PerspectiveCamera")
                let cam = ortho ?? persp
                let sel = (child(child(v, "Components"), "Selection")?.children ?? []).compactMap { $0.attrs["IfcGuid"] }
                if let cam, let pos = vec(child(cam, "CameraViewPoint")), let dir = vec(child(cam, "CameraDirection")) {
                    vp = BCFViewpoint(guid: v.attrs["Guid"] ?? "", position: pos, direction: dir, up: vec(child(cam, "CameraUpVector")) ?? Vec3(0, 0, 1),
                                      fieldOfView: Double(text(cam, "FieldOfView")) ?? 60, viewToWorldScale: Double(text(cam, "ViewToWorldScale")) ?? 10,
                                      orthogonal: ortho != nil, selection: sel)
                } else if !sel.isEmpty {
                    vp = BCFViewpoint(guid: v.attrs["Guid"] ?? "", position: .zero, direction: Vec3(0, 0, -1), up: Vec3(0, 1, 0), fieldOfView: 60, viewToWorldScale: 10, orthogonal: true, selection: sel)
                }
            }
            let first = comments.first
            out.append(BCFTopic(guid: topic.attrs["Guid"] ?? String(folder.dropLast()), title: text(topic, "Title"), status: topic.attrs["TopicStatus"] ?? "Open",
                                type: topic.attrs["TopicType"] ?? "Issue", author: text(topic, "CreationAuthor"), date: text(topic, "CreationDate"),
                                description: text(topic, "Description").isEmpty ? (first?.text ?? "") : text(topic, "Description"),
                                comments: comments, viewpoint: vp))
        }
        return out
    }

    /// Adds (or updates, by topic GUID) markups for BCF topics. Returns the markup ids.
    @discardableResult
    public static func importTopics(_ topics: [BCFTopic], into doc: inout ArchiDocument) -> [String] {
        let m = doc.units.mm / 1000
        var byGuid: [String: EntityID] = [:]
        for el in doc.elements { byGuid[ifcGuid(el.id, doc: doc)] = el.id }
        for e in doc.entities where e.props["ifcGuid"] != nil { byGuid[e.props["ifcGuid"]!] = e.id }
        var ids: [String] = []
        for t in topics {
            let mid = t.guid.lowercased()
            Markups.remove(&doc, mid)
            var center = Vec2.zero, height = 10.0 / m, camera: Camera?
            var level: Int?
            if let vp = t.viewpoint {
                let topDown = vp.orthogonal && vp.direction.z < -0.999
                if topDown {
                    center = Vec2(vp.position.x, vp.position.y) / m
                    height = vp.viewToWorldScale / m
                } else {
                    let eye = vp.position / m
                    let dir = vp.direction.length > 1e-12 ? vp.direction / vp.direction.length : Vec3(0, 1, 0)
                    camera = Camera(eye: eye, target: eye + dir * (10 / m), fov: vp.fieldOfView, orthographic: vp.orthogonal)
                    center = Vec2(eye.x, eye.y) + Vec2(dir.x, dir.y) * (5 / m)
                    height = (vp.orthogonal ? vp.viewToWorldScale : 10) / m
                }
            }
            let sel = t.viewpoint?.selection.compactMap { byGuid[$0] } ?? []
            if let first = sel.first, let el = doc.element(first) { level = el.level }
            let half = Vec2(height * 0.8, height / 2) * 0.5
            let c0 = t.comments.first
            let mid2 = Markups.add(&doc, rect: (center - half, center + half), title: t.title, comment: t.description.isEmpty ? (c0?.text ?? t.title) : t.description,
                                   author: t.author.isEmpty ? c0?.author : t.author, date: t.date.isEmpty ? c0?.date : t.date, elements: sel, camera: camera, level: level,
                                   id: mid, status: t.status.lowercased() == "closed" || t.status.lowercased() == "resolved" ? "resolved" : "open")
            // The view stored with the markup is the BCF one (not the cloud's).
            _ = Markups.update(&doc, mid2) { p in p["view"] = "\(fmt(center.x, 4)),\(fmt(center.y, 4)),\(fmt(height, 4))"; p["bcfGuid"] = t.guid }
            let skip = (t.description.isEmpty || c0?.text == t.description) ? 1 : 0
            for c in t.comments.dropFirst(skip) { Markups.reply(&doc, mid2, text: c.text, author: c.author, date: c.date) }
            ids.append(mid2)
        }
        return ids
    }
}
