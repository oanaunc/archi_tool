// Oanarina Archi Tool — GPL-3.0-or-later
// STEP units: the representation context's units win over other unit instances in the file.
import XCTest
@testable import ArchiCore

final class IOSTEPDiagTests: XCTestCase {
    func testContextUnitsWin() throws {
        let text = """
        ISO-10303-21;HEADER;FILE_SCHEMA(('AUTOMOTIVE_DESIGN'));ENDSEC;DATA;
        #1=(LENGTH_UNIT()NAMED_UNIT(*)SI_UNIT(.MILLI.,.METRE.));
        #2=(NAMED_UNIT(*)PLANE_ANGLE_UNIT()SI_UNIT($,.RADIAN.));
        #3=LENGTH_MEASURE_WITH_UNIT(LENGTH_MEASURE(25.4),#1);
        #4=(CONVERSION_BASED_UNIT('INCH',#3)LENGTH_UNIT()NAMED_UNIT(#9));
        #5=PLANE_ANGLE_MEASURE_WITH_UNIT(PLANE_ANGLE_MEASURE(0.0174532925),#2);
        #6=(CONVERSION_BASED_UNIT('DEGREE',#5)NAMED_UNIT(#9)PLANE_ANGLE_UNIT());
        #7=(GEOMETRIC_REPRESENTATION_CONTEXT(3)GLOBAL_UNIT_ASSIGNED_CONTEXT((#4,#6))REPRESENTATION_CONTEXT('',''));
        #9=DIMENSIONAL_EXPONENTS(1.,0.,0.,0.,0.,0.,0.);
        ENDSEC;END-ISO-10303-21;
        """
        let u = StepUnits.resolve(try STEPParser.parse(text))
        XCTAssertEqual(u.mmPerUnit, 25.4, accuracy: 1e-9)
        XCTAssertEqual(u.radPerAngle, .pi / 180, accuracy: 1e-9)
        // Without a context: the first unit by instance number.
        let bare = try STEPParser.parse(text.replacingOccurrences(of: "#7=(GEOMETRIC_REPRESENTATION_CONTEXT(3)GLOBAL_UNIT_ASSIGNED_CONTEXT((#4,#6))REPRESENTATION_CONTEXT('',''));", with: ""))
        XCTAssertEqual(StepUnits.resolve(bare).mmPerUnit, 1)
        XCTAssertEqual(StepUnits.resolve(bare).radPerAngle, 1)
    }
}
