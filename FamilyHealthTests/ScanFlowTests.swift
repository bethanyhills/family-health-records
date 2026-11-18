import SwiftData
import XCTest
@testable import FamilyHealth

final class ScanFlowTests: XCTestCase {
    private let eli = DocumentOwner.Candidate(id: UUID(), name: "Eli Hills", dateOfBirth: TypedDate.parse("03/14/2017"))
    private let owen = DocumentOwner.Candidate(id: UUID(), name: "Owen Hills", dateOfBirth: TypedDate.parse("09/02/2014"))
    private let beth = DocumentOwner.Candidate(id: UUID(), name: "Beth Hills", dateOfBirth: TypedDate.parse("05/20/1985"))
    private var family: [DocumentOwner.Candidate] { [eli, owen, beth] }

    func testCatchesASiblingsPlanScannedIntoTheWrongProfile() {
        let text = """
        Springfield Public Schools
        Section 504 Plan
        Student: Owen Hills    Date of birth: 09/02/2014
        Parent/Guardian: Beth Hills
        Accommodations: extended time
        """
        XCTAssertEqual(DocumentOwner.otherOwner(of: text, current: eli, family: family)?.id, owen.id)
        XCTAssertNil(DocumentOwner.otherOwner(of: text, current: owen, family: family))
    }

    func testAParentNamedOnTheFormIsNotTheOwner() {
        let text = "Student Name: Eli Hills\nParent: Beth Hills\nPhone 555-0100"
        XCTAssertNil(DocumentOwner.otherOwner(of: text, current: eli, family: family))
    }

    func testLastNameFirstAndBirthdaysCount() {
        XCTAssertEqual(DocumentOwner.otherOwner(of: "Patient: HILLS, OWEN", current: eli, family: family)?.id, owen.id)
        XCTAssertEqual(DocumentOwner.otherOwner(of: "DOB 9/2/2014\nAmoxicillin 400 mg/5 mL", current: eli, family: family)?.id, owen.id)
    }

    func testStaysQuietWhenItCantTell() {
        // No names at all, a sibling mentioned in passing, and two siblings named equally.
        XCTAssertNil(DocumentOwner.otherOwner(of: "Hepatitis B 06/15/2015", current: eli, family: family))
        XCTAssertNil(DocumentOwner.otherOwner(of: "Owen came to the visit too.", current: eli, family: family))
        XCTAssertNil(DocumentOwner.otherOwner(of: "Owen Hills and Beth Hills", current: eli, family: family))
        XCTAssertNil(DocumentOwner.otherOwner(of: "Student: Owen Hills", current: eli, family: [eli]))
    }

    func testPreferredNamesAndWholeWordsOnly() {
        let theo = DocumentOwner.Candidate(id: UUID(), name: "Theodore Hills", preferredName: "Theo")
        XCTAssertEqual(DocumentOwner.otherOwner(of: "Name: Theo Hills", current: eli, family: [eli, theo])?.id, theo.id)
        // "Eli" inside "Elizabeth" isn't Eli.
        XCTAssertEqual(DocumentOwner.score(eli, in: "Elizabeth Street"), 0)
    }

    func testNewDocumentsGetTheTypeTheyReadAs() {
        let vaccines = "Immunization Record\nHep B 06/15/2015\nDTaP 08/17/2015\nMMR 06/20/2016"
        let action = DocumentImport.offered(kind: .other, text: vaccines)
        XCTAssertEqual(action, .vaccines)
        XCTAssertEqual(action?.documentKind(for: vaccines), .vaccineRecord)
        XCTAssertEqual(DocumentImport.schoolPlan.documentKind(for: "Section 504 Plan. 504 accommodations."), .plan504)
        XCTAssertEqual(DocumentImport.offered(kind: .iep, text: ""), .schoolPlan)
        XCTAssertNil(DocumentImport.offered(kind: .labResults, text: "Ferritin 9 ng/mL"))
    }

    func testHeightAndWeightFromAVisitSummary() {
        let rows = ["After Visit Summary", "Visit date: 11/10/2026", "Vitals", "BP 100/60  Ht 4' 2.5\"  Wt 62 lb 8 oz",
                    "Birth weight 7 lb 2 oz", "Diagnoses", "Well child check"]
        let result = VisitSummaryParser.parse(rows: rows, now: TypedDate.parse("11/18/2026")!)
        XCTAssertEqual(result.height, "4 ft 3 in")
        XCTAssertEqual(result.weight, "62.5 lb")
        XCTAssertEqual(VisitSummaryParser.height(in: ["Height: 127 cm"])?.text, "127 cm")
        XCTAssertEqual(VisitSummaryParser.height(in: ["Ht: 1.27 m"])?.text, "127 cm")
        XCTAssertEqual(VisitSummaryParser.weight(in: ["Weight: 28.1 kg"])?.text, "28.1 kg")
        XCTAssertNil(VisitSummaryParser.weight(in: ["Birth weight: 7 lb 2 oz"]))
        XCTAssertNil(VisitSummaryParser.height(in: ["Follow up in 2 weeks"]))
    }

    func testMeasurementsAreWrittenLikeTheProfileAndOnlyWhenNew() {
        // Kept in the profile's units.
        XCTAssertEqual(BodyMeasurement.update(weight: "28.1 kg", current: "58 lb"), "62 lb")
        XCTAssertEqual(BodyMeasurement.update(height: "4 ft 2 in", current: "120 cm"), "127 cm")
        // Nothing to offer when it's the same, or when nothing was read.
        XCTAssertEqual(BodyMeasurement.update(height: "4 ft 2 in", current: "4 ft 2 in"), "")
        XCTAssertEqual(BodyMeasurement.update(weight: "", current: "58 lb"), "")
        // An empty profile takes it as read.
        XCTAssertEqual(BodyMeasurement.update(weight: "62 lb", current: ""), "62 lb")
    }

    @MainActor
    func testImportedDateSurvivesABackup() throws {
        let source = ModelContext(ModelStore.makeContainer(inMemory: true))
        let kid = Person(name: "Kid Example")
        source.insert(kid)
        let document = HealthDocument(title: "Shots", kind: .vaccineRecord)
        source.insert(document)
        document.person = kid
        let when = TypedDate.parse("11/18/2026")!
        document.importedAt = when
        try source.save()

        let archive = try BackupArchive(context: source)
        let data = try JSONEncoder().encode(archive)
        let decoded = try JSONDecoder().decode(BackupArchive.self, from: data)
        XCTAssertEqual(decoded.people.first?.documents?.first?.importedAt, when)
    }
}
