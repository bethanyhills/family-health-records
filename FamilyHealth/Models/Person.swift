import Foundation
import SwiftData

@Model
final class Person {
    var id: UUID = UUID()
    var name: String = ""
    var preferredName: String = ""
    var dateOfBirth: Date?
    var sexRaw: String = Sex.unspecified.rawValue
    var bloodTypeRaw: String = BloodType.unknown.rawValue
    var height: String = ""
    var weight: String = ""
    /// Replaced by `pharmacies` in 1.1; moved over by `ModelStore.upgradeData`.
    var preferredPharmacy: String = ""
    var notes: String = ""
    @Attribute(.externalStorage) var photoData: Data?
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Medication.person)
    var medications: [Medication] = []
    @Relationship(deleteRule: .cascade, inverse: \Allergy.person)
    var allergies: [Allergy] = []
    @Relationship(deleteRule: .cascade, inverse: \Condition.person)
    var conditions: [Condition] = []
    @Relationship(deleteRule: .cascade, inverse: \Procedure.person)
    var procedures: [Procedure] = []
    @Relationship(deleteRule: .cascade, inverse: \Immunization.person)
    var immunizations: [Immunization] = []
    @Relationship(deleteRule: .cascade, inverse: \FamilyHistoryItem.person)
    var familyHistory: [FamilyHistoryItem] = []
    /// 1.0 per-person contacts. Moved into `contacts` by `ModelStore.upgradeData`; not used by the UI.
    @Relationship(deleteRule: .cascade, inverse: \EmergencyContact.person)
    var emergencyContacts: [EmergencyContact] = []

    /// Providers and insurance policies are shared across family members.
    @Relationship(inverse: \Provider.patients)
    var providers: [Provider] = []
    @Relationship(inverse: \InsurancePolicy.members)
    var insurancePolicies: [InsurancePolicy] = []
    @Relationship(inverse: \Pharmacy.patients)
    var pharmacies: [Pharmacy] = []
    /// Emergency contacts, shared across family members (1.1).
    @Relationship(inverse: \EmergencyContact.people)
    var contacts: [EmergencyContact] = []

    init(name: String, dateOfBirth: Date? = nil, sortOrder: Int = 0) {
        self.name = name
        self.dateOfBirth = dateOfBirth
        self.sortOrder = sortOrder
    }

    var sex: Sex {
        get { Sex(rawValue: sexRaw) ?? .unspecified }
        set { sexRaw = newValue.rawValue }
    }

    var bloodType: BloodType {
        get { BloodType(rawValue: bloodTypeRaw) ?? .unknown }
        set { bloodTypeRaw = newValue.rawValue }
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Unnamed" : name
    }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var age: Int? {
        dateOfBirth.map { Person.age(bornOn: $0) }
    }

    static func age(bornOn birth: Date, on today: Date = .now, calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.year], from: birth, to: today).year ?? 0)
    }
}
