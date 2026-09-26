// Oanarina Archi Tool — GPL-3.0-or-later
// Command registration for the round 11 modelling and BIM additions.
import Foundation

enum Round11Commands {
    static var all: [CommandDef] { SubObjectCommands.all + SurfaceBlendCommands.all + ComponentDatumCommands.all + Round11BIMCommands.all + AdaptiveBSDDCommands.all + CornerWindowCommands.all + RoofJoinCommands.all + MechanismCommands.all + ScriptedComponentCommands.all + SketchPlaneCommands.all }
}
