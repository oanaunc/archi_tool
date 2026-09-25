// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// A unit rate: price per measure (count, length m, area m², volume m³) of a takeoff category, optionally for one type key.
public struct UnitPrice: Hashable {
    public var category: String
    public var key: String?
    public var measure: String
    public var price: Double
    public init(category: String, key: String? = nil, measure: String, price: Double) {
        self.category = category.lowercased(); self.key = key; self.measure = measure.lowercased(); self.price = price
    }
}

public struct CostTable {
    public var currency: String
    public var prices: [UnitPrice]
    public init(currency: String = "EUR", prices: [UnitPrice] = []) { self.currency = currency; self.prices = prices }

    static let measures: Set<String> = ["count", "length", "area", "volume"]

    /// Rates stored in drawing variables: `COST:<CATEGORY>[:<TYPE>]:<MEASURE>` = price, currency in `COSTCURRENCY`.
    public static func fromVariables(_ doc: ArchiDocument) -> CostTable {
        var t = CostTable(currency: doc.variable("COSTCURRENCY") ?? "EUR")
        for (k, v) in doc.variables.sorted(by: { $0.key < $1.key }) {
            guard k.uppercased().hasPrefix("COST:"), let price = Double(v.trimmingCharacters(in: .whitespaces)) else { continue }
            if let p = parseKey(String(k.dropFirst(5)), price: price) { t.prices.append(p) }
        }
        return t
    }

    /// "wall:area", "wall:Exterior Brick 365:area".
    static func parseKey(_ k: String, price: Double) -> UnitPrice? {
        let parts = k.split(separator: ":", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2, let meas = parts.last?.lowercased(), measures.contains(meas), !parts[0].isEmpty else { return nil }
        let key = parts.count > 2 ? parts[1..<(parts.count - 1)].joined(separator: ":") : nil
        return UnitPrice(category: parts[0], key: key, measure: meas, price: price)
    }

    public enum CostError: Error, LocalizedError {
        case invalid(String)
        public var errorDescription: String? { if case .invalid(let m) = self { return "Invalid unit price table: \(m)" }; return nil }
    }

    /// JSON: {"currency":"EUR","prices":[{"category":"wall","type":"Generic 200 mm","measure":"area","price":45}]}
    /// or a flat object {"currency":"EUR","wall:area":45,"door:count":350}.
    public static func fromJSON(_ text: String) throws -> CostTable {
        guard let d = text.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw CostError.invalid("expected a JSON object") }
        var t = CostTable(currency: o["currency"] as? String ?? "EUR")
        if let list = o["prices"] as? [[String: Any]] {
            for p in list {
                guard let c = p["category"] as? String, let m = p["measure"] as? String, let price = (p["price"] as? NSNumber)?.doubleValue ?? (p["price"] as? String).flatMap(Double.init) else {
                    throw CostError.invalid("each price needs category, measure and price")
                }
                guard measures.contains(m.lowercased()) else { throw CostError.invalid("unknown measure '\(m)' (count, length, area, volume)") }
                t.prices.append(UnitPrice(category: c, key: (p["type"] ?? p["key"]) as? String, measure: m, price: price))
            }
        }
        for (k, v) in o where k != "currency" && k != "prices" {
            guard let price = (v as? NSNumber)?.doubleValue else { continue }
            if let p = parseKey(k, price: price) { t.prices.append(p) }
        }
        return t
    }
}

public struct CostLine: Hashable {
    public var line: TakeoffLine
    public var measure: String
    public var quantity: Double
    public var unitPrice: Double
    public var total: Double { quantity * unitPrice }
}

public struct CostEstimate {
    public var currency: String
    public var lines: [CostLine]
    /// Takeoff lines that no rate applies to.
    public var unpriced: [TakeoffLine]
    public var total: Double { lines.reduce(0) { $0 + $1.total } }

    public static func compute(_ takeoff: Takeoff, table: CostTable) -> CostEstimate {
        var out: [CostLine] = []
        var unpriced: [TakeoffLine] = []
        for l in takeoff.lines {
            var byMeasure: [String: UnitPrice] = [:]
            for p in table.prices where p.category == l.category.lowercased() {
                if let k = p.key {
                    guard k.caseInsensitiveCompare(l.key) == .orderedSame || k.caseInsensitiveCompare(l.material) == .orderedSame else { continue }
                    byMeasure[p.measure] = p        // specific rate wins
                } else if byMeasure[p.measure] == nil || byMeasure[p.measure]!.key == nil {
                    byMeasure[p.measure] = p
                }
            }
            if byMeasure.isEmpty { unpriced.append(l); continue }
            for m in ["count", "length", "area", "volume"] { if let p = byMeasure[m] { out.append(CostLine(line: l, measure: m, quantity: l.quantity(m), unitPrice: p.price)) } }
        }
        return CostEstimate(currency: table.currency, lines: out, unpriced: unpriced)
    }

    public var csv: String {
        var rows = [["category", "type", "material", "measure", "quantity", "unit_price", "total", "currency"]]
        for c in lines { rows.append([c.line.category, c.line.key, c.line.material, c.measure, fmt(c.quantity, 3), fmt(c.unitPrice, 2), fmt(c.total, 2), currency]) }
        rows.append(["TOTAL", "", "", "", "", "", fmt(total, 2), currency])
        return CSVText.make(rows)
    }
    public var report: String {
        var s = ""
        for c in lines { s += "\(c.line.category) \(c.line.key): \(fmt(c.quantity, 3)) \(c.measure) × \(fmt(c.unitPrice, 2)) = \(fmt(c.total, 2)) \(currency)\n" }
        s += "Total: \(fmt(total, 2)) \(currency)"
        if !unpriced.isEmpty { s += "\nNo rate for: " + unpriced.map { "\($0.category) \($0.key)" }.joined(separator: "; ") }
        return s
    }
}
