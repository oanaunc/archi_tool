// Temporary placeholders — replaced by the render module.
import Foundation

public enum PlanRepresentation {
    public static func entries(_ el: BIMElement, doc: ArchiDocument) -> [DrawItem] { [] }
    public static func bounds(_ el: BIMElement, doc: ArchiDocument) -> BBox2 { .empty }
    public static func distance(from p: Vec2, to el: BIMElement, doc: ArchiDocument) -> Double { .infinity }
}

public enum DimensionRenderer {
    public struct Primitives { public var lines: [[Vec2]] = []; public var arrows: [[Vec2]] = []; public var text: TextGeom? }
    public static func primitives(_ d: DimensionGeom, style: DimStyle) -> Primitives { Primitives(lines: [d.points]) }
}
