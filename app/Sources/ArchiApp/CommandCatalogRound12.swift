// Oanarina Archi Tool — GPL-3.0-or-later
import SwiftUI
import ArchiCore

/// Entries for commands the core adds after round 11 (kept separate so late additions have one obvious home).
extension CommandCatalog {
    private static func c12(_ title: String, _ symbol: String, _ names: String...) -> CmdItem { CmdItem(title: title, symbol: symbol, names: names) }
    static let lateRound11: [CmdItem] = [
        c12("Adaptive Component", "point.3.connected.trianglepath.dotted", "ADAPTIVE"), c12("bSDD Lookup", "books.vertical", "BSDD"),
        c12("Corner Window", "square.split.bottomrightquarter", "CORNERWINDOW"), c12("Roof Join", "house", "ROOFJOIN"), c12("Mechanism Simulation", "gearshape.2", "MECHANISM"), c12("Scripted Component", "curlybraces.square", "SCRIPTCOMPONENT"),
        c12("Sketch Environment", "pencil.and.ruler", "SKETCHPAD"), c12("Sketch Plane", "square.and.pencil", "SKETCHPLANE"),
    ]
    static var coverageMenus8: [(String, [CmdItem])] { lateRound11.isEmpty ? [] : [("Adaptive, Corners & Roofs", lateRound11)] }
}
