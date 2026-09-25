// Oanarina Archi Tool — GPL-3.0-or-later
// IFC export class mapping (IO-024): components and generic elements are exported as the IFC class chosen by the
// element prop `IfcExportAs` (Revit's convention, e.g. "IfcSanitaryTerminal.WASHHANDBASIN"), the drawing's mapping table
// (variables IFCMAP:<category or element type>, command IFCMAP) or built-in defaults by component category. Only IfcElement
// subclasses with the IFC4 attribute layout (…, ObjectPlacement, Representation, Tag, PredefinedType) are offered.
import Foundation

public struct IFCClassMapping: Hashable, CustomStringConvertible {
    /// IFC class in schema spelling, e.g. "IfcSanitaryTerminal".
    public var ifcClass: String
    /// Predefined type (enumeration value) or nil = NOTDEFINED. Values not in the enumeration are exported as USERDEFINED
    /// with the value as ObjectType.
    public var predefinedType: String?
    public init(ifcClass: String, predefinedType: String? = nil) { self.ifcClass = ifcClass; self.predefinedType = predefinedType }
    public var description: String { ifcClass + (predefinedType.map { "." + $0 } ?? "") }
}

public enum IFCClassMap {
    /// Supported classes (upper case) → (schema spelling, predefined types, common property set).
    public static let supported: [String: (name: String, types: [String], pset: String)] = [
        "IFCFURNITURE": ("IfcFurniture", ["CHAIR", "TABLE", "DESK", "BED", "FILECABINET", "SHELF", "SOFA"], "Pset_FurnitureTypeCommon"),
        "IFCSANITARYTERMINAL": ("IfcSanitaryTerminal", ["BATH", "BIDET", "CISTERN", "SHOWER", "SINK", "SANITARYFOUNTAIN", "TOILETPAN", "URINAL", "WASHHANDBASIN", "WCSEAT"], "Pset_SanitaryTerminalTypeCommon"),
        "IFCLIGHTFIXTURE": ("IfcLightFixture", ["POINTSOURCE", "DIRECTIONSOURCE", "SECURITYLIGHTING"], "Pset_LightFixtureTypeCommon"),
        "IFCELECTRICAPPLIANCE": ("IfcElectricAppliance", ["DISHWASHER", "ELECTRICCOOKER", "FREESTANDINGELECTRICHEATER", "FREESTANDINGFAN", "FREESTANDINGWATERHEATER",
                                                          "FREESTANDINGWATERCOOLER", "FREEZER", "FRIDGE_FREEZER", "HANDDRYER", "KITCHENMACHINE", "MICROWAVE", "PHOTOCOPIER",
                                                          "REFRIGERATOR", "TUMBLEDRYER", "VENDINGMACHINE", "WASHINGMACHINE"], "Pset_ElectricApplianceTypeCommon"),
        "IFCGEOGRAPHICELEMENT": ("IfcGeographicElement", ["TERRAIN"], "Pset_GeographicElementCommon"),
        "IFCSHADINGDEVICE": ("IfcShadingDevice", ["JALOUSIE", "SHUTTER", "AWNING"], "Pset_ShadingDeviceCommon"),
        "IFCCHIMNEY": ("IfcChimney", [], "Pset_ChimneyCommon"),
        "IFCMEMBER": ("IfcMember", ["BRACE", "CHORD", "COLLAR", "MEMBER", "MULLION", "PLATE", "POST", "PURLIN", "RAFTER", "STRINGER", "STRUT", "STUD"], "Pset_MemberCommon"),
        "IFCPLATE": ("IfcPlate", ["CURTAIN_PANEL", "SHEET"], "Pset_PlateCommon"),
        "IFCCOVERING": ("IfcCovering", ["CEILING", "FLOORING", "CLADDING", "ROOFING", "MOLDING", "SKIRTINGBOARD", "INSULATION", "MEMBRANE", "SLEEVING", "WRAPPING"], "Pset_CoveringCommon"),
        "IFCRAILING": ("IfcRailing", ["HANDRAIL", "GUARDRAIL", "BALUSTRADE"], "Pset_RailingCommon"),
        "IFCTRANSPORTELEMENT": ("IfcTransportElement", ["ELEVATOR", "ESCALATOR", "MOVINGWALKWAY", "CRANEWAY", "LIFTINGGEAR"], "Pset_TransportElementCommon"),
        "IFCDISCRETEACCESSORY": ("IfcDiscreteAccessory", ["ANCHORPLATE", "BRACKET", "SHOE"], "Pset_DiscreteAccessoryCommon"),
        "IFCBUILDINGELEMENTPROXY": ("IfcBuildingElementProxy", ["COMPLEX", "ELEMENT", "PARTIAL", "PROVISIONFORVOID", "PROVISIONFORSPACE"], "Pset_BuildingElementProxyCommon"),
    ]

    /// Built-in defaults by component category (lower case); furniture stays IfcFurnishingElement unless mapped.
    public static let defaults: [String: String] = [
        "plumbing": "IfcSanitaryTerminal", "sanitary": "IfcSanitaryTerminal", "bathroom": "IfcSanitaryTerminal",
        "lighting": "IfcLightFixture", "light": "IfcLightFixture", "appliance": "IfcElectricAppliance", "appliances": "IfcElectricAppliance",
        "planting": "IfcGeographicElement", "tree": "IfcGeographicElement", "vegetation": "IfcGeographicElement",
        "elevator": "IfcTransportElement", "lift": "IfcTransportElement",
    ]

    /// Parses "IfcSanitaryTerminal.WASHHANDBASIN", "IFCLIGHTFIXTURE", "SanitaryTerminal/SINK".
    public static func parse(_ s: String) -> IFCClassMapping? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let parts = t.split(whereSeparator: { $0 == "." || $0 == "/" || $0 == ":" }).map(String.init)
        var cls = parts[0].uppercased()
        if !cls.hasPrefix("IFC") { cls = "IFC" + cls }
        guard let info = supported[cls] else { return nil }
        var pdt = parts.count > 1 ? parts[1].uppercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ")) : nil
        if pdt == "NOTDEFINED" || pdt?.isEmpty == true { pdt = nil }
        return IFCClassMapping(ifcClass: info.name, predefinedType: pdt)
    }

    /// The drawing's mapping table (IFCMAP:<key> variables), keys in the case they were typed are not kept: upper case.
    public static func table(_ doc: ArchiDocument) -> [String: IFCClassMapping] {
        var out: [String: IFCClassMapping] = [:]
        for (k, v) in doc.variables where k.hasPrefix("IFCMAP:") {
            if let m = parse(v) { out[String(k.dropFirst(7))] = m }
        }
        return out
    }

    /// Mapping for an element: prop IfcExportAs / ifcClass, then IFCMAP:<category> (components), IFCMAP:<element type>,
    /// then the category defaults. nil = the exporter's standard class.
    public static func resolve(_ el: BIMElement, doc: ArchiDocument) -> IFCClassMapping? {
        for key in ["IfcExportAs", "IFCExportAs", "ifcExportAs", "ifcClass"] { if let v = el.props[key], let m = parse(v) { return m } }
        var category: String?
        if case .component(let c) = el.geometry { category = c.category }
        if let c = category, let v = doc.variable("IFCMAP:" + c), let m = parse(v) { return m }
        if let v = doc.variable("IFCMAP:" + el.typeName), let m = parse(v) { return m }
        if let c = category?.lowercased() {
            if let d = defaults[c] { return parse(d) }
            for (k, v) in defaults where c.contains(k) { return parse(v) }
        }
        return nil
    }

    /// (entity keyword, PredefinedType literal, ObjectType or nil) for writing.
    static func literal(_ m: IFCClassMapping) -> (entity: String, pdt: String, objectType: String?) {
        let key = m.ifcClass.uppercased()
        let types = supported[key]?.types ?? []
        guard let p = m.predefinedType else { return (key, ".NOTDEFINED.", nil) }
        if types.contains(p) { return (key, ".\(p).", nil) }
        return (key, ".USERDEFINED.", p)
    }
}
