import SwiftData
import XCTest
@testable import FamilyHealth

@MainActor
final class ModelTests: XCTestCase {
    private func makeContext() -> ModelContext {
        ModelContext(ModelStore.makeContainer(inMemory: true))
    }

    func testDeletingAPersonRemovesTheirOwnRecords() throws {
        let context = makeContext()
        let person = Person(name: "Sam Example")
        context.insert(person)

        let medication = Medication(name: "Amoxicillin", dose: "250 mg", frequency: "Twice daily")
        let allergy = Allergy(allergen: "Penicillin", kind: .medication, reaction: "Hives", severity: .moderate)
        let contact = EmergencyContact(name: "Alex Example", relationship: "Parent", phone: "555-0100")
        context.insert(medication)
        context.insert(allergy)
        context.insert(contact)
        medication.person = person
        allergy.person = person
        contact.person = person
        try context.save()

        XCTAssertEqual(person.medications.count, 1)
        XCTAssertEqual(person.allergies.count, 1)
        XCTAssertEqual(person.emergencyContacts.count, 1)

        context.delete(person)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Medication>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Allergy>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EmergencyContact>()), 0)
    }

    func testSharedProviderAndInsuranceSurviveDeletingOneFamilyMember() throws {
        let context = makeContext()
        let parent = Person(name: "Pat Example")
        let child = Person(name: "Kid Example")
        let pediatrician = Provider(name: "Dr. Rivera", specialty: "Pediatrics")
        let policy = InsurancePolicy(carrier: "Example Health", kind: .medical)
        [parent, child].forEach { context.insert($0) }
        context.insert(pediatrician)
        context.insert(policy)

        pediatrician.patients = [parent, child]
        policy.members = [parent, child]
        try context.save()

        XCTAssertEqual(child.providers.map(\.name), ["Dr. Rivera"])
        XCTAssertEqual(parent.insurancePolicies.count, 1)

        context.delete(child)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Provider>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InsurancePolicy>()), 1)
        XCTAssertEqual(pediatrician.patients.map(\.name), ["Pat Example"])
        XCTAssertEqual(policy.members.map(\.name), ["Pat Example"])
    }

    func testAgeCountsWholeYears() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let birth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2015, month: 6, day: 15)))
        let dayBefore = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 6, day: 14)))
        let birthday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 6, day: 15)))

        XCTAssertEqual(Person.age(bornOn: birth, on: dayBefore, calendar: calendar), 9)
        XCTAssertEqual(Person.age(bornOn: birth, on: birthday, calendar: calendar), 10)
    }

    func testChoicesFallBackWhenStoredValueIsUnknown() {
        let person = Person(name: "Sam Example")
        person.bloodTypeRaw = "not-a-blood-type"
        XCTAssertEqual(person.bloodType, .unknown)

        person.bloodType = .oNegative
        XCTAssertEqual(person.bloodTypeRaw, "O-")

        let allergy = Allergy(allergen: "Peanuts", kind: .food, severity: .severe)
        XCTAssertEqual(allergy.kind, .food)
        XCTAssertEqual(allergy.severity, .severe)
    }

    func testInitialsUseFirstTwoNames() {
        XCTAssertEqual(Person(name: "mary jane watson").initials, "MJ")
        XCTAssertEqual(Person(name: "  ").displayName, "Unnamed")
    }
}
