import SwiftData
import XCTest
@testable import FamilyHealth

@MainActor
final class SchoolPlanReaderTests: XCTestCase {
    private let now = TypedDate.parse("11/17/2026")!

    func testReadsAnIEP() {
        let rows = [
            "Maple Grove School District",
            "INDIVIDUALIZED EDUCATION PROGRAM (IEP)",
            "Student: Kid Example   DOB: 06/15/2015",
            "IEP Meeting Date: 09/02/2026   Annual Review Date: 09/01/2027",
            "Primary Disability: Speech or Language Impairment (SLI)",
            "Present Levels of Academic Achievement",
            "Kid reads at grade level. The IEP team notes articulation errors.",
            "Special Education and Related Services",
            "Speech-language therapy   30 min   1x weekly   Resource room",
            "Occupational therapy   30 minutes   2x/month",
            "Accommodations",
            "• Preferential seating near the teacher",
            "• Extended time (1.5x) on tests and",
            "assignments",
            "• Breaks as needed",
            "Annual Goals",
            "Goal 1: produce /r/ correctly in 80% of trials",
        ]
        let result = SchoolPlanParser.parse(rows: rows, now: now)
        XCTAssertEqual(result.plan, .iep)
        XCTAssertEqual(result.planDate?.formDate, "09/02/2026")
        XCTAssertEqual(result.details.nextReview?.formDate, "09/01/2027")
        XCTAssertEqual(result.details.eligibility, "Speech or Language Impairment")
        XCTAssertEqual(result.details.services, [
            "Speech-language therapy, 30 min, 1x weekly, Resource room",
            "Occupational therapy, 30 minutes, 2x/month",
        ])
        XCTAssertEqual(result.details.accommodations, [
            "Preferential seating near the teacher",
            "Extended time (1.5x) on tests and assignments",
            "Breaks as needed",
        ])
        XCTAssertTrue(SchoolPlanParser.looksLikeSchoolPlan(rows.joined(separator: "\n")))
    }

    func testTellsA504PlanFromAnIEP() {
        let text = "Section 504 Plan\n504 Meeting Date: 08/20/2026\nAccommodations: Water bottle at desk; Nurse visits as needed"
        XCTAssertEqual(SchoolPlanParser.planKind(of: text), .plan504)
        let result = SchoolPlanParser.parse(rows: text.components(separatedBy: "\n"), now: now)
        XCTAssertEqual(result.plan, .plan504)
        XCTAssertEqual(result.details.accommodations, ["Water bottle at desk", "Nurse visits as needed"])
        XCTAssertFalse(SchoolPlanParser.looksLikeSchoolPlan("Lab results\nHemoglobin 13.5"))
    }

    func testDetailsLiveInTheDocumentNotesAndShowOnTheIntakeSummary() throws {
        let details = SchoolPlanDetails(eligibility: "Autism", nextReview: TypedDate.parse("09/01/2027"),
                                        services: ["Speech, 30 min weekly"], accommodations: ["Breaks", "Visual schedule"])
        let notes = details.merged(into: "Bring a copy to the doctor.\nServices: old list")
        XCTAssertEqual(notes, """
        Bring a copy to the doctor.

        Eligibility: Autism
        Next review: 09/01/2027
        Services: Speech, 30 min weekly
        Accommodations: Breaks; Visual schedule
        """)
        XCTAssertEqual(SchoolPlanDetails(notes: notes), details)

        let context = ModelContext(ModelStore.makeContainer(inMemory: true))
        let kid = Person(name: "Kid Example")
        context.insert(kid)
        kid.schoolPlan = .iep
        let plan = HealthDocument(title: "IEP", kind: .iep)
        plan.notes = notes
        context.insert(plan)
        plan.person = kid
        try context.save()

        let school = try XCTUnwrap(IntakeSummary.sections(for: kid).first { $0.title == "School" })
        let values = Dictionary(uniqueKeysWithValues: school.items.map { ($0.label, $0.value) })
        XCTAssertEqual(values["Eligibility"], "Autism")
        XCTAssertEqual(values["Services"], "Speech, 30 min weekly")
        XCTAssertEqual(values["Accommodations"], "Breaks; Visual schedule")
        XCTAssertEqual(values["Plan review by"], "09/01/2027")
    }
}
