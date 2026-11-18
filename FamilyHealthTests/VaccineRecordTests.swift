import SwiftData
import XCTest
@testable import FamilyHealth

final class VaccineRecordTests: XCTestCase {
    private let now = TypedDate.parse("11/17/2026")!

    private func summary(_ found: [VaccineRecordParser.Found]) -> [String] {
        found.map { "\($0.vaccine) \($0.date.formDate)" }
    }

    func testReadsATablePrintout() {
        let rows = [
            "Sunrise Pediatrics  Immunization Record",
            "Name: Kid Example   Date of birth: 06/15/2015",
            "Vaccine  Dose 1  Dose 2  Dose 3",
            "Hep B  06/15/2015  07/20/2015  12/18/2015",
            "DTaP  08/17/2015  10/19/2015",
            "12/21/2015",
            "MMR  6/20/16  6/22/19",
            "Varicella (chickenpox)  06/20/2016",
            "Influenza  2023-10-02",
        ]
        let found = VaccineRecordParser.parse(rows: rows, dateOfBirth: TypedDate.parse("06/15/2015"), now: now)
        XCTAssertEqual(summary(found), [
            "Hepatitis B 06/15/2015", "Hepatitis B 07/20/2015", "Hepatitis B 12/18/2015",
            "DTaP 08/17/2015", "DTaP 10/19/2015", "DTaP 12/21/2015",
            "MMR 06/20/2016", "MMR 06/22/2019",
            "Varicella (chickenpox) 06/20/2016",
            "Flu 10/02/2023",
        ])
    }

    func testCombinationsAndSideBySideColumns() {
        let rows = [
            "Pediarix (DTaP-HepB-IPV) 08/17/2015   Hib 08/17/2015",
            "DTaP-IPV  Kinrix  Sep 3, 2019",
            "Tdap 03/04/2026  Td 01/02/2025",
        ]
        let found = VaccineRecordParser.parse(rows: rows, now: now)
        XCTAssertEqual(summary(found), [
            "Pediarix (DTaP-HepB-IPV) 08/17/2015", "Hib 08/17/2015",
            "Kinrix or Quadracel (DTaP-IPV) 09/03/2019",
            "Tdap 03/04/2026", "Td 01/02/2025",
        ])
    }

    func testIgnoresImpossibleDatesAndOtherLines() {
        let rows = [
            "Date of birth 06/15/2015",
            "Printed 11/18/2026",
            "Hep B 06/14/2010  13/45/2016  06/15/2015",
            "Call 555-0100 with questions",
        ]
        let found = VaccineRecordParser.parse(rows: rows, dateOfBirth: TypedDate.parse("06/15/2015"), now: now)
        XCTAssertEqual(summary(found), ["Hepatitis B 06/15/2015"])
    }

    func testRecognizesNamesAndExistingShots() {
        XCTAssertEqual(VaccineRecordParser.canonicalName("Prevnar 13"), "Pneumococcal (PCV)")
        XCTAssertEqual(VaccineRecordParser.canonicalName("tdap booster"), "Tdap")
        XCTAssertEqual(VaccineRecordParser.canonicalName("MMRV"), "ProQuad (MMRV)")
        XCTAssertNil(VaccineRecordParser.canonicalName("Allergy shot"))

        let date = TypedDate.parse("08/17/2015")!
        let found = VaccineRecordParser.Found(vaccine: "DTaP", date: date)
        XCTAssertTrue(VaccineRecordParser.isAlreadyRecorded(found, in: [(vaccine: "Daptacel", date: date)]))
        XCTAssertFalse(VaccineRecordParser.isAlreadyRecorded(found, in: [(vaccine: "DTaP", date: nil)]))
        XCTAssertTrue(VaccineRecordParser.looksLikeVaccineRecord("Hep B\n06/15/2015\nDTaP\nMMR"))
        XCTAssertFalse(VaccineRecordParser.looksLikeVaccineRecord("Ferritin 9 ng/mL\nHemoglobin 12.9"))
    }

    func testTextPiecesSideBySideBecomeOneRow() {
        let pieces = [
            TextPiece(text: "06/15/2015", box: CGRect(x: 0.4, y: 0.80, width: 0.2, height: 0.03)),
            TextPiece(text: "Hep B", box: CGRect(x: 0.05, y: 0.805, width: 0.15, height: 0.03)),
            TextPiece(text: "DTaP", box: CGRect(x: 0.05, y: 0.75, width: 0.15, height: 0.03)),
            TextPiece(text: "08/17/2015", box: CGRect(x: 0.4, y: 0.748, width: 0.2, height: 0.03)),
        ]
        XCTAssertEqual(TextPiece.rows(pieces), ["Hep B  06/15/2015", "DTaP  08/17/2015"])
    }
}
