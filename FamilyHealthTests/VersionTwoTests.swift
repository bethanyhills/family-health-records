import SwiftData
import UIKit
import XCTest
@testable import FamilyHealth

@MainActor
final class VersionTwoTests: XCTestCase {
    func testUpgradingAVersionOnePointTwoDatabaseKeepsRecords() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let oldFolder = folder.appendingPathComponent("v3", isDirectory: true)
        let newFolder = folder.appendingPathComponent("v4", isDirectory: true)
        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)

        // A database written by version 1.2.
        try autoreleasepool {
            let schema = Schema(versionedSchema: SchemaV3.self)
            let configuration = ModelConfiguration(
                schema: schema, url: oldFolder.appendingPathComponent("FamilyHealth.store"), cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let kid = SchemaV3.Person(name: "Kid Example")
            context.insert(kid)
            let ot = SchemaV3.Provider(name: "Jane Smith", specialty: "OT")
            context.insert(ot)
            ot.patients = [kid]
            let therapy = SchemaV3.Therapy(kind: .occupational)
            context.insert(therapy)
            therapy.person = kid
            therapy.provider = ot
            try context.save()
        }
        for name in try FileManager.default.contentsOfDirectory(atPath: oldFolder.path) {
            try FileManager.default.copyItem(
                at: oldFolder.appendingPathComponent(name), to: newFolder.appendingPathComponent(name)
            )
        }

        let container: ModelContainer
        do {
            container = try ModelStore.openContainer(url: newFolder.appendingPathComponent("FamilyHealth.store"))
        } catch {
            return XCTFail("Upgrade failed: \(error)")
        }
        let context = ModelContext(container)
        try ModelStore.upgradeData(in: context)
        let kid = try XCTUnwrap(try context.fetch(FetchDescriptor<Person>()).first)
        XCTAssertEqual(kid.therapies.first?.provider?.name, "Jane Smith")
        XCTAssertEqual(kid.communicationNeeds, "")
        XCTAssertEqual(kid.documents.count, 0)

        // The new records work on the upgraded database.
        let visit = Visit(reason: "Checkup")
        context.insert(visit)
        visit.person = kid
        visit.provider = kid.providers.first
        let document = HealthDocument(title: "Evaluation", kind: .diagnosticReport)
        context.insert(document)
        document.person = kid
        try context.save()
        XCTAssertEqual(kid.providers.first?.visits.map(\.reason), ["Checkup"])
        XCTAssertEqual(kid.documents.map(\.displayTitle), ["Evaluation"])
    }

    func testPhotosBecomeOnePDFAndItsTextCanBeRead() async throws {
        let pages = [UIColor.white, UIColor.lightGray].map { color in
            UIGraphicsImageRenderer(size: CGSize(width: 850, height: 1100)).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 850, height: 1100))
            }
        }
        let scanned = DocumentPDF.pdf(from: pages)
        XCTAssertEqual(DocumentPDF.pageCount(of: scanned), 2)
        XCTAssertNotNil(DocumentPDF.thumbnail(of: scanned))

        // An emailed report already holds its text.
        let report = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            ("Complete blood count: hemoglobin 12.9 g/dL" as NSString)
                .draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
        }
        let text = await DocumentPDF.text(of: report)
        XCTAssertTrue(text.contains("hemoglobin"), text)
    }

    func testSearchFindsRecordsDocumentTextAndSharedProvidersOnce() throws {
        let context = ModelContext(ModelStore.makeContainer(inMemory: true))
        let mom = Person(name: "Mom Example")
        let kid = Person(name: "Kid Example")
        context.insert(mom)
        context.insert(kid)
        let med = Medication(name: "Albuterol", dose: "90 mcg")
        context.insert(med)
        med.person = kid
        let doctor = Provider(name: "Dr. Rivera", specialty: "Pediatrics")
        context.insert(doctor)
        doctor.patients = [mom, kid]
        let report = HealthDocument(title: "Blood work", kind: .labResults)
        context.insert(report)
        report.recognizedText = "Patient: Kid Example\nFerritin 9 ng/mL (low)\nVitamin D 31"
        report.person = kid
        try context.save()

        let people = [mom, kid]
        XCTAssertEqual(FamilySearch.hits(for: "albuterol", in: people).map(\.title), ["Albuterol 90 mcg"])
        let ferritin = FamilySearch.hits(for: "ferritin low", in: people)
        XCTAssertEqual(ferritin.map(\.area), [.document])
        XCTAssertTrue(ferritin.first?.detail.contains("Ferritin 9") ?? false, ferritin.first?.detail ?? "")
        XCTAssertEqual(FamilySearch.hits(for: "rivera", in: people).count, 1, "A shared provider shows once")
        XCTAssertTrue(FamilySearch.hits(for: "  ", in: people).isEmpty)
        XCTAssertTrue(FamilySearch.hits(for: "zzz", in: people).isEmpty)
    }

    func testMedicarePlanTypesAndLegalDocumentsAreAvailable() {
        XCTAssertTrue(InsuranceKind.allCases.contains(.medigap))
        XCTAssertEqual(InsuranceKind(rawValue: "medical"), .medical, "Stored values from earlier versions still read")
        XCTAssertTrue(DocumentKind.advanceDirective.isLegal)
        XCTAssertFalse(DocumentKind.labResults.isLegal)
    }
}
