import Foundation
import SwiftData

/// A plain, versioned copy of every record, used for the encrypted backup file.
struct BackupArchive: Codable, Equatable {
    static let currentVersion = 2

    var version = BackupArchive.currentVersion
    var exportedAt = Date()
    var people: [PersonRecord] = []
    var providers: [ProviderRecord] = []
    var insurancePolicies: [InsuranceRecord] = []
    /// Added in version 2. Missing from version 1 backups.
    var pharmacies: [PharmacyRecord]? = []
    /// Added in version 2. Version 1 kept contacts inside each person.
    var contacts: [ContactRecord]? = []

    struct PersonRecord: Codable, Equatable {
        var id: UUID
        var name, preferredName: String
        var dateOfBirth: Date?
        var sex, bloodType, height, weight, preferredPharmacy, notes: String
        var photo: Data?
        var sortOrder: Int
        var createdAt: Date
        var medications: [MedicationRecord]
        var allergies: [AllergyRecord]
        var conditions: [ConditionRecord]
        var procedures: [ProcedureRecord]
        var immunizations: [ImmunizationRecord]
        var familyHistory: [FamilyHistoryRecord]
        /// Version 1 only; version 2 uses the shared `contacts` list.
        var emergencyContacts: [EmergencyContactRecord]
    }

    struct PharmacyRecord: Codable, Equatable {
        var name, phone, address, notes: String
        var latitude, longitude: Double?
        var patientIDs: [UUID]
    }

    struct ContactRecord: Codable, Equatable {
        var name, relationship, phone, notes: String
        var personIDs: [UUID]
    }

    struct MedicationRecord: Codable, Equatable {
        var name, dose, frequency, reason, prescriber, pharmacy, notes: String
        var startDate, endDate: Date?
        var isActive: Bool
    }

    struct AllergyRecord: Codable, Equatable {
        var allergen, kind, reaction, severity, notes: String
    }

    struct ConditionRecord: Codable, Equatable {
        var name, status, treatingProvider, notes: String
        var diagnosedDate: Date?
    }

    struct ProcedureRecord: Codable, Equatable {
        var name, facility, surgeon, notes: String
        var date: Date?
    }

    struct ImmunizationRecord: Codable, Equatable {
        var vaccine, doseNumber, location, lotNumber, notes: String
        var date: Date?
    }

    struct FamilyHistoryRecord: Codable, Equatable {
        var relative, condition, notes: String
    }

    struct EmergencyContactRecord: Codable, Equatable {
        var name, relationship, phone, notes: String
    }

    struct ProviderRecord: Codable, Equatable {
        var name, specialty, practice, phone, fax, address, portalURL, notes: String
        var patientIDs: [UUID]
    }

    struct InsuranceRecord: Codable, Equatable {
        var kind, carrier, planName, memberID, groupNumber, subscriberName, phone: String
        var subscriberDateOfBirth: Date?
        var rxBIN, rxPCN, rxGroup, notes: String
        var cardFront, cardBack: Data?
        var memberIDs: [UUID]
    }
}

extension BackupArchive {
    /// Copies everything in the database into an archive.
    init(context: ModelContext) throws {
        let people = try context.fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]))
        self.people = people.map { p in
            PersonRecord(
                id: p.id, name: p.name, preferredName: p.preferredName, dateOfBirth: p.dateOfBirth,
                sex: p.sexRaw, bloodType: p.bloodTypeRaw, height: p.height, weight: p.weight,
                preferredPharmacy: p.preferredPharmacy, notes: p.notes, photo: p.photoData,
                sortOrder: p.sortOrder, createdAt: p.createdAt,
                medications: p.medications.sorted { $0.name < $1.name }.map {
                    MedicationRecord(name: $0.name, dose: $0.dose, frequency: $0.frequency, reason: $0.reason,
                                     prescriber: $0.prescriber, pharmacy: $0.pharmacy, notes: $0.notes,
                                     startDate: $0.startDate, endDate: $0.endDate, isActive: $0.isActive)
                },
                allergies: p.allergies.sorted { $0.allergen < $1.allergen }.map {
                    AllergyRecord(allergen: $0.allergen, kind: $0.kindRaw, reaction: $0.reaction,
                                  severity: $0.severityRaw, notes: $0.notes)
                },
                conditions: p.conditions.sorted { $0.name < $1.name }.map {
                    ConditionRecord(name: $0.name, status: $0.statusRaw, treatingProvider: $0.treatingProvider,
                                    notes: $0.notes, diagnosedDate: $0.diagnosedDate)
                },
                procedures: p.procedures.sorted { $0.name < $1.name }.map {
                    ProcedureRecord(name: $0.name, facility: $0.facility, surgeon: $0.surgeon, notes: $0.notes, date: $0.date)
                },
                immunizations: p.immunizations.sorted { ($0.vaccine, $0.doseNumber) < ($1.vaccine, $1.doseNumber) }.map {
                    ImmunizationRecord(vaccine: $0.vaccine, doseNumber: $0.doseNumber, location: $0.location,
                                       lotNumber: $0.lotNumber, notes: $0.notes, date: $0.date)
                },
                familyHistory: p.familyHistory.sorted { ($0.condition, $0.relative) < ($1.condition, $1.relative) }.map {
                    FamilyHistoryRecord(relative: $0.relative, condition: $0.condition, notes: $0.notes)
                },
                emergencyContacts: []
            )
        }
        providers = try context.fetch(FetchDescriptor<Provider>(sortBy: [SortDescriptor(\.name)])).map {
            ProviderRecord(name: $0.name, specialty: $0.specialty, practice: $0.practice, phone: $0.phone,
                           fax: $0.fax, address: $0.address, portalURL: $0.portalURL, notes: $0.notes,
                           patientIDs: $0.patients.map(\.id).sorted { $0.uuidString < $1.uuidString })
        }
        pharmacies = try context.fetch(FetchDescriptor<Pharmacy>(sortBy: [SortDescriptor(\.name)])).map {
            PharmacyRecord(name: $0.name, phone: $0.phone, address: $0.address, notes: $0.notes,
                           latitude: $0.latitude, longitude: $0.longitude,
                           patientIDs: $0.patients.map(\.id).sorted { $0.uuidString < $1.uuidString })
        }
        contacts = try context.fetch(FetchDescriptor<EmergencyContact>(sortBy: [SortDescriptor(\.name)])).map {
            ContactRecord(name: $0.name, relationship: $0.relationship, phone: $0.phone, notes: $0.notes,
                          personIDs: $0.people.map(\.id).sorted { $0.uuidString < $1.uuidString })
        }
        insurancePolicies = try context.fetch(FetchDescriptor<InsurancePolicy>(sortBy: [SortDescriptor(\.carrier)])).map {
            InsuranceRecord(kind: $0.kindRaw, carrier: $0.carrier, planName: $0.planName, memberID: $0.memberID,
                            groupNumber: $0.groupNumber, subscriberName: $0.subscriberName, phone: $0.phone,
                            subscriberDateOfBirth: $0.subscriberDateOfBirth, rxBIN: $0.rxBIN, rxPCN: $0.rxPCN,
                            rxGroup: $0.rxGroup, notes: $0.notes, cardFront: $0.cardFrontImage,
                            cardBack: $0.cardBackImage, memberIDs: $0.members.map(\.id).sorted { $0.uuidString < $1.uuidString })
        }
    }

    /// Replaces everything in the database with the contents of this archive.
    func restore(into context: ModelContext) throws {
        for person in try context.fetch(FetchDescriptor<Person>()) { context.delete(person) }
        for provider in try context.fetch(FetchDescriptor<Provider>()) { context.delete(provider) }
        for policy in try context.fetch(FetchDescriptor<InsurancePolicy>()) { context.delete(policy) }
        for pharmacy in try context.fetch(FetchDescriptor<Pharmacy>()) { context.delete(pharmacy) }
        for contact in try context.fetch(FetchDescriptor<EmergencyContact>()) { context.delete(contact) }
        try context.save()

        var peopleByID: [UUID: Person] = [:]
        for record in people {
            let person = Person(name: record.name, dateOfBirth: record.dateOfBirth, sortOrder: record.sortOrder)
            context.insert(person)
            person.id = record.id
            person.preferredName = record.preferredName
            person.sexRaw = record.sex
            person.bloodTypeRaw = record.bloodType
            person.height = record.height
            person.weight = record.weight
            person.preferredPharmacy = record.preferredPharmacy
            person.notes = record.notes
            person.photoData = record.photo
            person.createdAt = record.createdAt
            peopleByID[record.id] = person

            for r in record.medications {
                let item = Medication(name: r.name, dose: r.dose, frequency: r.frequency, isActive: r.isActive)
                context.insert(item)
                item.reason = r.reason
                item.prescriber = r.prescriber
                item.pharmacy = r.pharmacy
                item.notes = r.notes
                item.startDate = r.startDate
                item.endDate = r.endDate
                item.person = person
            }
            for r in record.allergies {
                let item = Allergy(allergen: r.allergen, reaction: r.reaction)
                context.insert(item)
                item.kindRaw = r.kind
                item.severityRaw = r.severity
                item.notes = r.notes
                item.person = person
            }
            for r in record.conditions {
                let item = Condition(name: r.name, diagnosedDate: r.diagnosedDate)
                context.insert(item)
                item.statusRaw = r.status
                item.treatingProvider = r.treatingProvider
                item.notes = r.notes
                item.person = person
            }
            for r in record.procedures {
                let item = Procedure(name: r.name, date: r.date)
                context.insert(item)
                item.facility = r.facility
                item.surgeon = r.surgeon
                item.notes = r.notes
                item.person = person
            }
            for r in record.immunizations {
                let item = Immunization(vaccine: r.vaccine, date: r.date, doseNumber: r.doseNumber)
                context.insert(item)
                item.location = r.location
                item.lotNumber = r.lotNumber
                item.notes = r.notes
                item.person = person
            }
            for r in record.familyHistory {
                let item = FamilyHistoryItem(relative: r.relative, condition: r.condition)
                context.insert(item)
                item.notes = r.notes
                item.person = person
            }
            for r in record.emergencyContacts {
                // Version 1 backups: each contact belonged to one person.
                let item = EmergencyContact(name: r.name, relationship: r.relationship, phone: r.phone)
                context.insert(item)
                item.notes = r.notes
                item.people = [person]
            }
        }

        for r in providers {
            let provider = Provider(name: r.name, specialty: r.specialty)
            context.insert(provider)
            provider.practice = r.practice
            provider.phone = r.phone
            provider.fax = r.fax
            provider.address = r.address
            provider.portalURL = r.portalURL
            provider.notes = r.notes
            provider.patients = r.patientIDs.compactMap { peopleByID[$0] }
        }

        for r in insurancePolicies {
            let policy = InsurancePolicy(carrier: r.carrier)
            context.insert(policy)
            policy.kindRaw = r.kind
            policy.planName = r.planName
            policy.memberID = r.memberID
            policy.groupNumber = r.groupNumber
            policy.subscriberName = r.subscriberName
            policy.subscriberDateOfBirth = r.subscriberDateOfBirth
            policy.phone = r.phone
            policy.rxBIN = r.rxBIN
            policy.rxPCN = r.rxPCN
            policy.rxGroup = r.rxGroup
            policy.notes = r.notes
            policy.cardFrontImage = r.cardFront
            policy.cardBackImage = r.cardBack
            policy.members = r.memberIDs.compactMap { peopleByID[$0] }
        }

        for r in pharmacies ?? [] {
            let pharmacy = Pharmacy(name: r.name, phone: r.phone, address: r.address)
            context.insert(pharmacy)
            pharmacy.notes = r.notes
            pharmacy.latitude = r.latitude
            pharmacy.longitude = r.longitude
            pharmacy.patients = r.patientIDs.compactMap { peopleByID[$0] }
        }

        for r in contacts ?? [] {
            let contact = EmergencyContact(name: r.name, relationship: r.relationship, phone: r.phone)
            context.insert(contact)
            contact.notes = r.notes
            contact.people = r.personIDs.compactMap { peopleByID[$0] }
        }

        try context.save()
        // Turns a version 1 "preferred pharmacy" into a shared pharmacy.
        try ModelStore.upgradeData(in: context)
    }
}
