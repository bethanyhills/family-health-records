import Foundation
import SwiftData

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
    var person: Person?

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
