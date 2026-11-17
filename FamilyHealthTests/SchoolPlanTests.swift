import SwiftData
import XCTest
@testable import FamilyHealth

@MainActor
final class SchoolPlanTests: XCTestCase {
    func testUpgradingAVersionOnePointThreeDatabaseKeepsDocuments() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let oldFolder = folder.appendingPathComponent("v4", isDirectory: true)
        let newFolder = folder.appendingPathComponent("v5", isDirectory: true)
        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)

        // A database written by version 1.3, with a vaccine record kept as a document.
        try autoreleasepool {
            let schema = Schema(versionedSchema: SchemaV4.self)
            let configuration = ModelConfiguration(
                schema: schema, url: oldFolder.appendingPathComponent("FamilyHealth.store"), cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let kid = SchemaV4.Person(name: "Kid Example")
            context.insert(kid)
            kid.communicationNeeds = "Uses ASL"
            let record = SchemaV4.HealthDocument(title: "Shot record", kind: .vaccineRecord)
            context.insert(record)
            record.person = kid
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
        XCTAssertEqual(kid.communicationNeeds, "Uses ASL")
        XCTAssertEqual(kid.documents.map(\.displayTitle), ["Shot record"])
        XCTAssertEqual(kid.schoolPlan, .noPlan)

        kid.schoolPlan = .iep
        try context.save()
        XCTAssertEqual(kid.schoolPlan, .iep)
    }

    func testSchoolDetailsLinkToTheNewestPlanDocument() throws {
        let context = ModelContext(ModelStore.makeContainer(inMemory: true))
        let kid = Person(name: "Kid Example")
        context.insert(kid)
        XCTAssertFalse(kid.hasSchoolInfo)

        let older = HealthDocument(title: "IEP 2024", kind: .iep)
        older.date = Date(timeIntervalSince1970: 1_725_148_800) // 2024-09-01
        let newer = HealthDocument(title: "IEP 2025", kind: .iep)
        newer.date = Date(timeIntervalSince1970: 1_756_684_800) // 2025-09-01
        let other = HealthDocument(title: "504 plan", kind: .plan504)
        for document in [older, newer, other] {
            context.insert(document)
            document.person = kid
        }

        XCTAssertNil(kid.schoolPlanDocument, "No plan is active until one is chosen.")
        kid.schoolPlan = .iep
        XCTAssertTrue(kid.hasSchoolInfo)
        XCTAssertEqual(kid.schoolPlanDocument?.title, "IEP 2025")
        kid.schoolPlan = .plan504
        XCTAssertEqual(kid.schoolPlanDocument?.title, "504 plan")
        XCTAssertEqual(SchoolPlan.iep.activeLabel, "Active IEP")
        XCTAssertEqual(SchoolPlan.plan504.activeLabel, "Active 504 plan")
        XCTAssertEqual(SchoolPlan.noPlan.rawValue, "none")
    }

    func testIntakeSummaryAndBackupIncludeThePlan() throws {
        let context = ModelContext(ModelStore.makeContainer(inMemory: true))
        let kid = Person(name: "Kid Example")
        context.insert(kid)
        kid.schoolPlan = .iep
        let plan = HealthDocument(title: "IEP", kind: .iep)
        plan.date = Date(timeIntervalSince1970: 1_756_684_800) // 2025-09-01
        context.insert(plan)
        plan.person = kid
        try context.save()

        let school = try XCTUnwrap(IntakeSummary.sections(for: kid).first { $0.title == "School" })
        XCTAssertEqual(school.items.first { $0.label == "Support plan" }?.value, "Active IEP, dated \(plan.date!.formDate)")

        let archive = try BackupArchive(context: context)
        let target = ModelContext(ModelStore.makeContainer(inMemory: true))
        try archive.restore(into: target)
        let restored = try XCTUnwrap(try target.fetch(FetchDescriptor<Person>()).first)
        XCTAssertEqual(restored.schoolPlan, .iep)
        XCTAssertEqual(restored.schoolPlanDocument?.kind, .iep)
    }
}
