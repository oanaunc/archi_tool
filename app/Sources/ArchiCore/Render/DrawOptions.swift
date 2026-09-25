// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// Options controlling how a document is turned into 2D draw entries.
public struct DrawOptions: Hashable {
    /// Only BIM elements on this level are drawn (nil = all levels).
    public var level: Int?
    public var showElements = true
    public var showAnnotations = true
    /// Additional linetype scale (multiplied with the LTSCALE variable).
    public var linetypeScale = 1.0
    /// Paper output: ACI 7 / white prints black.
    public var forPaper = false
    /// Draw material cut patterns inside cut walls/columns.
    public var cutHatches = true
    /// Show ceilings (slabs with props kind = ceiling); false in floor plans unless the CEILINGS variable is 1.
    public var showCeilings: Bool? = nil
    public init(level: Int? = nil) { self.level = level }
}
