import Foundation
import SwiftData

// Frozen copy of the version 1.5 database models, exactly as they shipped.
// Do not edit: SwiftData compares this against databases created by 1.5 so it
// can upgrade them. Make model changes in the top-level classes and add a
// new schema version instead.
enum SchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 5, 0)

    static var models: [any PersistentModel.Type] {
        [
            Person.self,
            Medication.self,
            Allergy.self,
            Condition.self,
            Procedure.self,
            Immunization.self,
            FamilyHistoryItem.self,
            EmergencyContact.self,
            Provider.self,
            InsurancePolicy.self,
            Pharmacy.self,
            School.self,
            Therapy.self,
            HealthDocument.self,
            Visit.self,
        ]
    }

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
        /// School year details for this child (1.1). The school itself is shared.
        var schoolGrade: String = ""
        var teacherName: String = ""
        var teacherEmail: String = ""
        var teacherPhone: String = ""
        /// How this person communicates with providers (1.3), e.g. "Deaf, uses ASL, needs an interpreter".
        var communicationNeeds: String = ""
        /// An active 504 plan or IEP at school (1.4). The plan itself is kept in Documents.
        var schoolPlanRaw: String = SchoolPlan.noPlan.rawValue
        /// Digits only (1.5). Shown masked; see `SocialSecurityNumber`.
        var socialSecurityNumber: String = ""
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
        @Relationship(deleteRule: .cascade, inverse: \Therapy.person)
        var therapies: [Therapy] = []
        @Relationship(deleteRule: .cascade, inverse: \HealthDocument.person)
        var documents: [HealthDocument] = []
        @Relationship(deleteRule: .cascade, inverse: \Visit.person)
        var visits: [Visit] = []
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
        @Relationship(inverse: \School.students)
        var schools: [School] = []
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

        var school: School? { schools.first }

        var schoolPlan: SchoolPlan {
            get { SchoolPlan(rawValue: schoolPlanRaw) ?? .noPlan }
            set { schoolPlanRaw = newValue.rawValue }
        }

        /// The newest document for the active plan, which the school section links to.
        var schoolPlanDocument: HealthDocument? {
            guard let kind = schoolPlan.documentKind else { return nil }
            return documents
                .filter { $0.kind == kind }
                .max { ($0.date ?? $0.createdAt) < ($1.date ?? $1.createdAt) }
        }

        var hasSchoolInfo: Bool {
            school != nil || !schoolGrade.isBlank || !teacherName.isBlank || schoolPlan != .noPlan
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

    @Model
    final class Medication {
        var id: UUID = UUID()
        var name: String = ""
        var dose: String = ""
        var frequency: String = ""
        var reason: String = ""
        var prescriber: String = ""
        var pharmacy: String = ""
        var startDate: Date?
        var endDate: Date?
        var isActive: Bool = true
        var notes: String = ""
        var person: Person?

        init(name: String, dose: String = "", frequency: String = "", isActive: Bool = true) {
            self.name = name
            self.dose = dose
            self.frequency = frequency
            self.isActive = isActive
        }
    }

    @Model
    final class Allergy {
        var id: UUID = UUID()
        var allergen: String = ""
        var kindRaw: String = AllergyKind.medication.rawValue
        var reaction: String = ""
        var severityRaw: String = AllergySeverity.unknown.rawValue
        var notes: String = ""
        var person: Person?

        init(allergen: String, kind: AllergyKind = .medication, reaction: String = "", severity: AllergySeverity = .unknown) {
            self.allergen = allergen
            self.kindRaw = kind.rawValue
            self.reaction = reaction
            self.severityRaw = severity.rawValue
        }

        var kind: AllergyKind {
            get { AllergyKind(rawValue: kindRaw) ?? .other }
            set { kindRaw = newValue.rawValue }
        }

        var severity: AllergySeverity {
            get { AllergySeverity(rawValue: severityRaw) ?? .unknown }
            set { severityRaw = newValue.rawValue }
        }
    }

    @Model
    final class Condition {
        var id: UUID = UUID()
        var name: String = ""
        var diagnosedDate: Date?
        var statusRaw: String = ConditionStatus.active.rawValue
        var treatingProvider: String = ""
        var notes: String = ""
        var person: Person?

        init(name: String, status: ConditionStatus = .active, diagnosedDate: Date? = nil) {
            self.name = name
            self.statusRaw = status.rawValue
            self.diagnosedDate = diagnosedDate
        }

        var status: ConditionStatus {
            get { ConditionStatus(rawValue: statusRaw) ?? .active }
            set { statusRaw = newValue.rawValue }
        }
    }

    /// Surgeries, procedures and hospital stays.
    @Model
    final class Procedure {
        var id: UUID = UUID()
        var name: String = ""
        var date: Date?
        var facility: String = ""
        var surgeon: String = ""
        var notes: String = ""
        var person: Person?

        init(name: String, date: Date? = nil) {
            self.name = name
            self.date = date
        }
    }

    @Model
    final class Immunization {
        var id: UUID = UUID()
        var vaccine: String = ""
        var date: Date?
        var doseNumber: String = ""
        var location: String = ""
        var lotNumber: String = ""
        var notes: String = ""
        var person: Person?

        init(vaccine: String, date: Date? = nil, doseNumber: String = "") {
            self.vaccine = vaccine
            self.date = date
            self.doseNumber = doseNumber
        }
    }

    /// "Does anyone in your family have...": one relative and one condition per item.
    @Model
    final class FamilyHistoryItem {
        var id: UUID = UUID()
        var relative: String = ""
        var condition: String = ""
        var notes: String = ""
        var person: Person?

        init(relative: String, condition: String) {
            self.relative = relative
            self.condition = condition
        }
    }

    @Model
    final class EmergencyContact {
        var id: UUID = UUID()
        var name: String = ""
        var relationship: String = ""
        var phone: String = ""
        var notes: String = ""
        /// 1.0 owner; cleared by `ModelStore.upgradeData` once moved into `people`.
        var person: Person?
        /// The family members this person is an emergency contact for (1.1).
        var people: [Person] = []

        init(name: String, relationship: String = "", phone: String = "") {
            self.name = name
            self.relationship = relationship
            self.phone = phone
        }
    }

    /// A doctor, therapist, dentist or clinic. One provider can see several family members.
    @Model
    final class Provider {
        var id: UUID = UUID()
        var name: String = ""
        var specialty: String = ""
        var practice: String = ""
        var phone: String = ""
        var fax: String = ""
        var address: String = ""
        var portalURL: String = ""
        var notes: String = ""
        var patients: [Person] = []
        /// Therapies this provider gives (1.2). Deleting the provider keeps the therapy.
        @Relationship(deleteRule: .nullify, inverse: \Therapy.provider)
        var therapies: [Therapy] = []
        /// Visits with and documents from this provider (1.3). Deleting the provider keeps them.
        @Relationship(deleteRule: .nullify, inverse: \Visit.provider)
        var visits: [Visit] = []
        @Relationship(deleteRule: .nullify, inverse: \HealthDocument.provider)
        var documents: [HealthDocument] = []

        init(name: String, specialty: String = "") {
            self.name = name
            self.specialty = specialty
        }
    }

    /// An insurance policy. A family plan covers several family members.
    @Model
    final class InsurancePolicy {
        var id: UUID = UUID()
        var kindRaw: String = InsuranceKind.medical.rawValue
        var carrier: String = ""
        var planName: String = ""
        var memberID: String = ""
        var groupNumber: String = ""
        var subscriberName: String = ""
        var subscriberDateOfBirth: Date?
        var phone: String = ""
        var rxBIN: String = ""
        var rxPCN: String = ""
        var rxGroup: String = ""
        var notes: String = ""
        @Attribute(.externalStorage) var cardFrontImage: Data?
        @Attribute(.externalStorage) var cardBackImage: Data?
        var members: [Person] = []

        init(carrier: String, kind: InsuranceKind = .medical) {
            self.carrier = carrier
            self.kindRaw = kind.rawValue
        }

        var kind: InsuranceKind {
            get { InsuranceKind(rawValue: kindRaw) ?? .other }
            set { kindRaw = newValue.rawValue }
        }
    }

    /// A pharmacy. Usually shared by the whole family.
    @Model
    final class Pharmacy {
        var id: UUID = UUID()
        var name: String = ""
        var phone: String = ""
        var address: String = ""
        var latitude: Double?
        var longitude: Double?
        var notes: String = ""
        var patients: [Person] = []

        init(name: String, phone: String = "", address: String = "") {
            self.name = name
            self.phone = phone
            self.address = address
        }
    }

    /// A school, shared by siblings. Each child's grade and teacher live on `Person`.
    @Model
    final class School {
        var id: UUID = UUID()
        var name: String = ""
        var address: String = ""
        var phone: String = ""
        var nurseName: String = ""
        var nursePhone: String = ""
        var nurseEmail: String = ""
        var notes: String = ""
        var students: [Person] = []

        init(name: String) {
            self.name = name
        }
    }

    /// A therapy a family member receives, such as OT, speech or ABA (1.2).
    @Model
    final class Therapy {
        var id: UUID = UUID()
        var kindRaw: String = TherapyKind.occupational.rawValue
        /// The name to show for "Other", e.g. "Vision therapy".
        var customName: String = ""
        var frequency: String = ""
        var goals: String = ""
        var notes: String = ""
        var startDate: Date?
        var endDate: Date?
        var isActive: Bool = true
        var person: Person?
        var provider: Provider?

        init(kind: TherapyKind, isActive: Bool = true) {
            self.kindRaw = kind.rawValue
            self.isActive = isActive
        }

        var kind: TherapyKind {
            get { TherapyKind(rawValue: kindRaw) ?? .other }
            set { kindRaw = newValue.rawValue }
        }

        var displayName: String {
            kind == .other && !customName.isBlank ? customName.trimmed : kind.label
        }
    }

    /// A lab report, diagnostic report, letter or form, kept whole as a PDF (1.3).
    /// Scans and photos are turned into a PDF when added.
    @Model
    final class HealthDocument {
        var id: UUID = UUID()
        var title: String = ""
        var kindRaw: String = DocumentKind.other.rawValue
        var date: Date?
        var notes: String = ""
        /// Text read from the pages on the phone, so documents can be searched.
        var recognizedText: String = ""
        var pageCount: Int = 0
        @Attribute(.externalStorage) var pdfData: Data?
        var createdAt: Date = Date()
        var person: Person?
        var provider: Provider?

        init(title: String, kind: DocumentKind = .other, date: Date? = nil) {
            self.title = title
            self.kindRaw = kind.rawValue
            self.date = date
        }

        var kind: DocumentKind {
            get { DocumentKind(rawValue: kindRaw) ?? .other }
            set { kindRaw = newValue.rawValue }
        }

        var displayTitle: String {
            title.isBlank ? kind.label : title.trimmed
        }
    }

    /// Notes from an appointment: why they went, what was said, and what happens next (1.3).
    @Model
    final class Visit {
        var id: UUID = UUID()
        var date: Date?
        var reason: String = ""
        /// What the provider said, in Beth's words.
        var notes: String = ""
        var followUp: String = ""
        var followUpDate: Date?
        var createdAt: Date = Date()
        var person: Person?
        var provider: Provider?

        init(date: Date? = nil, reason: String = "") {
            self.date = date
            self.reason = reason
        }
    }
}
