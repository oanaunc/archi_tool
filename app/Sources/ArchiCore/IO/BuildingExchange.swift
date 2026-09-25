// Oanarina Archi Tool — GPL-3.0-or-later
// Building data exchange for energy and facility management: gbXML 0.37 (spaces, envelope surfaces with openings,
// constructions with U-values — schema at gbxml.org) and COBie 2.4 spreadsheets (Contact, Facility, Floor, Space,
// Type, Component, Attribute sheets; BS 1192-4 column layout).
import Foundation

public enum GBXMLExporter {
    static func esc(_ s: String) -> String { XLSX.esc(s) }
    static func n(_ v: Double) -> String { fmt(v, 4) }

    /// gbXML document in SI units (metres). Walls become ExteriorWall/InteriorWall surfaces (with window/door openings),
    /// roofs Roof, lowest-level floor slabs SlabOnGrade, other floor slabs InteriorFloor; rooms become Spaces.
    public static func export(_ doc: ArchiDocument) -> String {
        let u = doc.units.mm / 1000
        func elev(_ l: Int) -> Double { (doc.level(l)?.elevation ?? 0) * u }
        let lowest = doc.levels.min { $0.elevation < $1.elevation }?.id ?? 0
        var constructions: [String: (name: String, u: Double)] = [:]
        var windowTypes: [String: (name: String, u: Double)] = [:]
        func consID(_ el: BIMElement, _ comp: String) -> String? {
            guard let cu = Thermal.uValue(el, doc: doc, component: comp) else { return nil }
            var name = el.material ?? comp
            if case .wall(let w) = el.geometry, let t = w.wallType { name = t }
            let key = "cons-" + MeshExport.safeName(comp + "-" + name) + "-" + fmt(cu.u, 3).replacingOccurrences(of: ".", with: "_")
            constructions[key] = (name, cu.u)
            return key
        }
        func loop(_ pts: [Vec3]) -> String {
            "<PolyLoop>" + pts.map { "<CartesianPoint><Coordinate>\(n($0.x))</Coordinate><Coordinate>\(n($0.y))</Coordinate><Coordinate>\(n($0.z))</Coordinate></CartesianPoint>" }.joined() + "</PolyLoop>"
        }
        // Rooms (spaces) and which one contains a plan point.
        let rooms = doc.elements.filter { if case .space = $0.geometry { return $0.props["areaScheme"] == nil }; return false }
        func room(at p: Vec2, level: Int) -> BIMElement? {
            rooms.first { r in if r.level == level, case .space(let s) = r.geometry { return GeometryOps.pointInPolygon(p, s.boundary) }; return false }
        }
        var surfaces: [String] = []
        for el in doc.elements {
            switch el.geometry {
            case .wall(let w):
                guard w.length > 1e-9, abs(w.bulge) < 1e-9 else { continue }
                let ext = Thermal.isExterior(el, doc: doc)
                let z0 = elev(el.level) + w.baseOffset * u, z1 = z0 + w.height * u
                let a = w.centerStart * u, b = w.centerEnd * u
                let mid = (w.centerStart + w.centerEnd) / 2, nrm = w.direction.perp, off = w.thickness / 2 + 150 / doc.units.mm
                let left = room(at: mid + nrm * off, level: el.level), right = room(at: mid - nrm * off, level: el.level)
                // Outward = toward the side without a room (exterior walls); points counter-clockwise seen from outside.
                let outwardLeft = ext && left == nil && right != nil
                var pts = [Vec3(a.x, a.y, z0), Vec3(b.x, b.y, z0), Vec3(b.x, b.y, z1), Vec3(a.x, a.y, z1)]
                if outwardLeft { pts.reverse() }
                let dirOut = outwardLeft ? nrm : nrm * -1
                let az = (90 - deg(atan2(dirOut.y, dirOut.x)) + doc.info.northAngle).truncatingRemainder(dividingBy: 360)
                var s = "<Surface id=\"su-\(el.id)\" surfaceType=\"\(ext ? "ExteriorWall" : "InteriorWall")\""
                if let c = consID(el, "wall") { s += " constructionIdRef=\"\(c)\"" }
                s += ">"
                for r in [left, right].compactMap({ $0 }) { s += "<AdjacentSpaceId spaceIdRef=\"sp-\(r.id)\"/>" }
                s += "<RectangularGeometry><Azimuth>\(n(az < 0 ? az + 360 : az))</Azimuth><CartesianPoint><Coordinate>\(n(a.x))</Coordinate><Coordinate>\(n(a.y))</Coordinate><Coordinate>\(n(z0))</Coordinate></CartesianPoint><Tilt>90</Tilt><Width>\(n(w.length * u))</Width><Height>\(n(w.height * u))</Height></RectangularGeometry>"
                s += "<PlanarGeometry>\(loop(pts))</PlanarGeometry>"
                for oe in doc.elements {
                    guard case .opening(let o) = oe.geometry, o.hostWall == el.id, o.kind != .opening else { continue }
                    let d = w.direction * u
                    let c0 = a + d * (o.offset - o.width / 2), c1 = a + d * (o.offset + o.width / 2)
                    let oz0 = z0 + o.sill * u, oz1 = oz0 + o.height * u
                    var op = [Vec3(c0.x, c0.y, oz0), Vec3(c1.x, c1.y, oz0), Vec3(c1.x, c1.y, oz1), Vec3(c0.x, c0.y, oz1)]
                    if outwardLeft { op.reverse() }
                    let cu = Thermal.uValue(oe, doc: doc)?.u ?? 1.3
                    let typeKey = (o.kind == .door ? "door-" : "win-") + fmt(cu, 3).replacingOccurrences(of: ".", with: "_")
                    windowTypes[typeKey] = (o.typeName ?? (o.kind == .door ? "Door" : "Window"), cu)
                    let kind = o.kind == .door ? (ext ? "NonSlidingDoor" : "NonSlidingDoor") : (o.windowStyle == .fixed ? "FixedWindow" : "OperableWindow")
                    s += "<Opening id=\"op-\(oe.id)\" openingType=\"\(kind)\" windowTypeIdRef=\"\(typeKey)\"><RectangularGeometry><CartesianPoint><Coordinate>\(n(o.offset * u - o.width * u / 2))</Coordinate><Coordinate>\(n(o.sill * u))</Coordinate></CartesianPoint><Width>\(n(o.width * u))</Width><Height>\(n(o.height * u))</Height></RectangularGeometry><PlanarGeometry>\(loop(op))</PlanarGeometry></Opening>"
                }
                surfaces.append(s + "<CADObjectId>\(el.id)</CADObjectId></Surface>")
            case .slab(let sl):
                let kind = el.props["kind"] ?? ""
                guard kind.isEmpty || kind == "floor" || kind == "landing", sl.boundary.count >= 3 else { continue }
                let onGrade = el.level == lowest
                var b = sl.boundary
                if GeometryOps.signedArea(b) > 0 { b.reverse() } // floor surfaces face down (outward)
                let pts = b.map { Vec3($0.x * u, $0.y * u, elev(el.level) + sl.topHeight(at: $0) * u) }
                var s = "<Surface id=\"su-\(el.id)\" surfaceType=\"\(onGrade ? "SlabOnGrade" : "InteriorFloor")\""
                if let c = consID(el, "floor") { s += " constructionIdRef=\"\(c)\"" }
                s += ">"
                let cpt = GeometryOps.centroid(sl.boundary)
                if let r = room(at: cpt, level: el.level) { s += "<AdjacentSpaceId spaceIdRef=\"sp-\(r.id)\"/>" }
                surfaces.append(s + "<PlanarGeometry>\(loop(pts))</PlanarGeometry><CADObjectId>\(el.id)</CADObjectId></Surface>")
            case .roof(let rf):
                guard rf.boundary.count >= 3 else { continue }
                var b = rf.boundary
                if GeometryOps.signedArea(b) < 0 { b.reverse() } // faces up
                let z = elev(el.level) + (rf.baseOffset + rf.thickness) * u
                var s = "<Surface id=\"su-\(el.id)\" surfaceType=\"Roof\""
                if let c = consID(el, "roof") { s += " constructionIdRef=\"\(c)\"" }
                let c0 = b[0] * u
                s += "><RectangularGeometry><CartesianPoint><Coordinate>\(n(c0.x))</Coordinate><Coordinate>\(n(c0.y))</Coordinate><Coordinate>\(n(z))</Coordinate></CartesianPoint><Tilt>\(n(rf.kind == .flat ? 0 : rf.pitch))</Tilt></RectangularGeometry>"
                surfaces.append(s + "<PlanarGeometry>\(loop(b.map { Vec3($0.x * u, $0.y * u, z) }))</PlanarGeometry><CADObjectId>\(el.id)</CADObjectId></Surface>")
            default: continue
            }
        }
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gbXML xmlns=\"http://www.gbxml.org/schema\" version=\"0.37\" temperatureUnit=\"C\" lengthUnit=\"Meters\" areaUnit=\"SquareMeters\" volumeUnit=\"CubicMeters\" useSIUnitsForResults=\"true\">\n"
        x += "<Campus id=\"campus\"><Location><Name>\(esc(doc.info.address.isEmpty ? doc.info.name : doc.info.address))</Name><Latitude>\(n(doc.info.latitude))</Latitude><Longitude>\(n(doc.info.longitude))</Longitude></Location>\n"
        let floorArea = rooms.reduce(0) { a, r in if case .space(let s) = r.geometry { return a + abs(GeometryOps.signedArea(s.boundary)) * u * u }; return a }
        x += "<Building id=\"building\" buildingType=\"Unknown\"><Name>\(esc(doc.info.name))</Name><Area>\(n(floorArea))</Area>\n"
        for lv in doc.levels.sorted(by: { $0.elevation < $1.elevation }) {
            x += "<BuildingStorey id=\"storey-\(lv.id)\"><Name>\(esc(lv.name))</Name><Level>\(n(lv.elevation * u))</Level></BuildingStorey>\n"
        }
        for r in rooms {
            guard case .space(let s) = r.geometry else { continue }
            let a = abs(GeometryOps.signedArea(s.boundary)) * u * u
            var b = s.boundary
            if GeometryOps.signedArea(b) < 0 { b.reverse() }
            let z = elev(r.level)
            x += "<Space id=\"sp-\(r.id)\" buildingStoreyIdRef=\"storey-\(r.level)\"><Name>\(esc((s.number.isEmpty ? "" : s.number + " ") + s.name))</Name><Area>\(n(a))</Area><Volume>\(n(a * s.height * u))</Volume>"
            x += "<PlanarGeometry>\(loop(b.map { Vec3($0.x * u, $0.y * u, z) }))</PlanarGeometry><CADObjectId>\(r.id)</CADObjectId></Space>\n"
        }
        x += "</Building>\n" + surfaces.joined(separator: "\n") + "\n</Campus>\n"
        for (k, c) in constructions.sorted(by: { $0.key < $1.key }) {
            x += "<Construction id=\"\(k)\"><U-value unit=\"WPerSquareMeterK\">\(n(c.u))</U-value><Name>\(esc(c.name))</Name></Construction>\n"
        }
        for (k, c) in windowTypes.sorted(by: { $0.key < $1.key }) {
            x += "<WindowType id=\"\(k)\"><Name>\(esc(c.name))</Name><U-value unit=\"WPerSquareMeterK\">\(n(c.u))</U-value></WindowType>\n"
        }
        let iso = ISO8601DateFormatter()
        x += "<DocumentHistory><ProgramInfo id=\"archi\"><CompanyName>Oanarina</CompanyName><ProductName>Oanarina Archi Tool</ProductName><Version>1.0</Version></ProgramInfo>"
        x += "<CreatedBy programId=\"archi\" date=\"\(iso.string(from: Date()))\" personId=\"author\"/><PersonInfo id=\"author\"><FirstName>\(esc(doc.info.author.isEmpty ? "Architect" : doc.info.author))</FirstName></PersonInfo></DocumentHistory>\n"
        return x + "</gbXML>\n"
    }
}

public enum COBieExporter {
    /// COBie 2.4 workbook (XLSX). Components are doors, windows and placed components; their types become Type rows.
    public static func sheets(_ doc: ArchiDocument) -> [XLSX.Sheet] {
        let u = doc.units.mm / 1000
        let who = doc.info.author.isEmpty ? "architect@example.com" : (doc.info.author.contains("@") ? doc.info.author : doc.info.author.replacingOccurrences(of: " ", with: ".").lowercased() + "@example.com")
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
        let now = iso.string(from: Date())
        let sys = "Oanarina Archi Tool"
        func guid(_ el: BIMElement) -> String { el.props["ifcGuid"].flatMap { IFCExporter.isValidGuid($0) ? $0 : nil } ?? IFCExporter.guid("element:\(el.id)") }
        func levelName(_ id: Int) -> String { doc.level(id)?.name ?? "Level \(id)" }

        var contact = [["Email", "CreatedBy", "CreatedOn", "Category", "Company", "Phone", "ExternalSystem", "ExternalObject", "ExternalIdentifier", "Department",
                        "OrganizationCode", "GivenName", "FamilyName", "Street", "PostalBox", "Town", "StateRegion", "PostalCode", "Country"]]
        let parts = doc.info.author.split(separator: " ").map(String.init)
        contact.append([who, who, now, "Designer", doc.info.client.isEmpty ? "n/a" : doc.info.client, "n/a", sys, "IfcPersonAndOrganization", "n/a", "n/a", "n/a",
                        parts.first ?? "n/a", parts.count > 1 ? parts.dropFirst().joined(separator: " ") : "n/a", doc.info.address.isEmpty ? "n/a" : doc.info.address, "n/a", "n/a", "n/a", "n/a", "n/a"])

        let facility = [["Name", "CreatedBy", "CreatedOn", "Category", "ProjectName", "SiteName", "LinearUnits", "AreaUnits", "VolumeUnits", "CurrencyUnit", "AreaMeasurement",
                         "ExternalSystem", "ExternalProjectObject", "ExternalProjectIdentifier", "ExternalSiteObject", "ExternalSiteIdentifier", "ExternalFacilityObject",
                         "ExternalFacilityIdentifier", "Description", "ProjectDescription", "SiteDescription", "Phase"],
                        [doc.info.name, who, now, "n/a", doc.info.number.isEmpty ? doc.info.name : doc.info.number, "Site", "meters", "square meters", "cubic meters",
                         doc.variable("COSTCURRENCY") ?? "EUR", "Net", sys, "IfcProject", IFCExporter.guid("project"), "IfcSite", IFCExporter.guid("site"), "IfcBuilding",
                         IFCExporter.guid("building"), doc.info.name, doc.info.name, doc.info.address.isEmpty ? "n/a" : doc.info.address, doc.phases.last ?? "n/a"]]

        var floor = [["Name", "CreatedBy", "CreatedOn", "Category", "ExtSystem", "ExtObject", "ExtIdentifier", "Description", "Elevation", "Height"]]
        for lv in doc.levels.sorted(by: { $0.elevation < $1.elevation }) {
            floor.append([lv.name, who, now, "Floor", sys, "IfcBuildingStorey", IFCExporter.guid("storey:\(lv.id)"), lv.name, fmt(lv.elevation * u, 3), fmt(lv.height * u, 3)])
        }

        var space = [["Name", "CreatedBy", "CreatedOn", "Category", "FloorName", "Description", "ExtSystem", "ExtObject", "ExtIdentifier", "RoomTag", "UsableHeight", "GrossArea", "NetArea"]]
        let roomRows = RoomSchedule.compute(doc)
        var spaceName: [EntityID: String] = [:]
        for el in doc.elements {
            guard case .space(let s) = el.geometry, el.props["areaScheme"] == nil else { continue }
            let name = s.number.isEmpty ? "\(el.id)" : s.number
            spaceName[el.id] = name
            let rr = roomRows.first { $0.id == el.id }
            space.append([name, who, now, el.props["category"] ?? "n/a", levelName(el.level), s.name, sys, "IfcSpace", guid(el), s.name,
                          fmt(s.height * u, 3), fmt(rr?.grossArea ?? 0, 3), fmt(rr?.netArea ?? 0, 3)])
        }
        func spaceOf(_ p: Vec2, level: Int) -> String {
            for el in doc.elements where el.level == level { if case .space(let s) = el.geometry, el.props["areaScheme"] == nil, GeometryOps.pointInPolygon(p, s.boundary) { return spaceName[el.id] ?? "n/a" } }
            return "n/a"
        }

        var types: [String: [String]] = [:]
        // Component names are unique keys in COBie: repeated marks get the element id appended.
        var usedNames = Set<String>(), componentName: [EntityID: String] = [:]
        func unique(_ n: String, _ id: EntityID) -> String {
            var name = n.isEmpty ? "Component-\(id)" : n
            if usedNames.contains(name) { name += "-\(id)" }
            usedNames.insert(name); componentName[id] = name
            return name
        }
        var component = [["Name", "CreatedBy", "CreatedOn", "TypeName", "Space", "Description", "ExtSystem", "ExtObject", "ExtIdentifier", "SerialNumber", "InstallationDate",
                          "WarrantyStartDate", "TagNumber", "BarCode", "AssetIdentifier"]]
        var attribute = [["Name", "CreatedBy", "CreatedOn", "Category", "SheetName", "RowName", "Value", "Unit", "ExtSystem", "ExtObject", "ExtIdentifier", "Description", "AllowedValues"]]
        for el in doc.elements {
            var typeName = "", ifc = "", cat = "", pos: Vec2? = nil, dims: (Double, Double, Double) = (0, 0, 0)
            switch el.geometry {
            case .opening(let o) where o.kind != .opening:
                let isDoor = o.kind == .door
                typeName = o.typeName ?? "\(isDoor ? "Door" : "Window") \(fmt(o.width * doc.units.mm, 0))x\(fmt(o.height * doc.units.mm, 0))"
                ifc = isDoor ? "IfcDoor" : "IfcWindow"; cat = isDoor ? "Doors" : "Windows"
                if let h = doc.element(o.hostWall), case .wall(let w) = h.geometry {
                    let c = w.centerStart + w.direction * o.offset, off = w.thickness / 2 + 100 / doc.units.mm
                    let a = spaceOf(c + w.direction.perp * off, level: h.level), b = spaceOf(c - w.direction.perp * off, level: h.level)
                    pos = nil
                    component.append([unique(el.props["mark"] ?? o.mark ?? "\(ifc.dropFirst(3))-\(el.id)", el.id), who, now, typeName, [a, b].filter { $0 != "n/a" }.joined(separator: ",").isEmpty ? "n/a" : [a, b].filter { $0 != "n/a" }.joined(separator: ","),
                                      el.name.isEmpty ? typeName : el.name, sys, ifc, guid(el), "n/a", "n/a", "n/a", o.mark ?? "n/a", "n/a", "n/a"])
                }
                dims = (o.width * u, 0, o.height * u)
            case .component(let c):
                typeName = c.family ?? c.block ?? c.category
                ifc = "IfcFurnishingElement"; cat = c.category
                pos = c.position
                dims = (c.size.x * u, c.size.y * u, c.size.z * u)
            default: continue
            }
            if let p = pos {
                component.append([unique(el.name.isEmpty ? "\(typeName)-\(el.id)" : el.name, el.id), who, now, typeName, spaceOf(p, level: el.level), el.name.isEmpty ? typeName : el.name,
                                  sys, ifc, guid(el), "n/a", "n/a", "n/a", "n/a", "n/a", "n/a"])
            }
            if types[typeName] == nil {
                types[typeName] = [typeName, who, now, cat, typeName, "Fixed", el.props["manufacturer"] ?? "n/a", el.props["model"] ?? "n/a", "n/a", "0", "n/a", "0", "Year",
                                   sys, ifc + "Type", "n/a", "0", "0", "Year", fmt(dims.0, 3), fmt(dims.1, 3), fmt(dims.2, 3)]
            }
            guard let rowName = componentName[el.id] else { continue }
            for (k, v) in el.props.sorted(by: { $0.key < $1.key }) where !["ifcGuid", "mark", "manufacturer", "model"].contains(k) && !v.isEmpty {
                attribute.append([k, who, now, "Submitted", "Component", rowName, v, "n/a", sys, "IfcPropertySingleValue", "n/a", k, "n/a"])
            }
        }
        var type = [["Name", "CreatedBy", "CreatedOn", "Category", "Description", "AssetType", "Manufacturer", "ModelNumber", "WarrantyGuarantorParts", "WarrantyDurationParts",
                     "WarrantyGuarantorLabor", "WarrantyDurationLabor", "WarrantyDurationUnit", "ExtSystem", "ExtObject", "ExtIdentifier", "ReplacementCost", "ExpectedLife",
                     "DurationUnit", "NominalLength", "NominalWidth", "NominalHeight"]]
        type += types.keys.sorted().map { types[$0]! }
        let instruction = [["Instruction"], ["COBie 2.4 (BS 1192-4) export from Oanarina Archi Tool. Units: metres, square metres. \"n/a\" marks values not available in the model."]]
        return [XLSX.Sheet(name: "Instruction", rows: instruction), XLSX.Sheet(name: "Contact", rows: contact), XLSX.Sheet(name: "Facility", rows: facility),
                XLSX.Sheet(name: "Floor", rows: floor), XLSX.Sheet(name: "Space", rows: space), XLSX.Sheet(name: "Type", rows: type),
                XLSX.Sheet(name: "Component", rows: component), XLSX.Sheet(name: "Attribute", rows: attribute)]
    }

    public static func export(_ doc: ArchiDocument) -> Data { XLSX.write(sheets(doc)) }
}
