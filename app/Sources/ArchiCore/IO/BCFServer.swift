// Oanarina Archi Tool — GPL-3.0-or-later
// BCF API client (COL-010): connects to OpenCDE / buildingSMART BCF API servers (BCF API 2.1 and 3.0 JSON over
// HTTPS with a bearer token): lists projects, pulls topics with their comments, viewpoints (camera, selection by IFC
// GlobalId) into review markups, and pushes local markups back (new topics, status/title changes, new comments and
// viewpoints). Network access happens only when the user runs BCFSERVER; the transport is replaceable (tests).
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class BCFAPIClient {
    public typealias Transport = (URLRequest) throws -> (status: Int, body: Data)
    public struct APIError: Error, LocalizedError { public let message: String; public var errorDescription: String? { "BCF server: " + message } }

    public let baseURL: URL
    public var version: String
    public var token: String?
    let transport: Transport

    public init(baseURL: URL, version: String = "3.0", token: String? = nil, transport: Transport? = nil) {
        self.baseURL = baseURL; self.version = version; self.token = token
        self.transport = transport ?? BCFAPIClient.urlSession
    }

    /// Synchronous URLSession request (30 s timeout).
    public static func urlSession(_ r: URLRequest) throws -> (status: Int, body: Data) {
        var result: (Int, Data)?, failure: Error?
        let sem = DispatchSemaphore(value: 0)
        var req = r; req.timeoutInterval = 30
        URLSession.shared.dataTask(with: req) { d, resp, e in
            if let e { failure = e } else { result = ((resp as? HTTPURLResponse)?.statusCode ?? 0, d ?? Data()) }
            sem.signal()
        }.resume()
        sem.wait()
        if let failure { throw APIError(message: failure.localizedDescription) }
        return result ?? (0, Data())
    }

    func request(_ method: String, _ path: String, body: Any? = nil) throws -> Any? {
        let url = URL(string: path.hasPrefix("/") ? String(path.dropFirst()) : path, relativeTo: baseURL.hasDirectoryPath ? baseURL : baseURL.appendingPathComponent(""))!.absoluteURL
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        let (status, data) = try transport(r)
        guard (200..<300).contains(status) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? String(decoding: data.prefix(200), as: UTF8.self)
            throw APIError(message: "\(method) \(url.path) → HTTP \(status)\(msg.isEmpty ? "" : ": " + msg)")
        }
        return data.isEmpty ? nil : try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    var root: String { "bcf/\(version)" }

    /// BCF API versions the server offers (GET /bcf/versions).
    public func versions() throws -> [String] {
        let v = try request("GET", "bcf/versions") as? [String: Any]
        return ((v?["versions"] as? [[String: Any]]) ?? []).compactMap { $0["version_id"] as? String }
    }

    /// Picks the highest of 3.0 / 2.1 the server supports.
    public func negotiate() throws {
        let v = try versions()
        if v.contains("3.0") { version = "3.0" } else if v.contains("2.1") { version = "2.1" }
        else { throw APIError(message: "no supported BCF API version (server offers \(v.joined(separator: ", ")))") }
    }

    public func projects() throws -> [(id: String, name: String)] {
        ((try request("GET", "\(root)/projects") as? [[String: Any]]) ?? []).compactMap { p in
            (p["project_id"] as? String).map { ($0, p["name"] as? String ?? "") }
        }
    }

    // MARK: JSON mapping

    static func vec(_ v: Any?) -> Vec3? {
        guard let d = v as? [String: Any], let x = (d["x"] as? NSNumber)?.doubleValue, let y = (d["y"] as? NSNumber)?.doubleValue, let z = (d["z"] as? NSNumber)?.doubleValue else { return nil }
        return Vec3(x, y, z)
    }
    static func json(_ v: Vec3) -> [String: Any] { ["x": v.x, "y": v.y, "z": v.z] }

    static func viewpoint(_ d: [String: Any]) -> BCFViewpoint? {
        let guid = d["guid"] as? String ?? ""
        var sel: [String] = []
        if let c = d["components"] as? [String: Any], let s = c["selection"] as? [[String: Any]] { sel = s.compactMap { $0["ifc_guid"] as? String } }
        if let o = d["orthogonal_camera"] as? [String: Any], let p = vec(o["camera_view_point"]), let dir = vec(o["camera_direction"]) {
            return BCFViewpoint(guid: guid, position: p, direction: dir, up: vec(o["camera_up_vector"]) ?? Vec3(0, 0, 1), fieldOfView: 60,
                                viewToWorldScale: (o["view_to_world_scale"] as? NSNumber)?.doubleValue ?? 10, orthogonal: true, selection: sel)
        }
        if let o = d["perspective_camera"] as? [String: Any], let p = vec(o["camera_view_point"]), let dir = vec(o["camera_direction"]) {
            return BCFViewpoint(guid: guid, position: p, direction: dir, up: vec(o["camera_up_vector"]) ?? Vec3(0, 0, 1),
                                fieldOfView: (o["field_of_view"] as? NSNumber)?.doubleValue ?? 60, viewToWorldScale: 10, orthogonal: false, selection: sel)
        }
        return sel.isEmpty ? nil : BCFViewpoint(guid: guid, position: .zero, direction: Vec3(0, 0, -1), up: Vec3(0, 1, 0), fieldOfView: 60, viewToWorldScale: 10, orthogonal: true, selection: sel)
    }

    static func viewpointJSON(_ v: BCFViewpoint) -> [String: Any] {
        var d: [String: Any] = ["guid": v.guid]
        let cam: [String: Any] = ["camera_view_point": json(v.position), "camera_direction": json(v.direction), "camera_up_vector": json(v.up)]
        if v.orthogonal { d["orthogonal_camera"] = cam.merging(["view_to_world_scale": v.viewToWorldScale, "aspect_ratio": 1.6]) { a, _ in a } }
        else { d["perspective_camera"] = cam.merging(["field_of_view": v.fieldOfView, "aspect_ratio": 1.6]) { a, _ in a } }
        if !v.selection.isEmpty { d["components"] = ["selection": v.selection.map { ["ifc_guid": $0] }] }
        return d
    }

    static func topicJSON(_ t: BCFTopic) -> [String: Any] {
        ["title": t.title, "topic_type": t.type, "topic_status": t.status, "description": t.description]
    }

    // MARK: Pull / push

    /// Topics of a project with comments and the first viewpoint (selection fetched when not embedded).
    public func topics(project: String) throws -> [BCFTopic] {
        let list = (try request("GET", "\(root)/projects/\(project)/topics") as? [[String: Any]]) ?? []
        var out: [BCFTopic] = []
        for t in list {
            guard let guid = t["guid"] as? String else { continue }
            let base = "\(root)/projects/\(project)/topics/\(guid)"
            let comments = ((try request("GET", "\(base)/comments") as? [[String: Any]]) ?? []).map {
                BCFComment(guid: $0["guid"] as? String ?? "", author: $0["author"] as? String ?? "", date: $0["date"] as? String ?? "", text: $0["comment"] as? String ?? "")
            }
            var vp: BCFViewpoint?
            if let v = ((try request("GET", "\(base)/viewpoints") as? [[String: Any]]) ?? []).first {
                vp = Self.viewpoint(v)
                if var p = vp, p.selection.isEmpty, let g = v["guid"] as? String {
                    let path = version == "2.1" ? "\(base)/viewpoints/\(g)/components" : "\(base)/viewpoints/\(g)/selection"
                    if let s = (try? request("GET", path)) as? [String: Any] {
                        let arr = (s["selection"] as? [[String: Any]]) ?? ((s["components"] as? [String: Any])?["selection"] as? [[String: Any]]) ?? []
                        p.selection = arr.compactMap { $0["ifc_guid"] as? String }
                        vp = p
                    }
                }
            }
            out.append(BCFTopic(guid: guid, title: t["title"] as? String ?? "", status: t["topic_status"] as? String ?? "Open", type: t["topic_type"] as? String ?? "Issue",
                                author: t["creation_author"] as? String ?? "", date: t["creation_date"] as? String ?? "",
                                description: t["description"] as? String ?? "", comments: comments, viewpoint: vp))
        }
        return out
    }

    public struct PushResult: Hashable { public var created: Int = 0, updated: Int = 0, comments: Int = 0, viewpoints: Int = 0
        /// Local topic GUID → server GUID for topics the server created.
        public var assigned: [String: String] = [:] }

    /// Pushes topics: unknown ones are created, known ones updated (title/status/type/description); comments and a
    /// viewpoint missing on the server are added.
    public func push(_ topics: [BCFTopic], project: String, serverGuid: (BCFTopic) -> String? = { _ in nil }) throws -> PushResult {
        var r = PushResult()
        let remote = Set(((try request("GET", "\(root)/projects/\(project)/topics") as? [[String: Any]]) ?? []).compactMap { $0["guid"] as? String })
        for t in topics {
            var guid = serverGuid(t) ?? t.guid
            let base = "\(root)/projects/\(project)/topics"
            if remote.contains(guid) {
                _ = try request("PUT", "\(base)/\(guid)", body: Self.topicJSON(t)); r.updated += 1
            } else {
                var body = Self.topicJSON(t); body["guid"] = t.guid
                let created = try request("POST", base, body: body) as? [String: Any]
                guid = created?["guid"] as? String ?? t.guid
                if guid != t.guid { r.assigned[t.guid] = guid }
                r.created += 1
            }
            let have = Set(((try request("GET", "\(base)/\(guid)/comments") as? [[String: Any]]) ?? []).compactMap { $0["guid"] as? String })
            let haveText = Set(((try request("GET", "\(base)/\(guid)/comments") as? [[String: Any]]) ?? []).compactMap { $0["comment"] as? String })
            var vpGuid: String?
            let vps = (try request("GET", "\(base)/\(guid)/viewpoints") as? [[String: Any]]) ?? []
            if let vp = t.viewpoint {
                if vps.isEmpty {
                    let res = try request("POST", "\(base)/\(guid)/viewpoints", body: Self.viewpointJSON(vp)) as? [String: Any]
                    vpGuid = res?["guid"] as? String ?? vp.guid; r.viewpoints += 1
                } else { vpGuid = vps.first?["guid"] as? String }
            }
            for c in t.comments where !have.contains(c.guid) && !haveText.contains(c.text) {
                var body: [String: Any] = ["comment": c.text, "guid": c.guid]
                if let v = vpGuid { body["viewpoint_guid"] = v }
                _ = try request("POST", "\(base)/\(guid)/comments", body: body); r.comments += 1
            }
        }
        return r
    }
}

public enum BCFServerCommands {
    @MainActor static var tokens: [String: String] = [:]

    static var command: CommandDef {
        CommandDef("BCFSERVER", aliases: ["BCFAPI", "OPENCDE", "BCFCONNECT"], category: "Collaborate",
                   summary: "Connects to a BCF API (OpenCDE) server: Connect (URL, bearer token), Projects, Pull (topics → markups with comments, cameras and selections) and Push (markups → topics, comments and viewpoints). The server URL and project are saved in the drawing (BCFSERVER, BCFPROJECT); the token is kept only for the session.") { ed in
            let k = try await ed.getKeyword("Option [Connect/Projects/Pull/Push]", ["Connect", "Projects", "Pull", "Push"], defaultValue: ed.doc.variable("BCFSERVER") == nil ? "Connect" : "Pull") ?? "Pull"
            @MainActor func client() throws -> BCFAPIClient {
                guard let s = ed.doc.variable("BCFSERVER"), let u = URL(string: s) else { throw CommandError.invalid("Not connected: BCFSERVER Connect first.") }
                return BCFAPIClient(baseURL: u, version: ed.doc.variable("BCFAPIVERSION") ?? "3.0", token: tokens[s] ?? ProcessInfo.processInfo.environment["BCF_TOKEN"], transport: BCFServerCommands.transport)
            }
            func fail(_ e: Error) -> CommandError { CommandError.invalid((e as? LocalizedError)?.errorDescription ?? "\(e)") }
            switch k {
            case "Connect":
                guard let s = try await ed.getWord("Server URL (https://…)"), let u = URL(string: s), u.scheme?.hasPrefix("http") == true else { throw CommandError.invalid("Enter the server's base URL.") }
                let tok = try await ed.getWord("Access token <none>")
                let c = BCFAPIClient(baseURL: u, token: tok?.isEmpty == false ? tok : nil, transport: BCFServerCommands.transport)
                do { try c.negotiate() } catch { throw fail(error) }
                ed.doc.setVariable("BCFSERVER", s); ed.doc.setVariable("BCFAPIVERSION", c.version)
                if let t = tok, !t.isEmpty { tokens[s] = t }
                let ps: [(id: String, name: String)]
                do { ps = try c.projects() } catch { throw fail(error) }
                ed.print("Connected (BCF API \(c.version)); \(ps.count) project(s).")
                for p in ps { ed.print("  \(p.id)  \(p.name)") }
                if ps.count == 1 { ed.doc.setVariable("BCFPROJECT", ps[0].id) }
            case "Projects":
                let ps: [(id: String, name: String)]
                do { ps = try client().projects() } catch { throw fail(error) }
                for p in ps { ed.print("  \(p.id)  \(p.name)") }
                if let p = try await ed.getWord("Project id <\(ed.doc.variable("BCFPROJECT") ?? "")>"), !p.isEmpty { ed.doc.setVariable("BCFPROJECT", p) }
            case "Pull":
                guard let p = ed.doc.variable("BCFPROJECT") else { throw CommandError.invalid("Choose a project: BCFSERVER Projects.") }
                let ts: [BCFTopic]
                do { ts = try client().topics(project: p) } catch { throw fail(error) }
                var d = ed.doc
                let ids = BCF.importTopics(ts, into: &d)
                ed.doc = d
                ed.print("Pulled \(ids.count) topic(s) as markups (MARKUP List).")
            default:
                guard let p = ed.doc.variable("BCFPROJECT") else { throw CommandError.invalid("Choose a project: BCFSERVER Projects.") }
                let d0 = ed.doc
                let ts = BCF.topics(d0)
                func serverGuid(_ t: BCFTopic) -> String? {
                    d0.entities.first { e in e.props["markup"].map { BCF.uuid($0) == t.guid } ?? false && e.props["bcfGuid"] != nil }?.props["bcfGuid"]
                }
                let r: BCFAPIClient.PushResult
                do { r = try client().push(ts, project: p, serverGuid: serverGuid) } catch { throw fail(error) }
                var d = ed.doc
                for (local, server) in r.assigned {
                    for i in d.entities.indices where d.entities[i].props["markup"].map({ BCF.uuid($0) == local }) ?? false { d.entities[i].props["bcfGuid"] = server }
                }
                ed.doc = d
                ed.print("Pushed: \(r.created) new, \(r.updated) updated topic(s), \(r.comments) comment(s), \(r.viewpoints) viewpoint(s).")
            }
        }
    }

    /// Replaceable transport (tests install a mock server).
    nonisolated(unsafe) public static var transport: BCFAPIClient.Transport? = nil
}
