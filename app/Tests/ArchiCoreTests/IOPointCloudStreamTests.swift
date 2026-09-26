// Oanarina Archi Tool — GPL-3.0-or-later
// Out-of-core sampling of large point clouds (IO-049 LAS, IO-050 XYZ/PTS/PLY).
import XCTest
@testable import ArchiCore

final class IOPointCloudStreamTests: XCTestCase {
    var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pcstream-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func grid(_ n: Int) -> [CloudPoint] {
        (0..<n).map { i in CloudPoint(Vec3(Double(i % 100) * 0.1, Double(i / 100) * 0.1, Double(i % 7) * 0.5), color: (UInt8(i % 256), 10, 200)) }
    }

    func testLASSamplingMatchesTheFullReader() throws {
        let pts = grid(30_000)
        let url = dir.appendingPathComponent("cloud.las")
        try LASReader.write(pts).write(to: url)
        let s = try XCTUnwrap(PointCloudStream.sample(url, maxPoints: 1000))
        let full = try LASReader.read(try Data(contentsOf: url), maxPoints: 1000)
        XCTAssertEqual(s.total, 30_000)
        XCTAssertFalse(s.estimated)
        XCTAssertEqual(s.points.count, 1000)
        for i in stride(from: 0, to: 1000, by: 97) {
            XCTAssertEqual(s.points[i].p.distance(to: full.points[i].p), 0, accuracy: 1e-9)
            XCTAssertEqual(s.points[i].color?.0, full.points[i].color?.0)
        }
        // Through the importer with streaming forced.
        let r = try PointCloudStream.load(url, options: PointCloudOptions(scale: 1000, maxPoints: 500), threshold: 0)
        XCTAssertTrue(r.sampled)
        XCTAssertEqual(r.entities.count, 500)
        XCTAssertEqual(r.total, 30_000)
    }

    func testTextSamplingEstimatesTheCount() throws {
        let pts = grid(20_000)
        var text = "\(pts.count)\n"
        for p in pts { text += "\(fmt(p.p.x, 3)) \(fmt(p.p.y, 3)) \(fmt(p.p.z, 3)) 0.5 \(p.color!.0) \(p.color!.1) \(p.color!.2)\n" }
        let url = dir.appendingPathComponent("cloud.pts")
        try text.write(to: url, atomically: true, encoding: .utf8)
        let s = try XCTUnwrap(PointCloudStream.sample(url, maxPoints: 800))
        XCTAssertTrue(s.estimated)
        XCTAssertGreaterThan(s.points.count, 780)
        XCTAssertLessThanOrEqual(s.points.count, 800)
        XCTAssertEqual(Double(s.total), 20_000, accuracy: 20_000 * 0.05)
        // Every sampled point is a real point of the file, spread over the whole file.
        let keys = Set(pts.map { "\(fmt($0.p.x, 3)),\(fmt($0.p.y, 3))" })
        for p in s.points { XCTAssertTrue(keys.contains("\(fmt(p.p.x, 3)),\(fmt(p.p.y, 3))")) }
        XCTAssertLessThan(s.points.map(\.p.y).min()!, 1)
        XCTAssertGreaterThan(s.points.map(\.p.y).max()!, 19)
        XCTAssertEqual(s.points[10].intensity, 0.5)
        XCTAssertNotNil(s.points[10].color)
        // Small files keep the exact reader.
        let exact = try PointCloudStream.load(url, options: PointCloudOptions(scale: 1, maxPoints: 0))
        XCTAssertFalse(exact.sampled)
        XCTAssertEqual(exact.total, 20_000)
    }

    func testBinaryAndASCIIPLYSampling() throws {
        let pts = grid(5000)
        var d = Data("ply\nformat binary_little_endian 1.0\nelement vertex \(pts.count)\nproperty float x\nproperty float y\nproperty float z\nproperty uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n".utf8)
        for p in pts {
            for v in [p.p.x, p.p.y, p.p.z] { var f = Float(v).bitPattern.littleEndian; d.append(Data(bytes: &f, count: 4)) }
            d.append(contentsOf: [p.color!.0, p.color!.1, p.color!.2])
        }
        let url = dir.appendingPathComponent("cloud.ply")
        try d.write(to: url)
        let s = try XCTUnwrap(PointCloudStream.sample(url, maxPoints: 250))
        let full = try PointCloud.parsePLY(d).points
        XCTAssertEqual(s.total, 5000)
        XCTAssertEqual(s.points.count, 250)
        for i in [0, 17, 249] {
            let j = Int(Double(i) * 5000.0 / 250.0)
            XCTAssertEqual(s.points[i].p.distance(to: full[j].p), 0, accuracy: 1e-5)
            XCTAssertEqual(s.points[i].color?.0, full[j].color?.0)
        }
        // ASCII PLY with vertices only.
        var a = "ply\nformat ascii 1.0\nelement vertex \(pts.count)\nproperty float x\nproperty float y\nproperty float z\nend_header\n"
        for p in pts { a += "\(p.p.x) \(p.p.y) \(p.p.z)\n" }
        let ua = dir.appendingPathComponent("ascii.ply")
        try a.write(to: ua, atomically: true, encoding: .utf8)
        let sa = try XCTUnwrap(PointCloudStream.sample(ua, maxPoints: 100))
        XCTAssertEqual(sa.total, 5000)
        XCTAssertGreaterThan(sa.points.count, 95)
        // A PLY whose faces come first needs the full reader.
        let faces = "ply\nformat ascii 1.0\nelement face 0\nproperty list uchar int vertex_indices\nelement vertex 1\nproperty float x\nproperty float y\nproperty float z\nend_header\n1 2 3\n"
        let uf = dir.appendingPathComponent("faces.ply")
        try faces.write(to: uf, atomically: true, encoding: .utf8)
        XCTAssertNil(try PointCloudStream.sample(uf, maxPoints: 10))
    }
}
