// Oanarina Archi Tool — GPL-3.0-or-later
// Windows/Linux support for the test suite. Apple's XCTest lets a test case be created with `SomeTests()` to reuse its
// helpers; the open-source XCTest (Windows, Linux) needs a name and a closure, so give the helper classes that initializer.
import XCTest
@testable import ArchiCore

#if !canImport(Darwin)
extension AnalysisAgentToolsTests { convenience init() { self.init(name: "helper", testClosure: { _ in }) } }
extension AnalysisEnergyPlusTests { convenience init() { self.init(name: "helper", testClosure: { _ in }) } }
extension IOIFCSchemaTests { convenience init() { self.init(name: "helper", testClosure: { _ in }) } }
#endif
