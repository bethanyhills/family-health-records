import XCTest
@testable import FamilyHealth

final class PrescriptionTests: XCTestCase {
    private let now = TypedDate.parse("11/17/2026")!

    func testReadsAPharmacyLabel() {
        let rows = [
            "CVS pharmacy",
            "123 MAIN ST SPRINGFIELD IL 62701  (217) 555-0100",
            "Rx# 1234567   DATE FILLED: 03/14/2026",
            "KID EXAMPLE",
            "TAKE 1 CAPSULE BY MOUTH THREE TIMES",
            "DAILY FOR 10 DAYS",
            "AMOXICILLIN 500MG CAPSULE",
            "QTY: 30   REFILLS: 0",
            "DR. JANE SMITH",
            "DISCARD AFTER: 03/14/2027",
        ]
        let result = PrescriptionParser.parse(rows: rows, now: now)
        XCTAssertEqual(result.name, "Amoxicillin")
        XCTAssertEqual(result.dose, "500 mg capsule")
        XCTAssertEqual(result.directions, "Take 1 capsule by mouth three times daily for 10 days")
        XCTAssertEqual(result.reason, "")
        XCTAssertEqual(result.prescriber, "Dr. Jane Smith")
        XCTAssertEqual(result.pharmacy, "CVS Pharmacy")
        XCTAssertEqual(result.dateFilled?.formDate, "03/14/2026")
        XCTAssertEqual(result.rxNumber, "1234567")
        XCTAssertEqual(result.quantity, "30")
        XCTAssertEqual(result.refills, "0")
        XCTAssertEqual(result.labelDetails, "Rx #1234567 · Filled 03/14/2026 · Qty 30 · No refills")
        XCTAssertTrue(PrescriptionParser.looksLikePrescription(rows.joined(separator: "\n")))
    }

    func testReadsAPrintoutFromTheDoctor() {
        let rows = [
            "Sunrise Pediatrics",
            "Patient: Kid Example   DOB: 06/15/2015",
            "Date: 11/10/2026",
            "Rx: Amoxicillin 400 mg/5 mL suspension",
            "Sig: 6 mL po bid for ear infection",
            "Disp: 150 mL   Refills: 0",
            "Jane Smith, MD   NPI 1234567890",
        ]
        let result = PrescriptionParser.parse(rows: rows, now: now)
        XCTAssertEqual(result.name, "Amoxicillin")
        XCTAssertEqual(result.dose, "400 mg/5 mL suspension")
        XCTAssertEqual(result.directions, "6 mL by mouth twice a day for ear infection")
        XCTAssertEqual(result.reason, "ear infection")
        XCTAssertEqual(result.prescriber, "Dr. Jane Smith")
        XCTAssertEqual(result.pharmacy, "")
        XCTAssertEqual(result.dateFilled?.formDate, "11/10/2026")
        XCTAssertEqual(result.quantity, "150 mL")
        XCTAssertEqual(result.refills, "0")
    }

    func testSkipsStickersAndReadsWrappedDirections() {
        let rows = [
            "TAKE WITH FOOD",
            "Walgreens #1234",
            "RX 0123456-07890  FILL DATE 10/02/2026",
            "GIVE 7.5 ML BY MOUTH EVERY 6 HOURS AS",
            "NEEDED FOR PAIN OR FEVER",
            "IBUPROFEN 100MG/5ML SUSP",
            "PRESCRIBER: SMITH, JANE PA-C",
            "QTY 120 ML  NO REFILLS",
        ]
        let result = PrescriptionParser.parse(rows: rows, now: now)
        XCTAssertEqual(result.name, "Ibuprofen")
        XCTAssertEqual(result.dose, "100 mg/5 mL suspension")
        XCTAssertEqual(result.directions, "Give 7.5 mL by mouth every 6 hours as needed for pain or fever")
        XCTAssertEqual(result.reason, "pain or fever")
        XCTAssertEqual(result.prescriber, "Jane Smith, PA-C")
        XCTAssertEqual(result.pharmacy, "Walgreens")
        XCTAssertEqual(result.dateFilled?.formDate, "10/02/2026")
        XCTAssertEqual(result.rxNumber, "0123456-07890")
        XCTAssertEqual(result.quantity, "120 mL")
        XCTAssertEqual(result.refills, "0")
    }

    func testOtherDocumentsDontLookLikePrescriptions() {
        let lab = "Sunrise Lab\nHemoglobin 13.5 g/dL  normal\nWhite blood cells 6.1\nCollected 10/01/2026"
        XCTAssertFalse(PrescriptionParser.looksLikePrescription(lab))
        XCTAssertTrue(PrescriptionParser.parse(rows: ["Thank you for visiting"], now: now).isEmpty)
    }

    func testMatchesSavedPharmaciesAndProviders() {
        XCTAssertEqual(PrescriptionParser.matchPharmacy("CVS Pharmacy", existing: ["Walgreens", "CVS Pharmacy #4471"]),
                       "CVS Pharmacy #4471")
        XCTAssertEqual(PrescriptionParser.matchPharmacy("CVS Pharmacy", existing: ["cvs #1", "CVS #2"], preferred: ["CVS #2"]),
                       "CVS #2")
        XCTAssertNil(PrescriptionParser.matchPharmacy("Walgreens", existing: ["CVS Pharmacy"]))

        let providers = ["Dr. Mary Smith", "Jane Smith, MD", "Dr. Lee"]
        XCTAssertEqual(PrescriptionParser.matchProvider("Dr. Jane Smith", existing: providers), "Jane Smith, MD")
        XCTAssertEqual(PrescriptionParser.matchProvider("Dr. Jane Smith", existing: ["Smith, Jane"]), "Smith, Jane")
        XCTAssertNil(PrescriptionParser.matchProvider("Dr. Jane Smith", existing: ["Dr. Mary Smith", "Dr. Lee"]))
    }

    func testFindsTheMedicationBeingRefilled() {
        let saved: [(name: String, isActive: Bool)] = [("Amoxicillin 250", false), ("Cetirizine", true), ("amoxicillin", true)]
        XCTAssertEqual(PrescriptionParser.matchingMedication(named: "Amoxicillin", in: saved), 2)
        XCTAssertNil(PrescriptionParser.matchingMedication(named: "Ibuprofen", in: saved))
    }

    func testDateScannerReadsShortYears() {
        let found = DateScanner.dates(in: "Filled 3/14/26, refill by Apr 2, 2027", now: now)
        XCTAssertEqual(found.map(\.date.formDate), ["03/14/2026", "04/02/2027"])
    }
}
