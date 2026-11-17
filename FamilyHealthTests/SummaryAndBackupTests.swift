import SwiftData
import XCTest
@testable import FamilyHealth

@MainActor
final class SummaryAndBackupTests: XCTestCase {
    private func makeFamily(in context: ModelContext) -> (Person, Person) {
        let parent = Person(name: "Pat Example", sortOrder: 0)
        let child = Person(name: "Kid Example", sortOrder: 1)
        context.insert(parent)
        context.insert(child)
        child.dateOfBirth = Date(timeIntervalSince1970: 1_434_326_400) // 2015-06-15
        child.bloodType = .aPositive

        let allergy = Allergy(allergen: "Penicillin", kind: .medication, reaction: "Hives", severity: .severe)
        context.insert(allergy)
        allergy.person = child

        let current = Medication(name: "Albuterol", dose: "90 mcg", frequency: "as needed")
        let past = Medication(name: "Amoxicillin", dose: "250 mg", isActive: false)
        context.insert(current)
        context.insert(past)
        current.reason = "asthma"
        current.person = child
        past.person = child
        past.reason = "ear infection"
        past.startDate = TypedDate.parse("03/01/2021")
        past.endDate = TypedDate.parse("03/11/2021")

        let condition = Condition(name: "Asthma", status: .managed)
        context.insert(condition)
        condition.person = child

        let contact = EmergencyContact(name: "Pat Example", relationship: "Parent", phone: "555-0100")
        context.insert(contact)
        contact.people = [child]

        let pharmacy = Pharmacy(name: "Walgreens", phone: "555-0199", address: "1 Main St")
        context.insert(pharmacy)
        pharmacy.patients = [parent, child]

        let school = School(name: "Maple Elementary")
        context.insert(school)
        school.nurseName = "Nurse Lee"
        school.nursePhone = "555-0177"
        school.students = [child]
        child.schoolGrade = "3rd grade"
        child.teacherName = "Ms. Park"

        let provider = Provider(name: "Dr. Rivera", specialty: "Pediatrics")
        context.insert(provider)
        provider.patients = [parent, child]

        let ot = Provider(name: "Jane Smith, OTR/L", specialty: "Occupational therapy")
        context.insert(ot)
        ot.practice = "Little Steps"
        ot.patients = [child]
        let therapy = Therapy(kind: .occupational)
        context.insert(therapy)
        therapy.frequency = "Weekly"
        therapy.goals = "Handwriting"
        therapy.person = child
        therapy.provider = ot
        let pastTherapy = Therapy(kind: .other, isActive: false)
        context.insert(pastTherapy)
        pastTherapy.customName = "Vision therapy"
        pastTherapy.person = child

        let policy = InsurancePolicy(carrier: "Example Health")
        context.insert(policy)
        policy.memberID = "XYZ123"
        policy.cardFrontImage = Data([1, 2, 3])
        policy.members = [parent, child]
        return (parent, child)
    }

    func testSummaryListsOnlyCurrentMedicationsAndFormatsAllergies() throws {
        let context = ModelContext(ModelStore.makeContainer(inMemory: true))
        let (_, child) = makeFamily(in: context)
        try context.save()

        let sections = IntakeSummary.sections(for: child)
        let meds = try XCTUnwrap(sections.first { $0.title == "Current medications" })
        XCTAssertEqual(meds.items.map(\.label), ["Albuterol 90 mcg"])
        XCTAssertEqual(meds.items.first?.value, "as needed, for asthma")

        let allergies = try XCTUnwrap(sections.first { $0.title == "Allergies" })
        XCTAssertEqual(allergies.items.first?.label, "Penicillin")
        XCTAssertEqual(allergies.items.first?.value, "Hives (severe)")

        XCTAssertFalse(sections.contains { $0.title == "Past conditions" }, "Empty past conditions are hidden")
        let therapies = try XCTUnwrap(sections.first { $0.title == "Current therapies" })
        XCTAssertEqual(therapies.items.map(\.label), ["Occupational therapy (OT)"])
        XCTAssertEqual(therapies.items.first?.value, "Jane Smith, OTR/L, Little Steps; Weekly")
        let pastTherapies = try XCTUnwrap(sections.first { $0.title == "Past therapies" })
        XCTAssertEqual(pastTherapies.items.map(\.label), ["Vision therapy"])
        let pastMeds = try XCTUnwrap(sections.first { $0.title == "Past medications" })
        XCTAssertEqual(pastMeds.items.map(\.label), ["Amoxicillin 250 mg"])
        XCTAssertEqual(pastMeds.items.first?.value, "for ear infection, 03/01/2021 to 03/11/2021")
        let titles = sections.map(\.title)
        XCTAssertEqual(titles.firstIndex(of: "Past medications"), titles.firstIndex(of: "Current medications").map { $0 + 1 })
        XCTAssertTrue(IntakeSummary.text(for: child).contains("Member ID: XYZ123"))
        XCTAssertTrue(IntakeSummary.text(for: child).contains("Walgreens: 1 Main St, 555-0199"))
        XCTAssertTrue(IntakeSummary.text(for: child).contains("Pat Example: Parent, 555-0100"))
        XCTAssertTrue(IntakeSummary.text(for: child).contains("School nurse: Nurse Lee, 555-0177"))
        XCTAssertFalse(IntakeSummary.sections(for: Person(name: "No School")).contains { $0.title == "School" },
                       "A person with no school details has no School section")
    }

    func testSummaryItemIDsAreStable() {
        let context = ModelContext(ModelStore.makeContainer(inMemory: true))
        let (_, child) = makeFamily(in: context)
        XCTAssertEqual(IntakeSummary.sections(for: child), IntakeSummary.sections(for: child))
    }

    func testPDFIsGenerated() {
        let context = ModelContext(ModelStore.makeContainer(inMemory: true))
        let (_, child) = makeFamily(in: context)
        let data = SummaryPDF.data(name: child.displayName, sections: IntakeSummary.sections(for: child))
        XCTAssertGreaterThan(data.count, 1000)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "%PDF")
    }

    func testHTMLIsEscaped() {
        XCTAssertEqual(SummaryPDF.escape("<b>&\"x\""), "&lt;b&gt;&amp;&quot;x&quot;")
    }

    func testBackupRoundTripRestoresEverything() throws {
        let source = ModelContext(ModelStore.makeContainer(inMemory: true))
        _ = makeFamily(in: source)
        try source.save()
        let archive = try BackupArchive(context: source)

        let file = try BackupCrypto.encrypt(archive, password: "correct horse", iterations: 1_000)
        let decrypted = try BackupCrypto.decrypt(file, password: "correct horse")
        XCTAssertEqual(decrypted, archive)

        let target = ModelContext(ModelStore.makeContainer(inMemory: true))
        target.insert(Person(name: "Someone To Replace"))
        try target.save()
        try decrypted.restore(into: target)

        let people = try target.fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.sortOrder)]))
        XCTAssertEqual(people.map(\.name), ["Pat Example", "Kid Example"])
        let child = people[1]
        XCTAssertEqual(child.bloodType, .aPositive)
        XCTAssertEqual(child.allergies.first?.severity, .severe)
        XCTAssertEqual(child.medications.count, 2)
        XCTAssertEqual(child.providers.map(\.name).sorted(), ["Dr. Rivera", "Jane Smith, OTR/L"])
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<Provider>()), 2)
        let ot = try XCTUnwrap(child.therapies.first { $0.kind == .occupational })
        XCTAssertEqual(ot.provider?.name, "Jane Smith, OTR/L")
        XCTAssertEqual(ot.goals, "Handwriting")
        XCTAssertEqual(child.therapies.first { !$0.isActive }?.displayName, "Vision therapy")
        XCTAssertEqual(child.insurancePolicies.first?.cardFrontImage, Data([1, 2, 3]))
        XCTAssertEqual(child.insurancePolicies.first?.members.count, 2)
        XCTAssertEqual(child.pharmacies.map(\.name), ["Walgreens"])
        XCTAssertEqual(child.contacts.map(\.name), ["Pat Example"])
        let restored = try BackupArchive(context: target)
        XCTAssertEqual(restored.people, archive.people)
        XCTAssertEqual(restored.pharmacies, archive.pharmacies)
        XCTAssertEqual(restored.contacts, archive.contacts)
        XCTAssertEqual(restored.schools, archive.schools)
        XCTAssertEqual(child.school?.name, "Maple Elementary")
        XCTAssertEqual(child.teacherName, "Ms. Park")
    }

    func testBackupRejectsWrongPasswordAndOtherFiles() throws {
        let archive = BackupArchive()
        let file = try BackupCrypto.encrypt(archive, password: "correct horse", iterations: 1_000)

        XCTAssertThrowsError(try BackupCrypto.decrypt(file, password: "wrong password")) { error in
            XCTAssertEqual(error as? BackupCrypto.Failure, .wrongPassword)
        }
        XCTAssertThrowsError(try BackupCrypto.decrypt(Data("{}".utf8), password: "correct horse")) { error in
            XCTAssertEqual(error as? BackupCrypto.Failure, .notABackup)
        }
        XCTAssertThrowsError(try BackupCrypto.encrypt(archive, password: "short")) { error in
            XCTAssertEqual(error as? BackupCrypto.Failure, .passwordTooShort)
        }
    }

    func testBackupFileDoesNotContainPlaintext() throws {
        let context = ModelContext(ModelStore.makeContainer(inMemory: true))
        _ = makeFamily(in: context)
        let file = try BackupCrypto.encrypt(try BackupArchive(context: context), password: "correct horse", iterations: 1_000)
        XCTAssertFalse(String(decoding: file, as: UTF8.self).contains("Penicillin"))
    }

    func testBackupReminderIsDueAfterThirtyDays() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertTrue(BackupStatus.isDue(lastBackupAt: 0, now: now))
        XCTAssertFalse(BackupStatus.isDue(lastBackupAt: now.timeIntervalSince1970 - 86_400, now: now))
        XCTAssertTrue(BackupStatus.isDue(lastBackupAt: now.timeIntervalSince1970 - 31 * 86_400, now: now))
    }

    func testVersionOneBackupRestoresContactsAndPharmacy() throws {
        var archive = BackupArchive()
        archive.version = 1
        archive.pharmacies = nil
        archive.contacts = nil
        let id = UUID()
        archive.people = [BackupArchive.PersonRecord(
            id: id, name: "Kid Example", preferredName: "", dateOfBirth: nil, sex: "unspecified",
            bloodType: "unknown", height: "", weight: "", preferredPharmacy: "CVS Naperville", notes: "",
            photo: nil, sortOrder: 0, createdAt: .now, medications: [], allergies: [], conditions: [],
            procedures: [], immunizations: [], familyHistory: [],
            emergencyContacts: [.init(name: "Grandma", relationship: "Grandmother", phone: "555-0111", notes: "")]
        )]
        let context = ModelContext(ModelStore.makeContainer(inMemory: true))
        try archive.restore(into: context)

        let person = try XCTUnwrap(try context.fetch(FetchDescriptor<Person>()).first)
        XCTAssertEqual(person.contacts.map(\.name), ["Grandma"])
        XCTAssertEqual(person.pharmacies.map(\.name), ["CVS Naperville"])
        XCTAssertEqual(person.preferredPharmacy, "")
    }
}
