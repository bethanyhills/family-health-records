import SwiftData
import XCTest
@testable import FamilyHealth

@MainActor
final class ProfileUpdateTests: XCTestCase {
    func testSocialSecurityNumberFormatting() {
        XCTAssertEqual(SocialSecurityNumber.digits("123-45-6789 "), "123456789")
        XCTAssertEqual(SocialSecurityNumber.digits("1234567890"), "123456789", "Extra digits are dropped.")
        XCTAssertEqual(SocialSecurityNumber.formatted("12345"), "123-45")
        XCTAssertEqual(SocialSecurityNumber.formatted("123456789"), "123-45-6789")
        XCTAssertEqual(SocialSecurityNumber.masked("123456789"), "•••-••-6789")
        XCTAssertEqual(SocialSecurityNumber.masked("1234"), "•••-••-••••")
        XCTAssertEqual(SocialSecurityNumber.masked(""), "")
        XCTAssertTrue(SocialSecurityNumber.isComplete("123-45-6789"))
        XCTAssertFalse(SocialSecurityNumber.isComplete("123-45"))
    }

    func testIntakeSummaryMasksTheNumberButCopiesItWhole() throws {
        let context = ModelContext(ModelStore.makeContainer(inMemory: true))
        let kid = Person(name: "Kid Example")
        context.insert(kid)
        kid.socialSecurityNumber = "123456789"

        let patient = try XCTUnwrap(IntakeSummary.sections(for: kid).first { $0.title == "Patient" })
        let row = try XCTUnwrap(patient.items.first { $0.label == "Social Security number" })
        XCTAssertEqual(row.value, "•••-••-6789")
        XCTAssertEqual(row.copyValue, "123-45-6789")
        let text = IntakeSummary.text(for: kid)
        XCTAssertTrue(text.contains("Social Security number: •••-••-6789"))
        XCTAssertFalse(text.contains("123-45-6789"), "Copy all and the PDF show only the last 4.")

        kid.socialSecurityNumber = ""
        let empty = try XCTUnwrap(IntakeSummary.sections(for: kid).first { $0.title == "Patient" })
        XCTAssertFalse(empty.items.contains { $0.label == "Social Security number" })
    }

    func testBackupKeepsTheNumber() throws {
        let context = ModelContext(ModelStore.makeContainer(inMemory: true))
        let kid = Person(name: "Kid Example")
        context.insert(kid)
        kid.socialSecurityNumber = "123456789"
        try context.save()

        let archive = try BackupArchive(context: context)
        XCTAssertEqual(archive.version, 7)
        let target = ModelContext(ModelStore.makeContainer(inMemory: true))
        try archive.restore(into: target)
        let restored = try XCTUnwrap(try target.fetch(FetchDescriptor<Person>()).first)
        XCTAssertEqual(restored.socialSecurityNumber, "123456789")
    }

    func testFamilyTitle() {
        XCTAssertEqual(FamilyTitle.display(""), "My Family")
        XCTAssertEqual(FamilyTitle.display("   "), "My Family")
        XCTAssertEqual(FamilyTitle.display(" Hills Family "), "Hills Family")
    }

    func testUpgradingAVersionOnePointFourDatabaseKeepsSchoolPlans() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let oldFolder = folder.appendingPathComponent("v5", isDirectory: true)
        let newFolder = folder.appendingPathComponent("v6", isDirectory: true)
        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)

        try autoreleasepool {
            let schema = Schema(versionedSchema: SchemaV5.self)
            let configuration = ModelConfiguration(
                schema: schema, url: oldFolder.appendingPathComponent("FamilyHealth.store"), cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let kid = SchemaV5.Person(name: "Kid Example")
            context.insert(kid)
            kid.schoolPlanRaw = SchoolPlan.iep.rawValue
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
        XCTAssertEqual(kid.schoolPlan, .iep)
        XCTAssertEqual(kid.socialSecurityNumber, "")
    }
}
