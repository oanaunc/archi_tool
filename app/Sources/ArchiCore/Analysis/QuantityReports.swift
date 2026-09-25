// Oanarina Archi Tool — GPL-3.0-or-later
// Quantity takeoff split by construction phase and level, and a priced bill of quantities (numbered sections by trade,
// unit rates, subtotals, contingency, VAT and currency formatting).
import Foundation

// MARK: - Takeoff by phase and level

public struct PhaseLevelTakeoff {
    public struct Group: Hashable {
        public var phase: String
        /// "new" (built in the phase) or "demolished" (removed in the phase).
        public var work: String
        public var level: Int
        public var levelName: String
        public var lines: [TakeoffLine]
    }
    public var groups: [Group]

    /// Elements are grouped by props "phaseCreated" (new work) and "phaseDemolished" (demolition); untagged elements
    /// belong to the current phase. Openings follow their own phase and are still deducted from their host wall.
    public static func compute(_ doc: ArchiDocument) -> PhaseLevelTakeoff {
        let current = Phasing.currentPhase(doc)
        let phases = doc.phases.isEmpty ? ["New Construction"] : doc.phases
        func phaseName(_ p: String?) -> String {
            guard let i = Phasing.phaseIndex(p, doc) else { return phases[min(current, phases.count - 1)] }
            return phases[i]
        }
        var buckets: [String: Set<EntityID>] = [:]
        func key(_ phase: String, _ work: String, _ level: Int) -> String { "\(phase)\u{1}\(work)\u{1}\(level)" }
        for el in doc.elements {
            buckets[key(phaseName(el.props["phaseCreated"]), "new", el.level), default: []].insert(el.id)
            if let dem = el.props["phaseDemolished"], Phasing.phaseIndex(dem, doc) != nil {
                buckets[key(phaseName(dem), "demolished", el.level), default: []].insert(el.id)
            }
        }
        var groups: [Group] = []
        for (k, ids) in buckets {
            let parts = k.components(separatedBy: "\u{1}")
            guard parts.count == 3, let lv = Int(parts[2]) else { continue }
            var sub = doc
            // Keep hosted openings for wall deductions; they are counted only when they belong to the group.
            let hostedByKept = Set(doc.elements.compactMap { e -> EntityID? in
                if case .opening(let o) = e.geometry, ids.contains(o.hostWall) { return e.id }; return nil })
            sub.elements = doc.elements.filter { ids.contains($0.id) || hostedByKept.contains($0.id) }
            var t = QuantityTakeoff.compute(sub, level: lv)
            t.lines = t.lines.compactMap { l -> TakeoffLine? in
                guard ["door", "window", "opening", "niche"].contains(l.category) else { return l }
                var c = l
                c.ids = l.ids.filter { ids.contains($0) }
                guard !c.ids.isEmpty else { return nil }
                c.count = c.ids.count
                let u = doc.units.mm / 1000
                c.area = c.ids.reduce(0) { a, id in if let e = doc.element(id), case .opening(let o) = e.geometry { return a + o.width * o.height * u * u }; return a }
                return c
            }
            guard !t.lines.isEmpty else { continue }
            groups.append(Group(phase: parts[0], work: parts[1], level: lv, levelName: doc.level(lv)?.name ?? "Level \(lv)", lines: t.lines))
        }
        let elevation = { (l: Int) in doc.level(l)?.elevation ?? 0 }
        groups.sort {
            let a = phases.firstIndex(of: $0.phase) ?? 0, b = phases.firstIndex(of: $1.phase) ?? 0
            if a != b { return a < b }
            if $0.work != $1.work { return $0.work == "demolished" }
            return elevation($0.level) < elevation($1.level)
        }
        return PhaseLevelTakeoff(groups: groups)
    }

    /// Total of a measure for a category over the groups that match.
    public func total(_ category: String, _ measure: String, phase: String? = nil, work: String? = nil, level: Int? = nil) -> Double {
        groups.filter { (phase == nil || $0.phase == phase) && (work == nil || $0.work == work) && (level == nil || $0.level == level) }
            .flatMap(\.lines).filter { $0.category == category }.reduce(0) { $0 + $1.quantity(measure) }
    }

    public var table: [[String]] {
        var rows = [["phase", "work", "level", "category", "type", "material", "count", "length_m", "area_m2", "volume_m3"]]
        for g in groups {
            for l in g.lines { rows.append([g.phase, g.work, g.levelName, l.category, l.key, l.material, "\(l.count)", fmt(l.length, 3), fmt(l.area, 3), fmt(l.volume, 3)]) }
        }
        return rows
    }
    public var csv: String { CSVText.make(table) }
}

// MARK: - Bill of quantities

public struct BoQOptions {
    /// Contingency and VAT in percent.
    public var contingency: Double = 0
    public var vat: Double = 0
    public var currency: String? = nil
    public init() {}
    /// BOQCONTINGENCY, BOQVAT, COSTCURRENCY variables.
    public static func from(_ doc: ArchiDocument) -> BoQOptions {
        var o = BoQOptions()
        o.contingency = doc.variable("BOQCONTINGENCY").flatMap(Double.init) ?? 0
        o.vat = doc.variable("BOQVAT").flatMap(Double.init) ?? 0
        o.currency = doc.variable("COSTCURRENCY")
        return o
    }
}

public struct BoQItem: Hashable {
    public var ref: String
    public var description: String
    public var unit: String
    public var quantity: Double
    public var rate: Double
    public var amount: Double { (quantity * rate * 100).rounded() / 100 }
    public var ids: [EntityID]
}

public struct BoQSection: Hashable {
    public var number: Int
    public var title: String
    public var items: [BoQItem]
    public var subtotal: Double { items.reduce(0) { $0 + $1.amount } }
}

public struct BillOfQuantities {
    public var currency: String
    public var sections: [BoQSection]
    public var contingencyPercent: Double
    public var vatPercent: Double
    /// Takeoff lines without a rate (listed as unpriced items).
    public var unpriced: [TakeoffLine]

    public var net: Double { sections.reduce(0) { $0 + $1.subtotal } }
    public var contingency: Double { (net * contingencyPercent).rounded() / 100 }
    public var vat: Double { ((net + contingency) * vatPercent).rounded() / 100 }
    public var total: Double { net + contingency + vat }

    /// Trades in bill order: title and the takeoff categories they contain.
    public static let trades: [(String, [String])] = [
        ("Substructure and concrete", ["slab", "column", "beam"]), ("Walls", ["wall", "curtainWall"]), ("Roofs", ["roof"]),
        ("Doors", ["door"]), ("Windows", ["window"]), ("Openings", ["opening", "niche"]), ("Stairs and railings", ["stair", "railing"]),
        ("Fittings and equipment", ["component"]), ("Finishes (rooms)", ["space"]),
    ]
    static let unitName = ["count": "nr", "length": "m", "area": "m²", "volume": "m³"]

    public static func build(_ takeoff: Takeoff, table: CostTable, options: BoQOptions = BoQOptions()) -> BillOfQuantities {
        let est = CostEstimate.compute(takeoff, table: table)
        var sections: [BoQSection] = []
        for (title, cats) in trades {
            let lines = est.lines.filter { cats.contains($0.line.category) }
            guard !lines.isEmpty else { continue }
            let n = sections.count + 1
            var items: [BoQItem] = []
            for (i, c) in lines.enumerated() {
                var desc = c.line.key
                if !c.line.material.isEmpty && c.line.material != c.line.key { desc += ", " + c.line.material }
                if c.line.category == "wall" || c.line.category == "slab" || c.line.category == "roof" { desc = c.line.category.capitalized + " " + desc }
                items.append(BoQItem(ref: "\(n).\(i + 1)", description: desc, unit: unitName[c.measure] ?? c.measure, quantity: (c.quantity * 1000).rounded() / 1000,
                                     rate: c.unitPrice, ids: c.line.ids))
            }
            sections.append(BoQSection(number: n, title: title, items: items))
        }
        return BillOfQuantities(currency: options.currency ?? table.currency, sections: sections, contingencyPercent: options.contingency, vatPercent: options.vat, unpriced: est.unpriced)
    }

    /// Amount with thousands separators and the currency symbol or code ("€ 12,345.60", "12.345,60 lei").
    public static func money(_ v: Double, currency: String) -> String {
        let neg = v < 0
        let cents = Int((abs(v) * 100).rounded())
        var intPart = String(cents / 100)
        let frac = String(format: "%02d", cents % 100)
        let comma = ["RON", "LEI", "DKK", "SEK", "NOK", "PLN", "CZK", "HUF"].contains(currency.uppercased())
        let sep = comma ? "." : ",", dec = comma ? "," : "."
        var grouped = ""
        while intPart.count > 3 { grouped = sep + String(intPart.suffix(3)) + grouped; intPart = String(intPart.dropLast(3)) }
        let num = (neg ? "-" : "") + intPart + grouped + dec + frac
        switch currency.uppercased() {
        case "EUR": return "€ " + num
        case "USD": return "$ " + num
        case "GBP": return "£ " + num
        case "JPY": return "¥ " + num
        case "RON", "LEI": return num + " lei"
        default: return num + " " + currency
        }
    }

    public var table: [[String]] {
        var rows = [["ref", "description", "unit", "quantity", "rate", "amount", "currency"]]
        for s in sections {
            rows.append(["\(s.number)", s.title.uppercased(), "", "", "", "", ""])
            for i in s.items { rows.append([i.ref, i.description, i.unit, fmt(i.quantity, 3), fmt(i.rate, 2), fmt(i.amount, 2), currency]) }
            rows.append(["", "Subtotal \(s.number) \(s.title)", "", "", "", fmt(s.subtotal, 2), currency])
        }
        rows.append(["", "NET TOTAL", "", "", "", fmt(net, 2), currency])
        if contingencyPercent != 0 { rows.append(["", "Contingency \(fmt(contingencyPercent, 2)) %", "", "", "", fmt(contingency, 2), currency]) }
        if vatPercent != 0 { rows.append(["", "VAT \(fmt(vatPercent, 2)) %", "", "", "", fmt(vat, 2), currency]) }
        rows.append(["", "GRAND TOTAL", "", "", "", fmt(total, 2), currency])
        for u in unpriced { rows.append(["-", "Not priced: \(u.category) \(u.key)", "", "", "", "", ""]) }
        return rows
    }
    public var csv: String { CSVText.make(table) }
    public var xlsx: Data { XLSX.write([XLSX.Sheet(name: "Bill of Quantities", rows: table)]) }

    public var report: String {
        var s = ""
        for sec in sections {
            s += "\(sec.number) \(sec.title)\n"
            for i in sec.items { s += "  \(i.ref) \(i.description): \(fmt(i.quantity, 3)) \(i.unit) × \(fmt(i.rate, 2)) = \(BillOfQuantities.money(i.amount, currency: currency))\n" }
            s += "  Subtotal: \(BillOfQuantities.money(sec.subtotal, currency: currency))\n"
        }
        s += "Net total: \(BillOfQuantities.money(net, currency: currency))"
        if contingencyPercent != 0 { s += "\nContingency \(fmt(contingencyPercent, 2)) %: \(BillOfQuantities.money(contingency, currency: currency))" }
        if vatPercent != 0 { s += "\nVAT \(fmt(vatPercent, 2)) %: \(BillOfQuantities.money(vat, currency: currency))" }
        s += "\nGrand total: \(BillOfQuantities.money(total, currency: currency))"
        if !unpriced.isEmpty { s += "\nNot priced: " + unpriced.map { "\($0.category) \($0.key)" }.joined(separator: "; ") }
        return s
    }
}
