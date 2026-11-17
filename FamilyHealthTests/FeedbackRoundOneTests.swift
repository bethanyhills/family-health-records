import SwiftData
import XCTest
@testable import FamilyHealth

@MainActor
final class FeedbackRoundOneTests: XCTestCase {
    // MARK: Typed dates

    func testTypedDateAddsSlashesAndKeepsEightDigits() {
        XCTAssertEqual(TypedDate.format("0615"), "06/15")
        XCTAssertEqual(TypedDate.format("061520151"), "06/15/2015")
        XCTAssertEqual(TypedDate.format("06/15/2015"), "06/15/2015")
        XCTAssertEqual(TypedDate.format("a1b2"), "12")
    }

    func testTypedDateParsesOnlyRealDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let date = try XCTUnwrap(TypedDate.parse("06/15/2015", calendar: calendar))
        XCTAssertEqual(TypedDate.string(from: date, calendar: calendar), "06/15/2015")
        XCTAssertNil(TypedDate.parse("02/30/2015", calendar: calendar))
        XCTAssertNil(TypedDate.parse("13/01/2015", calendar: calendar))
        XCTAssertNil(TypedDate.parse("06/15/15", calendar: calendar))
        XCTAssertNotNil(TypedDate.parse("02/29/2016", calendar: calendar))
    }

    // MARK: Height and weight

    func testHeightReadsCommonFormats() {
        XCTAssertEqual(BodyMeasurement.parseHeight("5 ft 4 in").text, "5 ft 4 in")
        XCTAssertEqual(BodyMeasurement.parseHeight("5'4\"").text, "5 ft 4 in")
        XCTAssertEqual(BodyMeasurement.parseHeight("64 in").text, "5 ft 4 in")
        XCTAssertEqual(BodyMeasurement.parseHeight("163 cm").text, "163 cm")
        XCTAssertEqual(BodyMeasurement.parseHeight("5 ft 4 in").conversion, "163 cm")
    }

    func testWeightReadsCommonFormats() {
        XCTAssertEqual(BodyMeasurement.parseWeight("130 lbs").text, "130 lb")
        XCTAssertEqual(BodyMeasurement.parseWeight("59.5 kg").text, "59.5 kg")
        XCTAssertEqual(BodyMeasurement.parseWeight("130").text, "130 lb")
        XCTAssertEqual(BodyMeasurement.parseWeight("130 lb").conversion, "59 kg")
    }

    // MARK: Insurance card

    func testInsuranceCardParserReadsTypicalCard() {
        let lines = [
            "BlueCross BlueShield of Illinois",
            "PPO",
            "Subscriber Name",
            "JANE Q DOE",
            "Member ID: XOF123456789",
            "Group No. 012345",
            "RxBIN 004336",
            "RxPCN ADV",
            "RxGRP RX1234",
            "Member Services 1-800-555-0123",
        ]
        let result = InsuranceCardParser.parse(lines)
        XCTAssertEqual(result.carrier, "Blue Cross Blue Shield")
        XCTAssertEqual(result.subscriberName, "Jane Q Doe")
        XCTAssertEqual(result.memberID, "XOF123456789")
        XCTAssertEqual(result.groupNumber, "012345")
        XCTAssertEqual(result.rxBIN, "004336")
        XCTAssertEqual(result.rxPCN, "ADV")
        XCTAssertEqual(result.rxGroup, "RX1234")
        XCTAssertEqual(result.phone, "1-800-555-0123")
    }

    func testInsuranceCardParserHandlesValuesOnTheNextLine() {
        let lines = ["aetna", "ID", "W123456789", "GROUP", "0987654-010-00001"]
        let result = InsuranceCardParser.parse(lines)
        XCTAssertEqual(result.carrier, "Aetna")
        XCTAssertEqual(result.memberID, "W123456789")
        XCTAssertEqual(result.groupNumber, "0987654-010-00001")
    }

    func testInsuranceCardParserLeavesUnknownFieldsEmpty() {
        let result = InsuranceCardParser.parse(["Some unrelated text", "nothing here"])
        XCTAssertEqual(result.filledCount, 0)
    }

    // MARK: Database upgrade from 1.0

    func testUpgradingAVersionOneDatabaseKeepsRecords() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let oldFolder = folder.appendingPathComponent("v1", isDirectory: true)
        let newFolder = folder.appendingPathComponent("v2", isDirectory: true)
        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        let oldURL = oldFolder.appendingPathComponent("FamilyHealth.store")
        let url = newFolder.appendingPathComponent("FamilyHealth.store")

        // A database written by version 1.0.
        try autoreleasepool {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, url: oldURL, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let kid = SchemaV1.Person(name: "Kid Example")
            kid.preferredPharmacy = "Walgreens Naperville"
            let sibling = SchemaV1.Person(name: "Sib Example")
            sibling.preferredPharmacy = "walgreens naperville"
            context.insert(kid)
            context.insert(sibling)
            let contact = SchemaV1.EmergencyContact(name: "Grandma", relationship: "Grandmother", phone: "555-0111")
            context.insert(contact)
            contact.person = kid
            let med = SchemaV1.Medication(name: "Albuterol")
            context.insert(med)
            med.person = kid
            try context.save()
        }

        // Copy the saved files, as they would sit on the phone, so this version opens a file
        // that no other connection in this test process still has open.
        for name in try FileManager.default.contentsOfDirectory(atPath: oldFolder.path) {
            try FileManager.default.copyItem(
                at: oldFolder.appendingPathComponent(name),
                to: newFolder.appendingPathComponent(name)
            )
        }

        // Opened by this version. Throws (instead of crashing) so a failure shows its reason.
        let container: ModelContainer
        do {
            container = try ModelStore.openContainer(url: url)
        } catch {
            return XCTFail("Upgrade failed: \(error)")
        }
        let context = ModelContext(container)
        try ModelStore.upgradeData(in: context)
        let people = try context.fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.name)]))
        XCTAssertEqual(people.map(\.name), ["Kid Example", "Sib Example"])
        let kid = people[0]
        XCTAssertEqual(kid.medications.map(\.name), ["Albuterol"])
        XCTAssertEqual(kid.contacts.map(\.name), ["Grandma"])
        XCTAssertEqual(kid.pharmacies.map(\.name), ["Walgreens Naperville"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Pharmacy>()), 1, "Same pharmacy typed twice becomes one")
        XCTAssertEqual(people[1].pharmacies.first?.id, kid.pharmacies.first?.id)
        XCTAssertEqual(kid.preferredPharmacy, "")
    }

    func testUpgradingAVersionOnePointOneDatabaseKeepsRecords() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let oldFolder = folder.appendingPathComponent("v2", isDirectory: true)
        let newFolder = folder.appendingPathComponent("v3", isDirectory: true)
        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)

        // A database written by version 1.1.
        try autoreleasepool {
            let schema = Schema(versionedSchema: SchemaV2.self)
            let configuration = ModelConfiguration(
                schema: schema, url: oldFolder.appendingPathComponent("FamilyHealth.store"), cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let kid = SchemaV2.Person(name: "Kid Example")
            context.insert(kid)
            let ot = SchemaV2.Provider(name: "Jane Smith", specialty: "OT")
            context.insert(ot)
            ot.patients = [kid]
            let school = SchemaV2.School(name: "Maple Elementary")
            context.insert(school)
            school.students = [kid]
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
        XCTAssertEqual(kid.providers.map(\.name), ["Jane Smith"])
        XCTAssertEqual(kid.school?.name, "Maple Elementary")
        XCTAssertEqual(kid.therapies.count, 0)

        // The new therapies work on the upgraded database.
        let therapy = Therapy(kind: .speech)
        context.insert(therapy)
        therapy.person = kid
        therapy.provider = kid.providers.first
        try context.save()
        XCTAssertEqual(kid.providers.first?.therapies.map(\.displayName), ["Speech therapy"])
    }

    // MARK: School grade

    func testSchoolGradeListIsInOrderAndKeepsOldTypedGrades() {
        XCTAssertEqual(Array(SchoolGrade.all.prefix(5)), ["Preschool", "Pre-K", "Kindergarten", "1st grade", "2nd grade"])
        XCTAssertTrue(SchoolGrade.all.contains("3rd grade"))
        XCTAssertTrue(SchoolGrade.all.contains("11th grade"))
        XCTAssertTrue(SchoolGrade.all.contains("12th grade"))
        XCTAssertEqual(SchoolGrade.options(keeping: "3rd grade"), SchoolGrade.all)
        XCTAssertEqual(SchoolGrade.options(keeping: ""), SchoolGrade.all)
        XCTAssertEqual(SchoolGrade.options(keeping: "3rd").first, "3rd")
    }

    // MARK: Business card

    func testBusinessCardParserReadsTherapistCard() {
        let lines = [
            "Little Steps Pediatric Therapy",
            "Jane Smith, MS, OTR/L",
            "Pediatric Occupational Therapist",
            "1200 Main Street, Suite 4",
            "Naperville, IL 60540",
            "Office: (630) 555-0101",
            "Fax: (630) 555-0102",
            "jsmith@littlestepstherapy.com",
            "www.littlestepstherapy.com",
        ]
        let result = BusinessCardParser.parse(lines)
        XCTAssertEqual(result.name, "Jane Smith, MS, OTR/L")
        XCTAssertEqual(result.specialty, "Pediatric Occupational Therapist")
        XCTAssertEqual(result.practice, "Little Steps Pediatric Therapy")
        XCTAssertEqual(result.phone, "(630) 555-0101")
        XCTAssertEqual(result.fax, "(630) 555-0102")
        XCTAssertEqual(result.email, "jsmith@littlestepstherapy.com")
        XCTAssertTrue(result.website.contains("littlestepstherapy.com"))
        XCTAssertTrue(result.address.contains("1200 Main Street"), result.address)
    }

    func testBusinessCardParserUsesCredentialForSpecialtyWhenNoTitle() {
        let result = BusinessCardParser.parse(["Bright Voices Speech Clinic", "Alex Rivera, CCC-SLP", "555-201-3344"])
        XCTAssertEqual(result.name, "Alex Rivera, CCC-SLP")
        XCTAssertEqual(result.specialty, "Speech therapy")
        XCTAssertEqual(result.practice, "Bright Voices Speech Clinic")
        XCTAssertEqual(result.phone, "555-201-3344")
    }
}
