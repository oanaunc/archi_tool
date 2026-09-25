// Oanarina Archi Tool — GPL-3.0-or-later
import XCTest
@testable import ArchiCore

/// Guards against commands silently replacing each other when command lists from different areas are merged.
@MainActor
final class CommandRegistryTests: XCTestCase {
    func testNoDuplicateCommandNames() {
        var seen: [String: String] = [:], dups: [String] = []
        for c in BuiltinCommands.allDefinitions {
            if let prev = seen[c.name] { dups.append("\(c.name) (\(prev) / \(c.category))") }
            seen[c.name] = c.category
        }
        XCTAssertEqual(dups, [], "duplicate command names")
    }

    func testAliasesDoNotShadowOrCollide() {
        let defs = BuiltinCommands.allDefinitions
        let names = Set(defs.map(\.name))
        var owner: [String: String] = [:], problems: [String] = []
        for c in defs {
            for a in c.aliases where a != c.name {
                if names.contains(a) { problems.append("alias \(a) of \(c.name) is also a command name") }
                if let o = owner[a], o != c.name { problems.append("alias \(a) used by \(o) and \(c.name)") }
                owner[a] = c.name
            }
        }
        XCTAssertEqual(problems, [], problems.joined(separator: "\n"))
    }

    func testEveryCommandHasSummaryAndCategory() {
        for c in BuiltinCommands.allDefinitions {
            XCTAssertFalse(c.summary.isEmpty, c.name); XCTAssertFalse(c.category.isEmpty, c.name)
        }
    }
}
