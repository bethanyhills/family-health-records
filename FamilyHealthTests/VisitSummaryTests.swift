import XCTest
@testable import FamilyHealth

final class VisitSummaryTests: XCTestCase {
    private let now = TypedDate.parse("11/17/2026")!

    func testReadsAPortalAfterVisitSummary() {
        let rows = [
            "Sunrise Pediatrics",
            "After Visit Summary",
            "Kid Example   DOB: 06/15/2015",
            "Visit Date: 11/10/2026",
            "Provider: Jane Smith, MD",
            "Reason for Visit",
            "Ear pain",
            "Diagnoses",
            "1. Acute otitis media of right ear (H66.91)",
            "2. Fever",
            "Start taking:",
            "amoxicillin 400 mg/5 mL suspension",
            "Instructions",
            "Give the full course of antibiotics even if",
            "feeling better.",
            "Use ibuprofen for fever over 102.",
            "Follow-up",
            "Return in 2 weeks for an ear recheck.",
            "Your Medication List",
            "cetirizine 5 mg daily",
        ]
        let result = VisitSummaryParser.parse(rows: rows, now: now)
        XCTAssertEqual(result.date?.formDate, "11/10/2026")
        XCTAssertEqual(result.provider, "Dr. Jane Smith")
        XCTAssertEqual(result.reason, "Ear pain")
        XCTAssertEqual(result.diagnoses, ["Acute otitis media of right ear", "Fever"])
        XCTAssertEqual(result.medicationChanges, ["Start amoxicillin 400 mg/5 mL suspension"])
        XCTAssertEqual(result.instructions, [
            "Give the full course of antibiotics even if feeling better.",
            "Use ibuprofen for fever over 102.",
        ])
        XCTAssertEqual(result.followUp, "Return in 2 weeks for an ear recheck.")
        XCTAssertEqual(result.followUpDate?.formDate, "11/24/2026")
        XCTAssertFalse(result.notes.contains("cetirizine"), "The full medication list isn't news from this visit.")
        XCTAssertTrue(result.notes.hasPrefix("Diagnosis: Acute otitis media of right ear; Fever"))
        XCTAssertTrue(VisitSummaryParser.looksLikeVisitSummary(rows.joined(separator: "\n")))
    }

    func testReadsInlineHeadingsAndAFollowUpSentence() {
        let rows = [
            "Summary of your visit",
            "You saw Dr. Mary Lee on Nov 3, 2026 at Lakeside Urgent Care",
            "Diagnosis: Strep throat",
            "Instructions: Take all of the antibiotic. Stay home until 24 hours after starting it.",
            "Come back in 3 days if not better.",
        ]
        let result = VisitSummaryParser.parse(rows: rows, now: now)
        XCTAssertEqual(result.date?.formDate, "11/03/2026")
        XCTAssertEqual(result.provider, "Dr. Mary Lee")
        XCTAssertEqual(result.reason, "")
        XCTAssertEqual(result.diagnoses, ["Strep throat"])
        XCTAssertEqual(result.followUp, "Come back in 3 days if not better")
        XCTAssertEqual(result.followUpDate?.formDate, "11/06/2026")
    }

    func testFollowUpDates() {
        let visit = TypedDate.parse("11/10/2026")!
        XCTAssertEqual(VisitSummaryParser.followUpDate(in: "Follow up on 12/01/2026", after: visit, now: now)?.formDate, "12/01/2026")
        XCTAssertEqual(VisitSummaryParser.followUpDate(in: "Recheck in 1-2 months", after: visit, now: now)?.formDate, "12/10/2026")
        XCTAssertEqual(VisitSummaryParser.followUpDate(in: "Return within two weeks", after: visit, now: now)?.formDate, "11/24/2026")
        XCTAssertNil(VisitSummaryParser.followUpDate(in: "As needed", after: visit, now: now))
    }

    func testOtherDocumentsArentVisitSummaries() {
        let label = "CVS pharmacy\nRx# 1234567\nTAKE 1 CAPSULE BY MOUTH\nAMOXICILLIN 500MG CAPSULE\nREFILLS: 0"
        XCTAssertFalse(VisitSummaryParser.looksLikeVisitSummary(label))
        XCTAssertTrue(VisitSummaryParser.parse(rows: ["Thank you"], now: now).isEmpty)
    }
}
