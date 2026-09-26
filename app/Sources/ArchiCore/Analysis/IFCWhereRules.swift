// Oanarina Archi Tool — GPL-3.0-or-later
// EXPRESS WHERE rules of the IFC2X3 / IFC4 / IFC4X3 schemas for the resource and product entities that exporters most
// often get wrong (ANL-041, IO-021…IO-030): geometric dimensionality, placements, profiles, extrusions, tessellations,
// representation item/type agreement, units, spatial relationships, property sets, quantities and material layers.
// Rule names follow the schema documentation (e.g. IfcAxis2Placement3D.AxisToRefDirPosition).
import Foundation

extension IFCValidator {
    /// Issues for violated WHERE rules, one issue per rule listing every offending instance.
    static func whereRuleIssues(_ f: STEPFile, _ t: IFCSchemaTable) -> [IFCValidationIssue] {
        let is2x3 = t.name.uppercased().hasPrefix("IFC2X3")
        var hits: [String: (IssueSeverity, String, [Int])] = [:]
        var order: [String] = []
        func fail(_ rule: String, _ msg: String, _ id: Int, _ sev: IssueSeverity = .error) {
            if hits[rule] == nil { hits[rule] = (sev, msg, []); order.append(rule) }
            hits[rule]!.2.append(id)
        }
        var nameCache: [String: [String: Int]] = [:]
        func a(_ e: StepEntity, _ name: String) -> StepValue {
            if nameCache[e.type] == nil {
                var m: [String: Int] = [:]
                for (i, n) in (t.attributeNames(e.type) ?? []).enumerated() { m[n] = i }
                nameCache[e.type] = m
            }
            guard e.parts.isEmpty, let i = nameCache[e.type]?[name] else { return .null }
            return e[i]
        }
        func isa(_ id: Int?, _ type: String) -> Bool { guard let e = f[id] else { return false }; return t.isSubtype(e.type, of: type) }
        func nums(_ v: StepValue) -> [Double] { (v.list ?? []).compactMap(\.double) }
        func vec(_ id: Int?) -> [Double]? {
            guard let e = f[id] else { return nil }
            switch e.type {
            case "IFCDIRECTION": return nums(a(e, "DirectionRatios"))
            case "IFCCARTESIANPOINT": return nums(a(e, "Coordinates"))
            default: return nil
            }
        }
        var dimCache: [Int: Int?] = [:]
        /// Coordinate space dimensionality of a geometric representation item (nil = unknown / not checked).
        func dim(_ id: Int?, depth: Int = 0) -> Int? {
            guard let id, let e = f[id], depth < 8 else { return nil }
            if let c = dimCache[id] { return c }
            var r: Int?
            switch e.type {
            case "IFCCARTESIANPOINT": r = a(e, "Coordinates").list?.count
            case "IFCDIRECTION": r = a(e, "DirectionRatios").list?.count
            case "IFCAXIS2PLACEMENT3D", "IFCCARTESIANPOINTLIST3D", "IFCTRIANGULATEDFACESET", "IFCPOLYGONALFACESET", "IFCFACETEDBREP",
                 "IFCEXTRUDEDAREASOLID", "IFCREVOLVEDAREASOLID", "IFCBOUNDINGBOX", "IFCBLOCK", "IFCSPHERE", "IFCRIGHTCIRCULARCYLINDER":
                r = 3
            case "IFCAXIS2PLACEMENT2D", "IFCCARTESIANPOINTLIST2D": r = 2
            case "IFCPOLYLINE": r = a(e, "Points").refs.first.flatMap { dim($0, depth: depth + 1) }
            case "IFCPOLYLOOP": r = a(e, "Polygon").refs.first.flatMap { dim($0, depth: depth + 1) }
            case "IFCINDEXEDPOLYCURVE": r = dim(a(e, "Points").ref, depth: depth + 1)
            case "IFCTRIMMEDCURVE": r = dim(a(e, "BasisCurve").ref, depth: depth + 1)
            case "IFCCIRCLE", "IFCELLIPSE":
                r = dim(a(e, "Position").ref ?? (a(e, "Position").list?.first?.ref), depth: depth + 1)
            case "IFCLINE": r = dim(a(e, "Pnt").ref, depth: depth + 1)
            case "IFCCOMPOSITECURVE":
                r = a(e, "Segments").refs.first.flatMap { f[$0] }.flatMap { dim(a($0, "ParentCurve").ref, depth: depth + 1) }
            default: r = nil
            }
            dimCache[id] = r
            return r
        }

        // Geometry resource.
        for e in f.all("IFCCARTESIANPOINT") {
            let n = a(e, "Coordinates").list?.count ?? 0
            if n < (is2x3 ? 2 : 1) || n > 3 { fail("IfcCartesianPoint.CorrectDim", "IfcCartesianPoint must have \(is2x3 ? 2 : 1) to 3 coordinates", e.id) }
        }
        for e in f.all("IFCDIRECTION") {
            let v = nums(a(e, "DirectionRatios"))
            if v.count < 2 || v.count > 3 { fail("IfcDirection.DirectionRatios", "IfcDirection must have 2 or 3 direction ratios", e.id) }
            else if !is2x3, v.reduce(0, { $0 + $1 * $1 }) <= 0 { fail("IfcDirection.MagnitudeGreaterZero", "IfcDirection has zero magnitude", e.id) }
        }
        for e in f.all("IFCAXIS2PLACEMENT3D") {
            let loc = a(e, "Location").ref, axis = a(e, "Axis").ref, ref = a(e, "RefDirection").ref
            if let d = dim(loc), d != 3 { fail("IfcAxis2Placement3D.LocationIs3D", "IfcAxis2Placement3D location is not 3D", e.id) }
            if let d = dim(axis), d != 3 { fail("IfcAxis2Placement3D.AxisIs3D", "IfcAxis2Placement3D axis is not 3D", e.id) }
            if let d = dim(ref), d != 3 { fail("IfcAxis2Placement3D.RefDirIs3D", "IfcAxis2Placement3D reference direction is not 3D", e.id) }
            if (axis == nil) != (ref == nil) { fail("IfcAxis2Placement3D.AxisAndRefDirProvision", "IfcAxis2Placement3D gives only one of Axis / RefDirection", e.id) }
            if let z = vec(axis), let x = vec(ref), z.count == 3, x.count == 3 {
                let c = [z[1] * x[2] - z[2] * x[1], z[2] * x[0] - z[0] * x[2], z[0] * x[1] - z[1] * x[0]]
                let lz = z.reduce(0) { $0 + $1 * $1 }.squareRoot(), lx = x.reduce(0) { $0 + $1 * $1 }.squareRoot()
                if lz > 0, lx > 0, c.reduce(0, { $0 + $1 * $1 }).squareRoot() / (lz * lx) < 1e-9 {
                    fail("IfcAxis2Placement3D.AxisToRefDirPosition", "IfcAxis2Placement3D axis and reference direction are parallel", e.id)
                }
            }
        }
        for e in f.all("IFCAXIS2PLACEMENT2D") {
            if let d = dim(a(e, "Location").ref), d != 2 { fail("IfcAxis2Placement2D.LocationIs2D", "IfcAxis2Placement2D location is not 2D", e.id) }
            if let d = dim(a(e, "RefDirection").ref), d != 2 { fail("IfcAxis2Placement2D.RefDirIs2D", "IfcAxis2Placement2D reference direction is not 2D", e.id) }
        }
        for e in f.all("IFCPOLYLINE") {
            let pts = a(e, "Points").refs
            if pts.count < 2 { fail("IfcPolyline.Points", "IfcPolyline needs at least 2 points", e.id) }
            if Set(pts.compactMap { dim($0) }).count > 1 { fail("IfcPolyline.SameDim", "IfcPolyline mixes 2D and 3D points", e.id) }
        }
        for e in f.all("IFCPOLYLOOP") {
            let pts = a(e, "Polygon").refs
            if pts.count < 3 { fail("IfcPolyLoop.Polygon", "IfcPolyLoop needs at least 3 points", e.id) }
            if Set(pts.compactMap { dim($0) }).count > 1 { fail("IfcPolyLoop.AllPointsSameDim", "IfcPolyLoop mixes 2D and 3D points", e.id) }
        }
        for e in f.all("IFCCARTESIANPOINTLIST3D") where (a(e, "CoordList").list ?? []).contains(where: { ($0.list?.count ?? 0) != 3 }) {
            fail("IfcCartesianPointList3D.CoordList", "IfcCartesianPointList3D has points without exactly 3 coordinates", e.id)
        }
        for e in f.all("IFCTRIANGULATEDFACESET") {
            var n = f[a(e, "Coordinates").ref].map { a($0, "CoordList").list?.count ?? 0 } ?? 0
            if let pn = a(e, "PnIndex").list, !pn.isEmpty { n = pn.count }
            let tri = a(e, "CoordIndex").list ?? []
            if tri.isEmpty { fail("IfcTriangulatedFaceSet.CoordIndex", "IfcTriangulatedFaceSet has no triangles", e.id); continue }
            let bad = tri.contains { tr in
                let ix = nums(tr).map { Int($0) }
                return ix.count != 3 || ix.contains { $0 < 1 || $0 > n }
            }
            if bad { fail("IfcTriangulatedFaceSet.CoordIndex", "IfcTriangulatedFaceSet triangle indices are not 3 indices within the point list", e.id) }
            if let norms = a(e, "Normals").list, !norms.isEmpty, norms.contains(where: { ($0.list?.count ?? 0) != 3 }) {
                fail("IfcTriangulatedFaceSet.Normals", "IfcTriangulatedFaceSet normals must have 3 components", e.id)
            }
        }

        // Profiles and swept solids.
        for e in f.all("IFCRECTANGLEPROFILEDEF") {
            if (a(e, "XDim").double ?? 1) <= 0 || (a(e, "YDim").double ?? 1) <= 0 { fail("IfcRectangleProfileDef.PositiveDims", "IfcRectangleProfileDef XDim / YDim must be positive", e.id) }
        }
        for e in f.all("IFCCIRCLEPROFILEDEF") where (a(e, "Radius").double ?? 1) <= 0 {
            fail("IfcCircleProfileDef.PositiveRadius", "IfcCircleProfileDef radius must be positive", e.id)
        }
        for e in f.entities.values where e.type == "IFCARBITRARYCLOSEDPROFILEDEF" || e.type == "IFCARBITRARYPROFILEDEFWITHVOIDS" {
            let outer = a(e, "OuterCurve").ref
            if let d = dim(outer), d != 2 { fail("IfcArbitraryClosedProfileDef.WR1", "Profile outer curve must be 2D", e.id) }
            if let o = f[outer], o.type == "IFCLINE" || o.type == "IFCOFFSETCURVE2D" { fail("IfcArbitraryClosedProfileDef.WR2", "Profile outer curve must not be an IfcLine / IfcOffsetCurve2D", e.id) }
            if let o = f[outer], o.type == "IFCPOLYLINE" {
                let pts = a(o, "Points").refs
                if pts.count >= 2, let p0 = vec(pts.first), let p1 = vec(pts.last), p0 != p1, pts.first != pts.last {
                    fail("IfcArbitraryClosedProfileDef.ClosedCurve", "Profile outer polyline is not closed (first point ≠ last point)", e.id, .warning)
                }
            }
            for inner in a(e, "InnerCurves").refs { if let d = dim(inner), d != 2 { fail("IfcArbitraryProfileDefWithVoids.WR2", "Profile inner curves must be 2D", e.id) } }
        }
        for e in f.all("IFCEXTRUDEDAREASOLID") {
            if (a(e, "Depth").double ?? 1) <= 0 { fail("IfcExtrudedAreaSolid.PositiveDepth", "IfcExtrudedAreaSolid depth must be positive", e.id) }
            if let d = vec(a(e, "ExtrudedDirection").ref) {
                if d.count != 3 { fail("IfcExtrudedAreaSolid.DirectionIs3D", "IfcExtrudedAreaSolid direction is not 3D", e.id) }
                else if abs(d[2]) < 1e-12, d.contains(where: { $0 != 0 }) { fail("IfcExtrudedAreaSolid.ValidExtrusionDirection", "IfcExtrudedAreaSolid direction lies in the profile plane", e.id) }
            }
        }
        for e in f.all("IFCREVOLVEDAREASOLID") where (a(e, "Angle").double ?? 1) <= 0 {
            fail("IfcRevolvedAreaSolid.PositiveAngle", "IfcRevolvedAreaSolid angle must be positive", e.id)
        }

        // Placements: 3D placements, no cycles.
        for e in f.all("IFCLOCALPLACEMENT") {
            // IfcCorrectLocalPlacement: a 3D relative placement needs a 3D placement it is relative to (2D ones are fine).
            let rel = a(e, "RelativePlacement").ref
            if let to = f[a(e, "PlacementRelTo").ref], to.type == "IFCLOCALPLACEMENT", f[rel]?.type == "IFCAXIS2PLACEMENT3D",
               let d = dim(a(to, "RelativePlacement").ref), d != 3 {
                fail("IfcLocalPlacement.CorrectLocalPlacement", "IfcLocalPlacement places a 3D placement relative to a 2D one", e.id)
            }
            var seen: Set<Int> = [e.id], cur = a(e, "PlacementRelTo").ref, steps = 0
            while let c = cur, steps < 10_000 {
                if !seen.insert(c).inserted { fail("IfcLocalPlacement.Acyclic", "IfcLocalPlacement chain is cyclic", e.id); break }
                cur = f[c].map { a($0, "PlacementRelTo").ref } ?? nil; steps += 1
            }
        }

        // Representations: context and item types that agree with RepresentationType.
        let typeItems: [String: [String]] = [
            "SWEPTSOLID": ["IFCSWEPTAREASOLID", "IFCSWEPTDISKSOLID"], "BREP": ["IFCFACETEDBREP", "IFCMANIFOLDSOLIDBREP"],
            "TESSELLATION": ["IFCTESSELLATEDITEM"], "BOUNDINGBOX": ["IFCBOUNDINGBOX"], "MAPPEDREPRESENTATION": ["IFCMAPPEDITEM"],
            "CSG": ["IFCBOOLEANRESULT", "IFCCSGPRIMITIVE3D", "IFCCSGSOLID"], "CLIPPING": ["IFCBOOLEANCLIPPINGRESULT", "IFCBOOLEANRESULT"],
            "SURFACEMODEL": ["IFCTESSELLATEDITEM", "IFCSHELLBASEDSURFACEMODEL", "IFCFACEBASEDSURFACEMODEL"],
            "CURVE2D": ["IFCCURVE"], "POINT": ["IFCPOINT"], "ADVANCEDBREP": ["IFCMANIFOLDSOLIDBREP"],
        ]
        for e in f.all("IFCSHAPEREPRESENTATION") {
            if let ctx = a(e, "ContextOfItems").ref, !isa(ctx, "IFCGEOMETRICREPRESENTATIONCONTEXT") {
                fail("IfcShapeRepresentation.CorrectContext", "IfcShapeRepresentation context is not a geometric representation context", e.id)
            }
            let items = a(e, "Items").refs
            if items.isEmpty { fail("IfcRepresentation.Items", "IfcShapeRepresentation has no items", e.id) }
            if items.contains(where: { isa($0, "IFCTOPOLOGICALREPRESENTATIONITEM") && !isa($0, "IFCVERTEXPOINT") && !isa($0, "IFCEDGECURVE") && !isa($0, "IFCFACESURFACE") }) {
                fail("IfcShapeRepresentation.NoTopologicalItem", "IfcShapeRepresentation contains topological items", e.id)
            }
            guard let rt = a(e, "RepresentationType").string?.uppercased(), let allowed = typeItems[rt] else { continue }
            let wrong = items.contains { id in !allowed.contains { isa(id, $0) } && !(rt == "BREP" && is2x3 && isa(id, "IFCFACETEDBREP")) }
            if wrong { fail("IfcShapeRepresentation.CorrectItemsForType", "IfcShapeRepresentation items do not match RepresentationType", e.id) }
            if rt == "CURVE2D", items.contains(where: { (dim($0) ?? 2) != 2 }) {
                fail("IfcShapeRepresentation.CorrectItemsForType", "IfcShapeRepresentation items do not match RepresentationType", e.id)
            }
            if rt == "BOUNDINGBOX", items.count != 1 { fail("IfcShapeRepresentation.CorrectItemsForType", "IfcShapeRepresentation items do not match RepresentationType", e.id) }
        }
        for e in f.all("IFCGEOMETRICREPRESENTATIONCONTEXT") {
            if let d = a(e, "CoordinateSpaceDimension").double, d != 2 && d != 3 {
                fail("IfcGeometricRepresentationContext.Dimension", "Coordinate space dimension must be 2 or 3", e.id)
            }
            if let n = vec(a(e, "TrueNorth").ref), n.count != 2 && !(n.count == 3 && !is2x3) {
                fail("IfcGeometricRepresentationContext.North2D", "TrueNorth must be a 2D direction", e.id)
            }
        }
        for e in f.all("IFCGEOMETRICREPRESENTATIONSUBCONTEXT") where f[a(e, "ParentContext").ref]?.type == "IFCGEOMETRICREPRESENTATIONSUBCONTEXT" {
            fail("IfcGeometricRepresentationSubContext.ParentNoSub", "A subcontext's parent must not be a subcontext", e.id)
        }

        // Units.
        let siNames: [String: Set<String>] = [
            "LENGTHUNIT": ["METRE"], "AREAUNIT": ["SQUARE_METRE"], "VOLUMEUNIT": ["CUBIC_METRE"], "PLANEANGLEUNIT": ["RADIAN"],
            "SOLIDANGLEUNIT": ["STERADIAN"], "MASSUNIT": ["GRAM"], "TIMEUNIT": ["SECOND"], "THERMODYNAMICTEMPERATUREUNIT": ["KELVIN", "DEGREE_CELSIUS"],
            "LUMINOUSINTENSITYUNIT": ["CANDELA"], "ELECTRICCURRENTUNIT": ["AMPERE"], "FORCEUNIT": ["NEWTON"], "PRESSUREUNIT": ["PASCAL"],
            "ENERGYUNIT": ["JOULE"], "POWERUNIT": ["WATT"], "FREQUENCYUNIT": ["HERTZ"], "ILLUMINANCEUNIT": ["LUX"], "LUMINOUSFLUXUNIT": ["LUMEN"],
        ]
        for e in f.all("IFCSIUNIT") {
            guard let ut = a(e, "UnitType").enumValue, let nm = a(e, "Name").enumValue, let ok = siNames[ut] else { continue }
            if !ok.contains(nm) { fail("IfcSIUnit.WR1", "IfcSIUnit name does not match its unit type", e.id) }
        }
        for e in f.all("IFCUNITASSIGNMENT") {
            var types: [String: Int] = [:]
            for u in a(e, "Units").refs {
                guard let ue = f[u] else { continue }
                let ut = a(ue, "UnitType").enumValue
                if let ut, ut != "USERDEFINED" { types[ut, default: 0] += 1 }
            }
            if types.values.contains(where: { $0 > 1 }) { fail("IfcUnitAssignment.WR01", "IfcUnitAssignment has more than one unit of the same type", e.id) }
        }

        // Project and relationships.
        var aggregatedParts = Set<Int>()
        for r in f.all("IFCRELAGGREGATES") {
            let whole = a(r, "RelatingObject").ref, parts = a(r, "RelatedObjects").refs
            aggregatedParts.formUnion(parts)
            if let w = whole, parts.contains(w) { fail("IfcRelAggregates.NoSelfReference", "An object aggregates itself", r.id) }
            if parts.isEmpty { fail("IfcRelAggregates.RelatedObjects", "IfcRelAggregates has no related objects", r.id) }
        }
        for p in f.all("IFCPROJECT") {
            if a(p, "Name").string?.isEmpty ?? true { fail("IfcProject.HasName", "IfcProject has no name", p.id) }
            if a(p, "RepresentationContexts").refs.contains(where: { f[$0]?.type == "IFCGEOMETRICREPRESENTATIONSUBCONTEXT" }) {
                fail("IfcProject.CorrectContext", "IfcProject lists a representation subcontext", p.id)
            }
            if aggregatedParts.contains(p.id) { fail("IfcProject.NoDecomposition", "IfcProject is part of an aggregation", p.id) }
        }
        for r in f.all("IFCRELCONTAINEDINSPATIALSTRUCTURE") {
            if a(r, "RelatedElements").refs.contains(where: { isa($0, "IFCSPATIALSTRUCTUREELEMENT") }) {
                fail("IfcRelContainedInSpatialStructure.WR31", "A spatial structure element is contained (instead of aggregated)", r.id)
            }
        }
        for r in f.all("IFCRELVOIDSELEMENT") where a(r, "RelatingBuildingElement").ref == a(r, "RelatedOpeningElement").ref {
            fail("IfcRelVoidsElement.NoSelfReference", "An element voids itself", r.id)
        }
        for r in f.all("IFCRELDEFINESBYPROPERTIES") where a(r, "RelatedObjects").refs.isEmpty {
            fail("IfcRelDefinesByProperties.RelatedObjects", "IfcRelDefinesByProperties has no related objects", r.id)
        }
        for ps in f.all("IFCPROPERTYSET") {
            if a(ps, "Name").string?.isEmpty ?? true { fail("IfcPropertySet.ExistsName", "IfcPropertySet has no name", ps.id) }
            let props = a(ps, "HasProperties").refs
            if props.isEmpty { fail("IfcPropertySet.HasProperties", "IfcPropertySet has no properties", ps.id) }
            let names = props.compactMap { f[$0].flatMap { a($0, "Name").string } }
            if Set(names).count != names.count { fail("IfcPropertySet.UniquePropertyNames", "IfcPropertySet has duplicate property names", ps.id) }
        }
        for q in f.all("IFCELEMENTQUANTITY") {
            let names = a(q, "Quantities").refs.compactMap { f[$0].flatMap { a($0, "Name").string } }
            if !is2x3, Set(names).count != names.count { fail("IfcElementQuantity.UniqueQuantityNames", "IfcElementQuantity has duplicate quantity names", q.id) }
        }
        for (type, attr) in [("IFCQUANTITYLENGTH", "LengthValue"), ("IFCQUANTITYAREA", "AreaValue"), ("IFCQUANTITYVOLUME", "VolumeValue"),
                             ("IFCQUANTITYCOUNT", "CountValue"), ("IFCQUANTITYWEIGHT", "WeightValue")] {
            for e in f.all(type) where (a(e, attr).double ?? 0) < 0 {
                fail("\(t.className(type) ?? type).WR21", "\(t.className(type) ?? type) value must not be negative", e.id)
            }
        }
        for e in f.all("IFCMATERIALLAYER") where (a(e, "LayerThickness").double ?? 0) < 0 {
            fail("IfcMaterialLayer.NormalizedThickness", "IfcMaterialLayer thickness must not be negative", e.id)
        }
        for e in f.all("IFCMATERIALLAYERSET") where a(e, "MaterialLayers").refs.isEmpty {
            fail("IfcMaterialLayerSet.MaterialLayers", "IfcMaterialLayerSet has no layers", e.id)
        }
        // A standard-case wall (and IFC4 slab) carries exactly one material layer set usage.
        if t.contains("IFCWALLSTANDARDCASE") {
            var usage: [Int: Int] = [:]
            for r in f.all("IFCRELASSOCIATESMATERIAL") where f[a(r, "RelatingMaterial").ref]?.type == "IFCMATERIALLAYERSETUSAGE" {
                for o in a(r, "RelatedObjects").refs { usage[o, default: 0] += 1 }
            }
            for type in ["IFCWALLSTANDARDCASE", "IFCSLABSTANDARDCASE"] {
                for e in f.all(type) where usage[e.id] != 1 {
                    fail("\(t.className(type) ?? type).HasMaterialLayerSetUsage", "\(t.className(type) ?? type) needs exactly one IfcMaterialLayerSetUsage", e.id)
                }
            }
        }
        moreWhereRules(f, t, is2x3: is2x3, a: a, isa: isa, dim: { dim($0) }, report: fail)
        return order.map { r in
            let (sev, msg, ids) = hits[r]!
            return IFCValidationIssue(severity: sev, code: "WR-" + r, message: "\(ids.count) instance(s) violate \(r): \(msg)", instances: ids.sorted())
        }
    }
}

extension IFCValidator {
    /// Presentation, profile, actor/address, type, grouping, material association and property WHERE rules.
    static func moreWhereRules(_ f: STEPFile, _ t: IFCSchemaTable, is2x3: Bool, a: (StepEntity, String) -> StepValue, isa: (Int?, String) -> Bool,
                               dim: (Int?) -> Int?, report: (String, String, Int, IssueSeverity) -> Void) {
        func fail(_ r: String, _ m: String, _ id: Int, _ s: IssueSeverity = .error) { report(r, m, id, s) }
        func cls(_ type: String) -> String { t.className(type) ?? type }
        func exists(_ v: StepValue) -> Bool {
            switch v { case .null, .derived: return false; case .list(let l): return !l.isEmpty; default: return true }
        }
        func typedName(_ v: StepValue) -> String? { if case .typed(let n, _) = v { return n.uppercased() }; return nil }
        func has(_ e: StepEntity, _ name: String) -> Bool { t.attributeNames(e.type)?.contains(name) ?? false }
        let entities = f.entities.values.sorted { $0.id < $1.id }

        // USERDEFINED enumerations need their user-defined companion value.
        for e in entities where e.parts.isEmpty {
            if a(e, "PredefinedType").enumValue == "USERDEFINED" {
                let companion = ["ElementType", "ProcessType", "ResourceType", "ObjectType"].first { has(e, $0) }
                if let c = companion, !exists(a(e, c)) {
                    fail("\(cls(e.type)).CorrectPredefinedType", "PredefinedType USERDEFINED without \(c)", e.id)
                }
            }
            if e.type == "IFCACTORROLE", a(e, "Role").enumValue == "USERDEFINED", !exists(a(e, "UserDefinedRole")) {
                fail("IfcActorRole.WR1", "Role USERDEFINED without UserDefinedRole", e.id)
            }
            if t.isSubtype(e.type, of: "IFCADDRESS"), a(e, "Purpose").enumValue == "USERDEFINED", !exists(a(e, "UserDefinedPurpose")) {
                fail("IfcAddress.WR1", "Purpose USERDEFINED without UserDefinedPurpose", e.id)
            }
        }
        for e in f.all("IFCPOSTALADDRESS") where !["InternalLocation", "AddressLines", "PostalBox", "PostalCode", "Town", "Region", "Country"].contains(where: { exists(a(e, $0)) }) {
            fail("IfcPostalAddress.WR1", "IfcPostalAddress has no address data", e.id)
        }
        for e in f.all("IFCTELECOMADDRESS") where !["TelephoneNumbers", "FacsimileNumbers", "PagerNumber", "ElectronicMailAddresses", "WWWHomePageURL", "MessagingIDs"].contains(where: { exists(a(e, $0)) }) {
            fail("IfcTelecomAddress.WR1", "IfcTelecomAddress has no contact data", e.id)
        }

        // Presentation.
        let boxAlignments: Set<String> = ["top-left", "top-middle", "top-right", "middle-left", "center", "middle-right", "bottom-left", "bottom-middle", "bottom-right"]
        for e in f.all("IFCTEXTLITERALWITHEXTENT") {
            if let b = a(e, "BoxAlignment").string, !boxAlignments.contains(b.lowercased()) { fail("IfcBoxAlignment.WR1", "Box alignment '\(b)' is not one of the nine allowed values", e.id) }
            if f[a(e, "Extent").ref]?.type == "IFCPLANARBOX" { fail("IfcTextLiteralWithExtent.WR31", "The extent of a text literal must not be an IfcPlanarBox", e.id) }
        }
        for e in f.all("IFCTEXTSTYLEFONTMODEL") {
            let v = a(e, "FontSize")
            let ok = ["IFCLENGTHMEASURE", "IFCPOSITIVELENGTHMEASURE"].contains(typedName(v) ?? "") && (v.double ?? 0) > 0
            if exists(v), !ok { fail("IfcTextStyleFontModel.MeasureOfFontSize", "Font size must be a positive length measure", e.id) }
        }
        for e in f.all("IFCANNOTATIONCURVEOCCURRENCE") {
            if let item = a(e, "Item").ref, !isa(item, "IFCCURVE") { fail("IfcAnnotationCurveOccurrence.WR31", "Annotation curve occurrence item is not a curve", e.id) }
        }
        for e in f.all("IFCANNOTATIONSURFACE") {
            let ok = ["IFCSURFACE", "IFCSHELLBASEDSURFACEMODEL", "IFCFACEBASEDSURFACEMODEL", "IFCSOLIDMODEL", "IFCBOOLEANRESULT", "IFCCSGPRIMITIVE3D"].contains { isa(a(e, "Item").ref, $0) }
            if !ok { fail("IfcAnnotationSurface.WR01", "Annotation surface item is not a surface or solid", e.id) }
        }
        for e in f.all("IFCSHAPEREPRESENTATION") where a(e, "RepresentationType").string?.uppercased() == "GEOMETRICCURVESET" {
            for item in a(e, "Items").refs {
                var ok = isa(item, "IFCGEOMETRICCURVESET") || isa(item, "IFCCURVE") || isa(item, "IFCPOINT") || isa(item, "IFCANNOTATIONFILLAREA")
                if !ok, let g = f[item], isa(item, "IFCGEOMETRICSET") {
                    ok = a(g, "Elements").refs.allSatisfy { isa($0, "IFCPOINT") || isa($0, "IFCCURVE") }
                }
                if !ok { fail("IfcShapeRepresentation.CorrectItemsForType", "IfcShapeRepresentation items do not match RepresentationType", e.id); break }
            }
        }

        // Curves.
        for e in entities where t.isSubtype(e.type, of: "IFCBSPLINECURVE") {
            let dims = Set(a(e, "ControlPointsList").refs.compactMap { dim($0) })
            if dims.count > 1 { fail("\(cls(e.type)).SameDim", "B-spline control points have different dimensions", e.id) }
        }
        for e in f.all("IFCINDEXEDPOLYCURVE") {
            let segs = (a(e, "Segments").list ?? []).map { s -> [Int] in
                if case .typed(_, let args) = s { return (args.first?.list ?? []).compactMap { $0.double.map { Int($0) } } }
                return []
            }
            if segs.count > 1, zip(segs, segs.dropFirst()).contains(where: { $0.last != $1.first }) {
                fail("IfcIndexedPolyCurve.Consecutive", "Indexed poly curve segments are not consecutive", e.id)
            }
        }

        // Parameterised profiles.
        func d(_ e: StepEntity, _ n: String) -> Double? { a(e, n).double }
        func check(_ type: String, _ rule: String, _ msg: String, _ ok: (StepEntity) -> Bool?) {
            for e in f.all(type) where ok(e) == false { fail("\(cls(type)).\(rule)", msg, e.id) }
        }
        check("IFCCSHAPEPROFILEDEF", "ValidGirth", "Girth must be less than half the depth") { e in d(e, "Girth").flatMap { g in d(e, "Depth").map { g < $0 / 2 } } }
        check("IFCCSHAPEPROFILEDEF", "ValidWallThickness", "Wall thickness must be less than half the width and depth") { e in
            guard let w = d(e, "WallThickness"), let wd = d(e, "Width"), let dp = d(e, "Depth") else { return nil }
            return w < wd / 2 && w < dp / 2
        }
        check("IFCCSHAPEPROFILEDEF", "ValidInternalFilletRadius", "Internal fillet radius must not exceed half the width or depth") { e in
            guard let r = d(e, "InternalFilletRadius"), let wd = d(e, "Width"), let dp = d(e, "Depth") else { return nil }
            return r <= wd / 2 && r <= dp / 2
        }
        check("IFCISHAPEPROFILEDEF", "ValidFlangeThickness", "Flange thickness must be less than half the overall depth") { e in d(e, "FlangeThickness").flatMap { ft in d(e, "OverallDepth").map { 2 * ft < $0 } } }
        check("IFCISHAPEPROFILEDEF", "ValidWebThickness", "Web thickness must be less than the overall width") { e in d(e, "WebThickness").flatMap { w in d(e, "OverallWidth").map { w < $0 } } }
        check("IFCLSHAPEPROFILEDEF", "ValidThickness", "Leg thickness must be less than the depth and width") { e in
            guard let th = d(e, "Thickness"), let dp = d(e, "Depth") else { return nil }
            return th < dp && (d(e, "Width").map { th < $0 } ?? true)
        }
        check("IFCTSHAPEPROFILEDEF", "ValidFlangeThickness", "Flange thickness must be less than the depth") { e in d(e, "FlangeThickness").flatMap { ft in d(e, "Depth").map { ft < $0 } } }
        check("IFCTSHAPEPROFILEDEF", "ValidWebThickness", "Web thickness must be less than the flange width") { e in d(e, "WebThickness").flatMap { w in d(e, "FlangeWidth").map { w < $0 } } }
        check("IFCUSHAPEPROFILEDEF", "ValidFlangeThickness", "Flange thickness must be less than half the depth") { e in d(e, "FlangeThickness").flatMap { ft in d(e, "Depth").map { ft < $0 / 2 } } }
        check("IFCUSHAPEPROFILEDEF", "ValidWebThickness", "Web thickness must be less than the flange width") { e in d(e, "WebThickness").flatMap { w in d(e, "FlangeWidth").map { w < $0 } } }
        check("IFCZSHAPEPROFILEDEF", "ValidFlangeThickness", "Flange thickness must be less than half the depth") { e in d(e, "FlangeThickness").flatMap { ft in d(e, "Depth").map { ft < $0 / 2 } } }
        check("IFCRECTANGLEHOLLOWPROFILEDEF", "ValidWallThickness", "Wall thickness must be less than half of XDim and YDim") { e in
            guard let w = d(e, "WallThickness"), let x = d(e, "XDim"), let y = d(e, "YDim") else { return nil }
            return w < x / 2 && w < y / 2
        }
        check("IFCCIRCLEHOLLOWPROFILEDEF", "WR1", "Wall thickness must be less than the radius") { e in d(e, "WallThickness").flatMap { w in d(e, "Radius").map { w < $0 } } }
        for e in f.all("IFCARBITRARYPROFILEDEFWITHVOIDS") {
            if a(e, "ProfileType").enumValue == "CURVE" { fail("IfcArbitraryProfileDefWithVoids.WR1", "A profile with voids must be an AREA profile", e.id) }
            if a(e, "InnerCurves").refs.contains(where: { f[$0]?.type == "IFCLINE" }) { fail("IfcArbitraryProfileDefWithVoids.WR3", "Inner curves must not be IfcLine", e.id) }
        }

        // Door / window lining.
        for type in ["IFCWINDOWLININGPROPERTIES", "IFCDOORLININGPROPERTIES"] {
            for e in f.all(type) where exists(a(e, "LiningDepth")) && !exists(a(e, "LiningThickness")) {
                fail("\(cls(type)).WR31", "Lining depth is given without a lining thickness", e.id)
            }
        }

        // Properties and CRS operations.
        for e in f.all("IFCPROPERTYLISTVALUE") {
            let types = Set((a(e, "ListValues").list ?? []).map { typedName($0) ?? "?" })
            if types.count > 1 { fail("IfcPropertyListValue.WR31", "List values have different types", e.id) }
        }
        for e in f.all("IFCRIGIDOPERATION") where exists(a(e, "FirstCoordinate")) && exists(a(e, "SecondCoordinate")) {
            if typedName(a(e, "FirstCoordinate")) != typedName(a(e, "SecondCoordinate")) {
                fail("IfcRigidOperation.FirstCoordinateAndSecondCoordinateSameType", "First and second coordinates have different measure types", e.id)
            }
        }
        var psetNames: [Int: [String]] = [:]
        for r in f.all("IFCRELDEFINESBYPROPERTIES") {
            guard let ps = f[a(r, "RelatingPropertyDefinition").ref], ps.type == "IFCPROPERTYSET", let n = a(ps, "Name").string else { continue }
            for o in a(r, "RelatedObjects").refs { psetNames[o, default: []].append(n) }
        }
        for (o, names) in psetNames.sorted(by: { $0.key < $1.key }) where Set(names).count != names.count {
            fail("IfcObject.UniquePropertySetNames", "An object has several property sets with the same name", o, .warning)
        }

        // Units: named (conversion-based / context-dependent) units have the dimensions of their unit type.
        let dims: [String: [Int]] = [
            "LENGTHUNIT": [1, 0, 0, 0, 0, 0, 0], "MASSUNIT": [0, 1, 0, 0, 0, 0, 0], "TIMEUNIT": [0, 0, 1, 0, 0, 0, 0],
            "ELECTRICCURRENTUNIT": [0, 0, 0, 1, 0, 0, 0], "THERMODYNAMICTEMPERATUREUNIT": [0, 0, 0, 0, 1, 0, 0],
            "AMOUNTOFSUBSTANCEUNIT": [0, 0, 0, 0, 0, 1, 0], "LUMINOUSINTENSITYUNIT": [0, 0, 0, 0, 0, 0, 1],
            "PLANEANGLEUNIT": [0, 0, 0, 0, 0, 0, 0], "SOLIDANGLEUNIT": [0, 0, 0, 0, 0, 0, 0], "AREAUNIT": [2, 0, 0, 0, 0, 0, 0],
            "VOLUMEUNIT": [3, 0, 0, 0, 0, 0, 0], "FORCEUNIT": [1, 1, -2, 0, 0, 0, 0], "PRESSUREUNIT": [-1, 1, -2, 0, 0, 0, 0],
            "ENERGYUNIT": [2, 1, -2, 0, 0, 0, 0], "POWERUNIT": [2, 1, -3, 0, 0, 0, 0], "FREQUENCYUNIT": [0, 0, -1, 0, 0, 0, 0],
        ]
        for e in entities where e.type == "IFCCONVERSIONBASEDUNIT" || e.type == "IFCCONTEXTDEPENDENTUNIT" || e.type == "IFCCONVERSIONBASEDUNITWITHOFFSET" {
            guard let ut = a(e, "UnitType").enumValue, let want = dims[ut], let de = f[a(e, "Dimensions").ref] else { continue }
            let got = de.args.compactMap { $0.double.map { Int($0) } }
            if got.count == 7, got != want { fail("IfcNamedUnit.WR1", "Unit dimensions do not match the unit type", e.id) }
        }
        // Compound plane angles (site latitude / longitude).
        for e in f.all("IFCSITE") {
            for attr in ["RefLatitude", "RefLongitude"] {
                let v = (a(e, attr).list ?? []).compactMap { $0.double }
                guard v.count >= 3 else { continue }
                if is2x3, !(v[0] >= -360 && v[0] < 360) { fail("IfcCompoundPlaneAngleMeasure.WR2", "Compound angle degrees out of range", e.id) }
                if abs(v[1]) >= 60 { fail("IfcCompoundPlaneAngleMeasure.MinutesInRange", "Compound angle minutes out of range", e.id) }
                if abs(v[2]) >= 60 { fail("IfcCompoundPlaneAngleMeasure.SecondsInRange", "Compound angle seconds out of range", e.id) }
                if v.count > 3, abs(v[3]) >= 1_000_000 { fail("IfcCompoundPlaneAngleMeasure.MicrosecondsInRange", "Compound angle microseconds out of range", e.id) }
                if !(v.allSatisfy { $0 >= 0 } || v.allSatisfy { $0 <= 0 }) { fail("IfcCompoundPlaneAngleMeasure.ConsistentSign", "Compound angle components have mixed signs", e.id) }
            }
        }

        // Groups and material associations.
        for r in f.all("IFCRELASSIGNSTOGROUP") where f[a(r, "RelatingGroup").ref]?.type == "IFCZONE" {
            if a(r, "RelatedObjects").refs.contains(where: { !(isa($0, "IFCZONE") || isa($0, "IFCSPACE") || isa($0, "IFCSPATIALZONE")) }) {
                fail("IfcZone.WR1", "A zone groups objects other than spaces and zones", a(r, "RelatingGroup").ref ?? r.id)
            }
        }
        for r in f.all("IFCRELASSOCIATESMATERIAL") {
            let objs = a(r, "RelatedObjects").refs
            if objs.contains(where: { isa($0, "IFCFEATUREELEMENTSUBTRACTION") || isa($0, "IFCVIRTUALELEMENT") }) {
                fail("IfcRelAssociatesMaterial.NoVoidElement", "Material associated with an opening or virtual element", r.id)
            }
            if !is2x3 {
                let allowed = ["IFCELEMENT", "IFCELEMENTTYPE", "IFCWINDOWSTYLE", "IFCDOORSTYLE", "IFCSTRUCTURALMEMBER", "IFCPORT"]
                if objs.contains(where: { o in !allowed.contains { isa(o, $0) } }) {
                    fail("IfcRelAssociatesMaterial.AllowedElements", "Material associated with an object that cannot have a material", r.id)
                }
            }
        }
    }
}
