// Oanarina Archi Tool — GPL-3.0-or-later
import Foundation

/// View templates applied to views: VIEWTEMPLATE names the template of the current model view; drawing views
/// (VIEWDRAW specs) may carry their own ("south|template=Presentation Elevation").
public enum ViewTemplates {
    public static let variable = "VIEWTEMPLATE"

    /// The document with the current view template's settings applied (unchanged when none is set).
    public static func applied(_ doc: ArchiDocument, template name: String? = nil) -> ArchiDocument {
        guard let t = doc.viewTemplate(name ?? doc.variable(variable)) else { return doc }
        return t.apply(to: doc)
    }

    /// Adds or replaces a template.
    public static func save(_ t: ViewTemplate, doc: inout ArchiDocument) {
        if let i = doc.viewTemplates.firstIndex(where: { $0.name.caseInsensitiveCompare(t.name) == .orderedSame }) { doc.viewTemplates[i] = t }
        else { doc.viewTemplates.append(t) }
    }

    /// Splits a view spec "south|template=Name" into the spec and the template name.
    public static func split(_ spec: String) -> (spec: String, template: String?) {
        let parts = spec.components(separatedBy: "|template=")
        return (parts[0], parts.count > 1 ? parts[1] : nil)
    }
}
