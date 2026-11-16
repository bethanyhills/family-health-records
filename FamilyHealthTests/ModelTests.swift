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
        contact.people = [person]
        try context.save()

        XCTAssertEqual(person.medications.count, 1)
        XCTAssertEqual(person.allergies.count, 1)
        XCTAssertEqual(person.contacts.count, 1)

        context.delete(person)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Medication>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Allergy>()), 0)
        // Shared contacts stay (they may cover other family members) but lose this person.
        XCTAssertEqual(contact.people.count, 0)
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

    func testUnusedSharedRecordsAreRemovedButSharedOnesStay() throws {
        let context = makeContext()
        let mom = Person(name: "Mom Example")
        let kid = Person(name: "Kid Example")
        context.insert(mom)
        context.insert(kid)
        let oldCard = InsurancePolicy(carrier: "Old Carrier")
        let familyCard = InsurancePolicy(carrier: "Family Carrier")
        let pediatrician = Provider(name: "Dr. Example")
        let school = School(name: "Maple Elementary")
        context.insert(oldCard)
        context.insert(familyCard)
        context.insert(pediatrician)
        context.insert(school)
        oldCard.members = [kid]
        familyCard.members = [mom, kid]
        pediatrician.patients = [kid]
        kid.schools = [school]
        try context.save()

        // Remove the old card and the kid's school; drop the kid from the family card.
        oldCard.members.removeAll { $0.id == kid.id }
        familyCard.members.removeAll { $0.id == kid.id }
        kid.schools = []
        ModelStore.removeUnusedSharedRecords(in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<InsurancePolicy>()).map(\.carrier), ["Family Carrier"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<School>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Provider>()), 1, "Still the kid's doctor")
    }

    func testFamilyHistoryCopiesToOthersWithoutDuplicates() throws {
        let context = makeContext()
        let mom = Person(name: "Mom Example")
        let kid = Person(name: "Kid Example")
        let sib = Person(name: "Sib Example")
        [mom, kid, sib].forEach { context.insert($0) }
        let existing = FamilyHistoryItem(relative: "maternal grandmother", condition: "type 2 diabetes")
        context.insert(existing)
        existing.person = sib

        let item = FamilyHistoryItem(relative: "Maternal grandmother", condition: "Type 2 diabetes")
        item.notes = "Diagnosed at 50"
        context.insert(item)
        item.person = kid
        item.copy(to: [mom, sib], in: context)
        try context.save()

        XCTAssertEqual(mom.familyHistory.map(\.condition), ["Type 2 diabetes"])
        XCTAssertEqual(mom.familyHistory.first?.notes, "Diagnosed at 50")
        XCTAssertNotEqual(mom.familyHistory.first?.id, item.id, "Each person gets their own copy")
        XCTAssertEqual(sib.familyHistory.count, 1, "Sib already had it")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FamilyHistoryItem>()), 3)
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
