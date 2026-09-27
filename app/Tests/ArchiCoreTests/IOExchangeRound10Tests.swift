// Oanarina Archi Tool — GPL-3.0-or-later
// DXF versions (IO-009) and further exchange formats added in round 10.
import XCTest
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import ArchiCore

final class IOExchangeRound10Tests: XCTestCase {
    func tmpDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("archi-r10-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func draftDoc() -> ArchiDocument {
        var d = ArchiDocument()
        d.add(Entity(layer: "0", geometry: .line(LineGeom(Vec2(0, 0), Vec2(100, 0)))))
        d.add(Entity(layer: "0", geometry: .circle(CircleGeom(Vec2(50, 50), 20))))
        d.add(Entity(layer: "0", geometry: .text(TextGeom(position: Vec2(0, 80), height: 5, content: "Ștefan café 😀"))))
        return d
    }

    func testDXFVersionsRoundTrip() throws {
        let d = draftDoc()
        XCTAssertEqual(DXFVersion.parse("2018"), .r2018)
        XCTAssertEqual(DXFVersion.parse("AC1027"), .r2013)
        XCTAssertEqual(DXFVersion.parse("dxf2004"), .r2004)
        XCTAssertEqual(DXFVersion.parse("R12"), .r12)
        for v in DXFVersion.allCases {
            let text = DXFWriter.write(d, version: v)
            XCTAssertTrue(text.contains("$ACADVER\n  1\n" + v.acadVer), v.rawValue)
            if !v.isUTF8 && v != .r12 { XCTAssertTrue(text.contains("\\U+0218"), v.rawValue) }
            if v.isUTF8 { XCTAssertTrue(text.contains("Ștefan café 😀"), v.rawValue); XCTAssertFalse(text.contains("\\U+0218"), v.rawValue) }
            let back = try DXFReader.read(text)
            XCTAssertEqual(back.entities.count, 3, v.rawValue)
            XCTAssertEqual(back.variable("DXFVERSION"), v.acadVer)
            let t = back.entities.compactMap { e -> String? in if case .text(let t) = e.geometry { return t.content }; return nil }.first
            if v != .r12 { XCTAssertEqual(t, "Ștefan café 😀", v.rawValue) }
        }
        // Export by format name and the command.
        let dir = try tmpDir()
        XCTAssertTrue(try FileImport.export(d, to: dir.appendingPathComponent("a.dxf"), format: "dxf2018"))
        XCTAssertTrue(try String(contentsOf: dir.appendingPathComponent("a.dxf"), encoding: .utf8).contains("AC1032"))
    }

    @MainActor func testDXFOutVersionCommand() async throws {
        let dir = try tmpDir()
        let ed = Editor()
        ed.doc = draftDoc()
        let p = dir.appendingPathComponent("b.dxf").path
        await ed.run("DXFOUTVERSION R2010 \(p)")
        let s = try String(contentsOfFile: p, encoding: .utf8)
        XCTAssertTrue(s.contains("AC1024"))
        XCTAssertEqual(try DXFReader.read(s).entities.count, 3)
    }

    func testIFCXMLRoundTrip() throws {
        let d = IOIFCSchemaTests().model()
        let step = IFCExporter.export(doc: d, meshes: MeshBuilder.build(doc: d))
        let xml = try IFCXML.fromSTEP(step)
        XCTAssertTrue(xml.hasPrefix("<?xml"))
        XCTAssertTrue(xml.contains("<ifcXML xmlns=\"http://www.buildingsmart-tech.org/ifcXML/IFC4/Add2\""))
        XCTAssertTrue(xml.contains("<IfcWall id=\"i"))
        XCTAssertTrue(xml.contains("xsi:nil=\"true\""))
        XCTAssertTrue(xml.contains("-wrapper>"), "typed property values")
        XCTAssertTrue(IFCXML.sniff(Data(xml.utf8)))
        // Well-formed XML.
        XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse())
        // Every instance survives with the same class, GlobalIds and attribute values.
        let back = try IFCXML.toSTEP(Data(xml.utf8))
        let a = try STEPParser.parse(step), b = try STEPParser.parse(back)
        XCTAssertEqual(a.entities.count, b.entities.count)
        for (id, e) in a.entities {
            let f = try XCTUnwrap(b.entities[id], "#\(id)")
            XCTAssertEqual(f.type, e.type, "#\(id)")
            XCTAssertEqual(f.args.count, e.args.count, "#\(id) \(e.type)")
            for (x, y) in zip(e.args, f.args) {
                switch (x, y) {
                case (.real(let p), .real(let q)): XCTAssertEqual(p, q, accuracy: abs(p) * 1e-9 + 1e-12, "#\(id)")
                case (.int(let p), .real(let q)), (.real(let q), .int(let p)): XCTAssertEqual(Double(p), q, "#\(id)")
                default: XCTAssertEqual(x, y, "#\(id) \(e.type)")
                }
            }
        }
        // The IFC importer reads the converted file like the original.
        let r1 = try IFCImporter.importFile(step), r2 = try IFCImporter.importFile(back)
        XCTAssertEqual(r1.doc.elements.count, r2.doc.elements.count)
        XCTAssertEqual(r1.doc.elements.map { $0.props["ifcGuid"] ?? "" }.sorted(), r2.doc.elements.map { $0.props["ifcGuid"] ?? "" }.sorted())
        // Files: .ifcXML export/import, IfcZIP holding ifcXML.
        let dir = try tmpDir()
        let u = dir.appendingPathComponent("m.ifcXML")
        XCTAssertTrue(try FileImport.export(d, to: u, format: "ifcxml"))
        XCTAssertEqual(FileImport.format(for: u), "ifcxml")
        var doc = ArchiDocument()
        let (res, _) = try FileImport.importFile(u, into: &doc)
        XCTAssertEqual(res.elementIDs.count, r1.doc.elements.count)
        let z = IFCZip.writeXML(xml)
        XCTAssertEqual(try IFCZip.read(z), back)
        XCTAssertThrowsError(try IFCXML.toSTEP(Data("<svg/>".utf8)))
    }

    func testLAZThroughAnInstalledDecompressor() throws {
        let dir = try tmpDir()
        // A LAZ file (the compressed flag set on a LAS) and a stand-in "laszip" that restores the LAS.
        let las = LASReader.write([CloudPoint(Vec3(1, 2, 3), color: (255, 0, 0), intensity: 5), CloudPoint(Vec3(4, 5, 6), color: (0, 255, 0), intensity: 7)])
        var bytes = [UInt8](las); bytes[104] |= 0x80
        let laz = dir.appendingPathComponent("scan.laz")
        try Data(bytes).write(to: laz)
        let tool = dir.appendingPathComponent("laszip")
        try "#!/bin/sh\n# laszip -i IN -o OUT\ncp \"$2\" \"$4\"\nprintf '\\002' | dd of=\"$4\" bs=1 seek=104 conv=notrunc 2>/dev/null\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let t = try XCTUnwrap(LAZConverter.tool(at: tool.path))
        XCTAssertEqual(t.kind, .laszip)
        XCTAssertEqual(LAZConverter.arguments(t, input: laz, output: URL(fileURLWithPath: "/o.las")), ["-i", laz.path, "-o", "/o.las"])
        XCTAssertEqual(LAZConverter.arguments(LAZConverter.Tool(kind: .pdal, path: "/x/pdal"), input: laz, output: URL(fileURLWithPath: "/o.las")), ["translate", laz.path, "/o.las"])
        let data = try LAZConverter.decompress(laz, converter: tool.path)
        XCTAssertEqual(try LASReader.read(data).points.count, 2)
        var ref = ArchiDocument(); ref.setVariable("LAZCONVERTER", tool.path)
        let (doc, summary) = try FileImport.load(laz, reference: ref)
        XCTAssertTrue(summary.contains("2 of 2 LAZ points"), summary)
        XCTAssertEqual(doc.entities.count, 2)
        // Without a decompressor the error explains how to get one.
        XCTAssertThrowsError(try LAZConverter.decompress(laz, converter: dir.appendingPathComponent("missing").path, timeout: 5)) { e in
            if LAZConverter.find() == nil { XCTAssertTrue((e as? LocalizedError)?.errorDescription?.contains("LASzip") ?? false) }
        }
    }

    func testPresentationSlides() throws {
        var d = ArchiDocument()
        d.info.name = "House"
        d.addElement(.wall(WallGeom(start: Vec2(0, 0), end: Vec2(6000, 0), thickness: 300, height: 3000)))
        d.addElement(.wall(WallGeom(start: Vec2(6000, 0), end: Vec2(6000, 4000), thickness: 300, height: 3000)))
        d.layouts = [Layout(name: "A-101 Plan", paper: PaperSize.standard[1], viewports: [Viewport(origin: Vec2(20, 20), size: Vec2(300, 200), viewCenter: Vec2(3000, 2000), scale: 50, title: "Ground floor")],
                            titleBlock: ["Drawn": "OU", "notes": "Start with the plan."]),
                     Layout(name: "Empty")]
        d.namedViews = [NamedView(name: "Entrance", center: Vec2(0, 0), height: 3000)]
        let slides = Presentation.slides(d)
        XCTAssertEqual(slides.map(\.title), ["A-101 Plan", "Entrance"])
        XCTAssertEqual(slides[0].notes, "Start with the plan.")
        for s in slides { XCTAssertTrue(XMLParser(data: Data(s.svg.utf8)).parse(), s.title) }
        XCTAssertTrue(slides[0].svg.contains("viewBox=\"0 0 420 297\""))
        XCTAssertTrue(slides[0].svg.contains("Ground floor — 1:50"))
        XCTAssertTrue(slides[0].svg.contains("<path") || slides[0].svg.contains("<polyline") || slides[0].svg.contains("<polygon"), "walls drawn in the viewport")
        let html = Presentation.html(slides, title: "House")
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertEqual(html.components(separatedBy: "<section class=\"slide").count - 1, 2)
        XCTAssertTrue(html.contains("requestFullscreen"))
        // No sheets or views: one slide of the whole plan.
        var bare = d; bare.layouts = []; bare.namedViews = []
        XCTAssertEqual(Presentation.slides(bare).count, 1)
    }

    func testEd25519AndSHA512Vectors() {
        func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
        func bytes(_ h: String) -> [UInt8] { stride(from: 0, to: h.count, by: 2).map { UInt8(h.dropFirst($0).prefix(2), radix: 16)! } }
        XCTAssertEqual(hex(SHA512.hash(Array("abc".utf8))), "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
        XCTAssertEqual(hex(SHA512.hash([])), "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e")
        // RFC 8032 section 7.1, tests 1 and 2.
        let sk1 = bytes("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
        XCTAssertEqual(hex(Ed25519.publicKey(seed: sk1)), "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
        let s1 = Ed25519.sign([], seed: sk1)
        XCTAssertEqual(hex(s1), "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
        XCTAssertTrue(Ed25519.verify([], signature: s1, publicKey: Ed25519.publicKey(seed: sk1)))
        let sk2 = bytes("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb")
        let s2 = Ed25519.sign([0x72], seed: sk2)
        XCTAssertEqual(hex(s2), "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00")
        XCTAssertTrue(Ed25519.verify([0x72], signature: s2, publicKey: Ed25519.publicKey(seed: sk2)))
        XCTAssertFalse(Ed25519.verify([0x73], signature: s2, publicKey: Ed25519.publicKey(seed: sk2)))
        var bad = s2; bad[10] ^= 1
        XCTAssertFalse(Ed25519.verify([0x72], signature: bad, publicKey: Ed25519.publicKey(seed: sk2)))
        XCTAssertFalse(Ed25519.verify([0x72], signature: s2, publicKey: Ed25519.publicKey(seed: sk1)))
    }

    func testFileSignatures() throws {
        let dir = try tmpDir()
        let key = FileSignature.newKey(signer: "Oana")
        let kurl = dir.appendingPathComponent("key.json")
        try FileSignature.saveKey(key, to: kurl)
        XCTAssertEqual(try FileSignature.loadKey(kurl), key)
        let f = dir.appendingPathComponent("A-101.pdf")
        try Data("%PDF-1.7 sheet".utf8).write(to: f)
        let r = try FileSignature.signFile(f, key: key)
        XCTAssertEqual(r.signer, "Oana")
        XCTAssertEqual(FileSignature.verifyFile(f).0, .valid(signer: "Oana", trusted: false))
        XCTAssertEqual(FileSignature.verifyFile(f, trusted: [key.publicKey]).0, .valid(signer: "Oana", trusted: true))
        try Data("%PDF-1.7 sheet, changed".utf8).write(to: f)
        XCTAssertEqual(FileSignature.verifyFile(f).0, .modified)
        // A forged record (signer renamed) no longer verifies.
        var forged = r; forged.signer = "Mallory"
        XCTAssertEqual(FileSignature.verify(Data("%PDF-1.7 sheet".utf8), record: forged), .invalid)
        XCTAssertEqual(FileSignature.verifyFile(dir.appendingPathComponent("none.pdf")).0, .missing)
    }

    func testMarkdownConversion() {
        let md = """
        # Title — *Guide*

        Intro with `code`, **bold**, *em*, a [link](SCRIPTING.md#js) and <https://example.org>.
        Second line of the paragraph.

        ## Lists & tables

        - one
        - two
          - nested **x**
        1. first
        2. second

        | Input | Meaning |
        | --- | ---: |
        | `@500,0` | relative \\| pipe |

        > quoted

        ```
        WALL 0,0 <6000>
        ```
        ---
        ## Lists & tables
        """
        let (html, heads) = Markdown.html(md, linkMap: DocSite.linkMap)
        XCTAssertEqual(heads.map(\.id), ["title--guide", "lists--tables", "lists--tables-1"])
        XCTAssertTrue(html.contains("<h1 id=\"title--guide\">Title — <em>Guide</em></h1>"), html)
        XCTAssertTrue(html.contains("<code>code</code>, <strong>bold</strong>, <em>em</em>, a <a href=\"scripting.html#js\">link</a> and <a href=\"https://example.org\">https://example.org</a>. Second line"), html)
        XCTAssertTrue(html.contains("<ul>\n<li>one</li>\n<li>two\n<ul>\n<li>nested <strong>x</strong></li>\n</ul>\n</li>\n</ul>"), html)
        XCTAssertTrue(html.contains("<ol>\n<li>first</li>\n<li>second</li>\n</ol>"), html)
        XCTAssertTrue(html.contains("<th style=\"text-align:right\">Meaning</th>"), html)
        XCTAssertTrue(html.contains("<td style=\"text-align:right\">relative | pipe</td>"), html)
        XCTAssertTrue(html.contains("<blockquote>\n<p>quoted</p>\n</blockquote>"), html)
        XCTAssertTrue(html.contains("<pre><code>WALL 0,0 &lt;6000&gt;</code></pre>"), html)
        XCTAssertTrue(html.contains("<hr>"))
        XCTAssertEqual(Markdown.slug("BIM: building elements and levels"), "bim-building-elements-and-levels")
        XCTAssertEqual(Markdown.slug("3D view and rendering"), "3d-view-and-rendering")
    }

    func testDocumentationSiteFromTheRepository() throws {
        let docs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs")
        guard FileManager.default.fileExists(atPath: docs.appendingPathComponent("USER-GUIDE.md").path) else { throw XCTSkip("docs folder not present") }
        let dir = try tmpDir()
        let files = try DocSite.build(source: docs, into: dir, apiReference: APIReference.markdown())
        XCTAssertTrue(files.contains("index.html") && files.contains("user-guide.html") && files.contains("reference.html"))
        // Every local link points to an existing page and anchor.
        var ids: [String: Set<String>] = [:]
        for f in files where f.hasSuffix(".html") {
            let text = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
            var set = Set<String>()
            var rest = text[...]
            while let r = rest.range(of: " id=\"") { let tail = rest[r.upperBound...]; if let e = tail.firstIndex(of: "\"") { set.insert(String(tail[..<e])) }; rest = tail }
            ids[f] = set
        }
        var broken: [String] = []
        for f in files where f.hasSuffix(".html") {
            let text = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
            var rest = text[...]
            while let r = rest.range(of: "href=\"") {
                let tail = rest[r.upperBound...]
                guard let e = tail.firstIndex(of: "\"") else { break }
                let href = String(tail[..<e]); rest = tail[e...]
                if href.contains("://") || href.hasPrefix("mailto:") || href.hasSuffix(".css") { continue }
                let parts = href.split(separator: "#", maxSplits: 1).map(String.init)
                let page = href.hasPrefix("#") ? f : parts[0]
                let anchor = href.hasPrefix("#") ? String(href.dropFirst()) : (parts.count > 1 ? parts[1] : nil)
                guard let known = ids[page] else { if page.hasSuffix(".html") { broken.append("\(f): \(href)") }; continue }
                if let a = anchor, !a.isEmpty, !known.contains(a) { broken.append("\(f): \(href)") }
            }
        }
        XCTAssertTrue(broken.isEmpty, broken.prefix(20).joined(separator: "\n"))
        let index = try String(contentsOf: dir.appendingPathComponent("search-index.js"), encoding: .utf8)
        XCTAssertTrue(index.contains("\"t\":\"WALL\""), "commands are searchable")
    }

    func testIFC43AlignmentImport() throws {
        // Geometry: a clothoid from a straight into R = 100 m over 50 m ends with direction 0.25 rad.
        let cl = AlignmentGeometry.sample(AlignmentGeometry.Horizontal(kind: "CLOTHOID", start: .zero, direction: 0, startRadius: 0, endRadius: 100_000, length: 50_000), step: 500)
        let e = cl.last!, p = cl[cl.count - 2]
        XCTAssertEqual(atan2(e.y - p.y, e.x - p.x), 0.25, accuracy: 0.005)
        XCTAssertEqual(e.x, 49_688.9, accuracy: 2)        // x = L − L⁵/40A⁴ + L⁹/3456A⁸ (A² = R L)
        XCTAssertEqual(e.y, 4_148.2, accuracy: 2)         // y = L³/6A² − L⁷/336A⁶ + L¹¹/42240A¹⁰
        let arcR = AlignmentGeometry.sample(AlignmentGeometry.Horizontal(kind: "CIRCULARARC", start: .zero, direction: 0, startRadius: -200, endRadius: -200, length: 100), step: 1)
        XCTAssertEqual(arcR.last!.x, 200 * sin(0.5), accuracy: 1e-6)
        XCTAssertEqual(arcR.last!.y, -(200 - 200 * cos(0.5)), accuracy: 1e-6, "negative radius turns right")
        let ifc = """
        ISO-10303-21;HEADER;FILE_SCHEMA(('IFC4X3_ADD2'));ENDSEC;DATA;
        #1=IFCPROJECT('0YvctVUKr0kugbFTf53O9L',$,'P',$,$,$,$,$,#2);
        #2=IFCUNITASSIGNMENT((#3,#4));#3=IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);#4=IFCSIUNIT(*,.PLANEANGLEUNIT.,$,.RADIAN.);
        #10=IFCALIGNMENT('1YvctVUKr0kugbFTf53O9L',$,'Road A',$,$,$,$,$);
        #11=IFCALIGNMENTHORIZONTAL('2YvctVUKr0kugbFTf53O9L',$,$,$,$,$,$);
        #13=IFCALIGNMENTVERTICAL('2ZvctVUKr0kugbFTf53O9L',$,$,$,$,$,$);
        #12=IFCRELNESTS('3YvctVUKr0kugbFTf53O9L',$,$,$,#10,(#11,#13));
        #20=IFCCARTESIANPOINT((0.,0.));#21=IFCALIGNMENTHORIZONTALSEGMENT($,$,#20,0.,0.,0.,100.,$,.LINE.);
        #22=IFCALIGNMENTSEGMENT('4YvctVUKr0kugbFTf53O9L',$,$,$,$,$,$,#21);
        #23=IFCCARTESIANPOINT((100.,0.));#24=IFCALIGNMENTHORIZONTALSEGMENT($,$,#23,0.,200.,200.,100.,$,.CIRCULARARC.);
        #25=IFCALIGNMENTSEGMENT('5YvctVUKr0kugbFTf53O9L',$,$,$,$,$,$,#24);
        #26=IFCRELNESTS('6YvctVUKr0kugbFTf53O9L',$,$,$,#11,(#22,#25));
        #30=IFCALIGNMENTVERTICALSEGMENT($,$,0.,200.,10.,0.02,0.02,$,.CONSTANTGRADIENT.);
        #31=IFCALIGNMENTSEGMENT('7YvctVUKr0kugbFTf53O9L',$,$,$,$,$,$,#30);
        #32=IFCRELNESTS('8YvctVUKr0kugbFTf53O9L',$,$,$,#13,(#31));
        ENDSEC;END-ISO-10303-21;
        """
        let r = try IFCImporter.importFile(ifc)
        XCTAssertEqual(r.stats["alignment"], 1)
        let a = try XCTUnwrap(r.doc.entities.first { $0.layer == "IFC-ALIGNMENT" })
        XCTAssertEqual(a.props["name"], "Road A")
        XCTAssertEqual(a.props["segments"], "LINE,CIRCULARARC")
        guard case .polyline(let pl) = a.geometry, let last = pl.vertices.last?.p else { return XCTFail() }
        XCTAssertEqual(last.x, 100_000 + 200_000 * sin(0.5), accuracy: 1)
        XCTAssertEqual(last.y, 200_000 - 200_000 * cos(0.5), accuracy: 1)
        let z = (a.props["elevations"] ?? "").split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(z.count, pl.vertices.count)
        XCTAssertEqual(z.first ?? 0, 10_000, accuracy: 1e-6)
        XCTAssertEqual(z.last ?? 0, 14_000, accuracy: 5)
    }

    func testIFC43AlignmentExportRoundTrip() throws {
        var d = IOIFCSchemaTests().model()
        // 100 m straight, then a quarter circle of R = 50 m turning left (bulge tan(90°/4)), rising 2 %.
        let bulge = tan(Double.pi / 8)
        let pl = PolylineGeom([PolyVertex(Vec2(0, 0)), PolyVertex(Vec2(100_000, 0), bulge: bulge), PolyVertex(Vec2(150_000, 50_000))], closed: false)
        let len = 100_000 + 50_000 * Double.pi / 2
        d.ensureLayer("C-ROAD-ALIGNMENT")
        d.add(Entity(layer: "C-ROAD-ALIGNMENT", geometry: .polyline(pl), props: ["name": "Access road", "elevations": "0,2000,\(fmt(0.02 * len, 3))"]))
        let text = IFCExporter.export(doc: d, meshes: MeshBuilder.build(doc: d), options: IFCExportOptions(schema: .ifc4x3, modelView: .referenceView))
        let issues = IFCValidator.validate(text).filter { $0.severity == .error }
        XCTAssertTrue(issues.isEmpty, issues.map(\.description).joined(separator: "\n"))
        let f = try STEPParser.parse(text)
        XCTAssertEqual(f.all("IFCALIGNMENT").count, 1)
        XCTAssertEqual(f.all("IFCALIGNMENTHORIZONTALSEGMENT").count, 2)
        XCTAssertEqual(f.all("IFCALIGNMENTVERTICALSEGMENT").count, 2)
        let arc = try XCTUnwrap(f.all("IFCALIGNMENTHORIZONTALSEGMENT").first { $0[8].enumValue == "CIRCULARARC" })
        XCTAssertEqual(arc[4].double ?? 0, 50_000, accuracy: 1e-3, "left turn: positive radius (mm)")
        XCTAssertEqual(arc[6].double ?? 0, 50_000 * Double.pi / 2, accuracy: 1e-3)
        // One decomposition of the project: site and alignment together.
        let proj = try XCTUnwrap(f.all("IFCPROJECT").first)
        XCTAssertEqual(f.all("IFCRELAGGREGATES").filter { $0[4].ref == proj.id }.count, 1)
        // Back in: the same path and heights.
        let back = try IFCImporter.importFile(text)
        let a = try XCTUnwrap(back.doc.entities.first { $0.layer == "IFC-ALIGNMENT" })
        XCTAssertEqual(a.props["name"], "Access road")
        guard case .polyline(let p2) = a.geometry, let end = p2.vertices.last?.p else { return XCTFail() }
        XCTAssertEqual(end.x, 150_000, accuracy: 1); XCTAssertEqual(end.y, 50_000, accuracy: 1)
        let z = (a.props["elevations"] ?? "").split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(z.last ?? 0, 0.02 * len, accuracy: 20)
        // IFC4 exports carry no alignments.
        XCTAssertFalse(IFCExporter.export(doc: d, meshes: MeshBuilder.build(doc: d), options: IFCExportOptions(schema: .ifc4)).contains("IFCALIGNMENT("))
    }

    @MainActor func testSurveyFieldToFinish() async throws {
        XCTAssertEqual(SurveyCodes.parse("EP1 B"), SurveyCodes.Parsed(feature: "EP", string: 1, control: "B"))
        XCTAssertEqual(SurveyCodes.parse("bld2 close"), SurveyCodes.Parsed(feature: "BLD", string: 2, control: "C"))
        XCTAssertEqual(SurveyCodes.parse("TREE"), SurveyCodes.Parsed(feature: "TREE", string: nil, control: nil))
        XCTAssertNil(SurveyCodes.parse("123"))
        let csv = """
        name,x,y,z,code
        1,0,0,10,EP1 B
        2,10,0,10.5,EP1
        3,20,0,11,EP1 E
        4,0,5,10,EP2 B
        5,20,5,11,EP2
        6,5,20,12,TREE
        7,30,30,9,BLD1 B
        8,40,30,9,BLD1
        9,40,40,9,BLD1
        10,30,40,9,BLD1 C
        """
        let pts = PointTable.importPoints(csv, options: { var o = PointImportOptions(); o.scale = 1000; return o }()).entities
        let ed = Editor()
        for e in pts { ed.doc.add(e) }
        ed.doc.setVariable("SURVEYCODES", "EP=V-ROAD-EDGE:line; TREE=V-TREE:point")
        await ed.run("SURVEYLINES")
        let lines = ed.doc.entities.compactMap { e -> (Entity, PolylineGeom)? in if case .polyline(let p) = e.geometry { return (e, p) }; return nil }
        XCTAssertEqual(lines.count, 3)
        let ep1 = try XCTUnwrap(lines.first { $0.0.props["string"] == "EP#1" })
        XCTAssertEqual(ep1.0.layer, "V-ROAD-EDGE")
        XCTAssertEqual(ep1.1.vertices.count, 3)
        XCTAssertEqual(ep1.0.props["elevations"], "10000,10500,11000")
        let bld = try XCTUnwrap(lines.first { $0.0.props["survey"] == "BLD" })
        XCTAssertTrue(bld.1.closed); XCTAssertEqual(bld.0.layer, "SURVEY-BLD")
        XCTAssertTrue(ed.doc.entities.contains { $0.props["code"] == "TREE" && $0.layer == "V-TREE" })
        ed.undo()
        XCTAssertFalse(ed.doc.entities.contains { if case .polyline = $0.geometry { return true }; return false })
    }

    func testSparkleEdDSAUpdateVerification() throws {
        let seed = Ed25519.generateSeed()
        let pk = Data(Ed25519.publicKey(seed: seed)).base64EncodedString()
        let dmg = Data((0..<5000).map { UInt8($0 % 251) })
        let sig = Data(Ed25519.sign([UInt8](dmg), seed: seed)).base64EncodedString()
        let appcast = """
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><title>2.0</title>
        <enclosure url="https://example.org/a-2.0.dmg" length="5000" sparkle:version="2000" sparkle:shortVersionString="2.0" sparkle:edSignature="\(sig)"/></item></channel></rss>
        """
        let item = try XCTUnwrap(UpdateCheck.parseAppcast(Data(appcast.utf8)).first)
        XCTAssertTrue(UpdateCheck.verifyEdSignature(dmg, signature: sig, publicKey: pk))
        XCTAssertNil(UpdateCheck.check(download: dmg, item: item, publicKey: pk))
        var tampered = dmg; tampered[100] ^= 1
        XCTAssertNotNil(UpdateCheck.check(download: tampered, item: item, publicKey: pk))
        XCTAssertNotNil(UpdateCheck.check(download: dmg.dropLast(), item: item, publicKey: pk), "wrong length")
        let other = Data(Ed25519.publicKey(seed: Ed25519.generateSeed())).base64EncodedString()
        XCTAssertNotNil(UpdateCheck.check(download: dmg, item: item, publicKey: other), "signed with another key")
    }
}
