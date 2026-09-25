// Oanarina Archi Tool — GPL-3.0-or-later
// Issue tracker inside the document: issues with status, priority, assignee, due date, linked elements, a saved view
// and comments. Stored as JSON in the document variable ISSUES, so they travel with the .archi file.
import Foundation

public struct IssueComment: Codable, Hashable {
    public var author: String
    public var date: String
    public var text: String
}

public struct Issue: Codable, Hashable {
    public enum Status: String, Codable, CaseIterable { case open, inProgress, resolved, closed }
    public enum Priority: String, Codable, CaseIterable { case low, normal, high, critical }
    public var id: Int
    public var title: String
    public var description: String
    public var status: Status
    public var priority: Priority
    public var assignee: String
    public var author: String
    public var created: String
    public var modified: String
    public var due: String?
    public var elements: [EntityID]
    /// Saved view: centre and height of the plan window, level.
    public var viewCenter: Vec2?
    public var viewHeight: Double?
    public var level: Int?
    public var labels: [String]
    public var comments: [IssueComment]

    public init(id: Int, title: String, description: String = "", status: Status = .open, priority: Priority = .normal, assignee: String = "",
                author: String, created: String, elements: [EntityID] = [], labels: [String] = []) {
        self.id = id; self.title = title; self.description = description; self.status = status; self.priority = priority
        self.assignee = assignee; self.author = author; self.created = created; self.modified = created; self.due = nil
        self.elements = elements; self.labels = labels; self.comments = []
    }

    enum CodingKeys: String, CodingKey { case id, title, description, status, priority, assignee, author, created, modified, due, elements, viewCenter, viewHeight, level, labels, comments }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        status = (try? c.decodeIfPresent(Status.self, forKey: .status)) ?? .open
        priority = (try? c.decodeIfPresent(Priority.self, forKey: .priority)) ?? .normal
        assignee = try c.decodeIfPresent(String.self, forKey: .assignee) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        created = try c.decodeIfPresent(String.self, forKey: .created) ?? ""
        modified = try c.decodeIfPresent(String.self, forKey: .modified) ?? created
        due = try c.decodeIfPresent(String.self, forKey: .due)
        elements = try c.decodeIfPresent([EntityID].self, forKey: .elements) ?? []
        viewCenter = try c.decodeIfPresent(Vec2.self, forKey: .viewCenter)
        viewHeight = try c.decodeIfPresent(Double.self, forKey: .viewHeight)
        level = try c.decodeIfPresent(Int.self, forKey: .level)
        labels = try c.decodeIfPresent([String].self, forKey: .labels) ?? []
        comments = try c.decodeIfPresent([IssueComment].self, forKey: .comments) ?? []
    }

    public var isOpen: Bool { status == .open || status == .inProgress }
    public static func parseStatus(_ s: String) -> Status? {
        switch s.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "") {
        case "open", "new", "reopen", "reopened": return .open
        case "inprogress", "progress", "active", "doing", "assigned": return .inProgress
        case "resolved", "fixed", "done": return .resolved
        case "closed", "close", "wontfix": return .closed
        default: return nil
        }
    }
    public static func parsePriority(_ s: String) -> Priority? { Priority.allCases.first { $0.rawValue.hasPrefix(s.lowercased()) && !s.isEmpty } }
}

public enum IssueTracker {
    public static let variable = "ISSUES"

    public static func all(_ doc: ArchiDocument) -> [Issue] { (VarJSON.load(doc, variable, as: [Issue].self) ?? []).sorted { $0.id < $1.id } }
    static func store(_ issues: [Issue], _ doc: inout ArchiDocument) { VarJSON.save(issues.sorted { $0.id < $1.id }, &doc, variable, empty: issues.isEmpty) }

    public static func issue(_ doc: ArchiDocument, _ id: Int) -> Issue? { all(doc).first { $0.id == id } }

    /// Adds an issue; the saved view frames its elements (or `view` when given). Returns its number.
    @discardableResult
    public static func add(_ doc: inout ArchiDocument, title: String, description: String = "", priority: Issue.Priority = .normal, assignee: String = "",
                           elements: [EntityID] = [], labels: [String] = [], due: String? = nil, author: String? = nil, date: String? = nil,
                           view: (center: Vec2, height: Double)? = nil) -> Int {
        var list = all(doc)
        let id = (list.map(\.id).max() ?? 0) + 1
        var i = Issue(id: id, title: title, description: description, priority: priority, assignee: assignee, author: author ?? Markups.author(doc),
                      created: date ?? Markups.now(), elements: elements.filter { doc.contains($0) }, labels: labels)
        i.due = due
        if let v = view { i.viewCenter = v.center; i.viewHeight = v.height }
        else if let b = bounds(doc, i.elements), !b.isEmpty { i.viewCenter = b.center; i.viewHeight = max(b.height, b.width / 1.6) * 1.4 + 1 }
        i.level = i.elements.compactMap { doc.element($0)?.level }.first
        list.append(i)
        store(list, &doc)
        return id
    }

    /// Applies `change` to issue `id` and stamps the modification date. False when there is no such issue.
    @discardableResult
    public static func update(_ doc: inout ArchiDocument, _ id: Int, date: String? = nil, _ change: (inout Issue) -> Void) -> Bool {
        var list = all(doc)
        guard let k = list.firstIndex(where: { $0.id == id }) else { return false }
        change(&list[k])
        list[k].modified = date ?? Markups.now()
        store(list, &doc)
        return true
    }

    @discardableResult
    public static func comment(_ doc: inout ArchiDocument, _ id: Int, text: String, author: String? = nil, date: String? = nil) -> Bool {
        let who = author ?? Markups.author(doc), when = date ?? Markups.now()
        return update(&doc, id, date: when) { $0.comments.append(IssueComment(author: who, date: when, text: text)) }
    }

    @discardableResult
    public static func remove(_ doc: inout ArchiDocument, _ id: Int) -> Bool {
        var list = all(doc)
        guard let k = list.firstIndex(where: { $0.id == id }) else { return false }
        list.remove(at: k)
        store(list, &doc)
        return true
    }

    /// Bounds of the linked objects (for zooming to an issue).
    public static func bounds(_ doc: ArchiDocument, _ ids: [EntityID]) -> BBox2? {
        var b = BBox2.empty
        for id in ids {
            if let e = doc.entity(id) { b.add(GeometryOps.bounds(e.geometry, doc: doc)) }
            else if let el = doc.element(id) { b.add(PlanRepresentation.bounds(el, doc: doc)) }
        }
        return b.isEmpty ? nil : b
    }

    /// Issues filtered by status / assignee / label (nil = any).
    public static func filter(_ doc: ArchiDocument, status: Issue.Status? = nil, openOnly: Bool = false, assignee: String? = nil, label: String? = nil) -> [Issue] {
        all(doc).filter { i in
            (status == nil || i.status == status) && (!openOnly || i.isOpen) &&
            (assignee == nil || i.assignee.caseInsensitiveCompare(assignee!) == .orderedSame) &&
            (label == nil || i.labels.contains { $0.caseInsensitiveCompare(label!) == .orderedSame })
        }
    }

    /// Issues linked to objects that no longer exist lose those links (after deletions).
    public static func prune(_ doc: inout ArchiDocument) -> Int {
        var list = all(doc)
        var n = 0
        for k in list.indices {
            let kept = list[k].elements.filter { doc.contains($0) }
            n += list[k].elements.count - kept.count
            list[k].elements = kept
        }
        if n > 0 { store(list, &doc) }
        return n
    }

    public static func table(_ issues: [Issue]) -> [[String]] {
        [["id", "title", "status", "priority", "assignee", "author", "created", "modified", "due", "elements", "labels", "comments", "description"]] + issues.map {
            ["\($0.id)", $0.title, $0.status.rawValue, $0.priority.rawValue, $0.assignee, $0.author, $0.created, $0.modified, $0.due ?? "",
             $0.elements.map(String.init).joined(separator: " "), $0.labels.joined(separator: " "), "\($0.comments.count)", $0.description]
        }
    }
    public static func csv(_ doc: ArchiDocument) -> String { CSVText.make(table(all(doc))) }

    /// One-line summary per issue.
    public static func line(_ i: Issue) -> String {
        "#\(i.id) [\(i.status.rawValue)] \(i.priority == .normal ? "" : i.priority.rawValue.uppercased() + " ")\(i.title)" +
        (i.assignee.isEmpty ? "" : " → \(i.assignee)") + (i.due.map { " (due \($0))" } ?? "") +
        (i.elements.isEmpty ? "" : " — " + i.elements.map { "#\($0)" }.joined(separator: ",")) + (i.comments.isEmpty ? "" : " — \(i.comments.count) comments")
    }
}
