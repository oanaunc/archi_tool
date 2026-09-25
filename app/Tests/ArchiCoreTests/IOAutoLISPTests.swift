// Oanarina Archi Tool — GPL-3.0-or-later
// AutoLISP subset (SCR-005).
import XCTest
@testable import ArchiCore

final class IOAutoLISPTests: XCTestCase {
    @MainActor func eval(_ s: String) async throws -> LispValue { try await LispInterpreter().run(s) }

    @MainActor func testLanguageCore() async throws {
        let v1 = try await eval("(defun sq (x) (* x x)) (sq 12)")
        XCTAssertEqual(v1, .int(144))
        let v2 = try await eval("(setq l '(1 2 3)) (mapcar '(lambda (x) (* x 10)) l)")
        XCTAssertEqual(v2, .list([.int(10), .int(20), .int(30)]))
        let v3 = try await eval("(setq i 0 s 0) (while (< i 5) (setq s (+ s i) i (1+ i))) s")
        XCTAssertEqual(v3, .int(10))
        let v4 = try await eval("(cdr (assoc 8 '((0 . \"LINE\") (8 . \"WALLS\"))))")
        XCTAssertEqual(v4, .str("WALLS"))
        let v5 = try await eval("(strcat \"A\" (itoa 42) (substr \"hello\" 2 3) (strcase \"x\"))")
        XCTAssertEqual(v5, .str("A42ellX"))
        let v6 = try await eval("(polar '(0 0) (/ pi 2) 100)")
        XCTAssertEqual(v6.point.map { $0.distance(to: Vec2(0, 100)) } ?? 1, 0, accuracy: 1e-9)
        let v7 = try await eval("(cond ((= 1 2) \"a\") ((> 3 2) \"b\") (T \"c\"))")
        XCTAssertEqual(v7, .str("b"))
        let v8 = try await eval("(foreach x '(1 2 3) (setq acc (cons x acc))) acc")
        XCTAssertEqual(v8, .list([.int(3), .int(2), .int(1)]))
        let v9 = try await eval("(/ 7 2) ")
        XCTAssertEqual(v9, .int(3))
        let v10 = try await eval("(/ 7.0 2)")
        XCTAssertEqual(v10, .real(3.5))
        let v11 = try await eval("(vl-sort '(3 1 2) '<)")
        XCTAssertEqual(v11, .list([.int(1), .int(2), .int(3)]))
        do { _ = try await eval("(undefined-fn 1)"); XCTFail("should throw") } catch { XCTAssertTrue("\(error)".contains("no function definition")) }
        do { _ = try await eval("(/ 1 0)"); XCTFail("should throw") } catch {}
        do { _ = try await eval("(+ 1 2"); XCTFail("should throw") } catch {}
    }

    @MainActor func testLoadFileAndRunCommands() async throws {
        let src = """
        ; sample routine
        (defun c:mybox (/ p w)
          (setq p '(0 0) w 1000.0)
          (command "RECTANG" p (list w w))
          (princ "box drawn"))
        (defun c:circles (/ i)
          (setq i 0)
          (repeat 3 (command "CIRCLE" (list (* i 1000) 0) 200) (setq i (1+ i)))
          (princ))
        (defun c:circlestolayer (/ ss n e)
          (setq ss (ssget "X" '((0 . "CIRCLE"))) n 0)
          (while (< n (sslength ss))
            (setq e (entget (ssname ss n)))
            (entmod (subst (cons 8 "CIRCLES") (assoc 8 e) e))
            (setq n (1+ n)))
          (princ (strcat (itoa n) " circles moved")))
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID().uuidString).lsp")
        try src.write(to: url, atomically: true, encoding: .utf8)
        let ed = Editor()
        await ed.run("LISPLOAD \(url.path)")
        await ed.backgroundTask?.value
        XCTAssertNotNil(ed.registry.lookup("MYBOX"))
        await ed.run("MYBOX")
        await ed.backgroundTask?.value
        XCTAssertEqual(ed.doc.entities.filter { $0.typeName == "polyline" }.count, 1, ed.log.suffix(12).joined(separator: "\n"))
        await ed.run("CIRCLES")
        await ed.backgroundTask?.value
        XCTAssertEqual(ed.doc.entities.filter { $0.typeName == "circle" }.count, 3)
        await ed.run("CIRCLESTOLAYER")
        await ed.backgroundTask?.value
        XCTAssertEqual(ed.doc.entities.filter { $0.layer == "CIRCLES" }.count, 3, ed.log.suffix(12).joined(separator: "\n"))
        XCTAssertTrue(ed.log.contains { $0.contains("3 circles moved") }, ed.log.suffix(12).joined(separator: "\n"))
        ed.undo()   // each (command) and each LISP edit is undoable
        XCTAssertEqual(ed.doc.entities.filter { $0.layer == "CIRCLES" }.count, 2)
        await ed.run("LISP (getvar 'clayer)")
        await ed.backgroundTask?.value
        XCTAssertTrue(ed.log.contains("\"0\""), ed.log.suffix(5).joined(separator: "\n"))
    }
}
