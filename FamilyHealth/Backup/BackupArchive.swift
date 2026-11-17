import Foundation
import SwiftData

/// A plain, versioned copy of every record, used for the encrypted backup file.
struct BackupArchive: Codable, Equatable {
    static let currentVersion = 5

    var version = BackupArchive.currentVersion
    var exportedAt = Date()
    var people: [PersonRecord] = []
    var providers: [ProviderRecord] = []
    var insurancePolicies: [InsuranceRecord] = []
    /// Added in version 2. Missing from version 1 backups.
    var pharmacies: [PharmacyRecord]? = []
    /// Added in version 2. Version 1 kept contacts inside each person.
    var contacts: [ContactRecord]? = []
    /// Added in version 2.
    var schools: [SchoolRecord]? = []
    /// Added in version 4. True for a file that shares some family members with another
    /// phone; it is merged in on import instead of replacing everything.
    var isSharedProfiles: Bool? = false

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
        /// Added in version 2.
        var schoolGrade, teacherName, teacherEmail, teacherPhone: String?
        /// Added in version 3.
        var therapies: [TherapyRecord]?
        /// Added in version 5.
        var communicationNeeds: String?
        var documents: [DocumentRecord]?
        var visits: [VisitRecord]?
    }

    struct DocumentRecord: Codable, Equatable {
        var title, kind, notes, recognizedText: String
        var date: Date?
        var pageCount: Int
        var pdf: Data?
        var createdAt: Date
        var providerID: UUID?
    }

    struct VisitRecord: Codable, Equatable {
        var reason, notes, followUp: String
        var date, followUpDate: Date?
        var createdAt: Date
        var providerID: UUID?
    }

    struct TherapyRecord: Codable, Equatable {
        var kind, customName, frequency, goals, notes: String
        var startDate, endDate: Date?
        var isActive: Bool
        /// Matches `ProviderRecord.id`.
        var providerID: UUID?
    }

    struct SchoolRecord: Codable, Equatable {
        var name, address, phone, nurseName, nursePhone, nurseEmail, notes: String
        var studentIDs: [UUID]
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
        /// Added in version 3, so therapies can point at their provider.
        var id: UUID?
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
    /// Copies everything in the database into an archive. With `onlyPeople`, copies just those
    /// family members and the providers, insurance, pharmacies, contacts and schools they use,
    /// for sharing with another phone.
    init(context: ModelContext, onlyPeople: Set<UUID>? = nil) throws {
        let people = try context.fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]))
            .filter { onlyPeople?.contains($0.id) ?? true }
        let included = Set(people.map(\.id))
        /// The included people among `linked`, or nil when the record isn't used by any of them.
        func ids(_ linked: [Person]) -> [UUID]? {
            let ids = linked.map(\.id).filter { included.contains($0) }.sorted { $0.uuidString < $1.uuidString }
            return ids.isEmpty && onlyPeople != nil ? nil : ids
        }
        isSharedProfiles = onlyPeople != nil
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
                emergencyContacts: [],
                schoolGrade: p.schoolGrade, teacherName: p.teacherName,
                teacherEmail: p.teacherEmail, teacherPhone: p.teacherPhone,
                therapies: p.therapies.sorted { $0.displayName < $1.displayName }.map {
                    TherapyRecord(kind: $0.kindRaw, customName: $0.customName, frequency: $0.frequency,
                                  goals: $0.goals, notes: $0.notes, startDate: $0.startDate, endDate: $0.endDate,
                                  isActive: $0.isActive, providerID: $0.provider?.id)
                },
                communicationNeeds: p.communicationNeeds,
                documents: p.documents.sorted { $0.createdAt < $1.createdAt }.map {
                    DocumentRecord(title: $0.title, kind: $0.kindRaw, notes: $0.notes, recognizedText: $0.recognizedText,
                                   date: $0.date, pageCount: $0.pageCount, pdf: $0.pdfData, createdAt: $0.createdAt,
                                   providerID: $0.provider?.id)
                },
                visits: p.visits.sorted { $0.createdAt < $1.createdAt }.map {
                    VisitRecord(reason: $0.reason, notes: $0.notes, followUp: $0.followUp, date: $0.date,
                                followUpDate: $0.followUpDate, createdAt: $0.createdAt, providerID: $0.provider?.id)
                }
            )
        }
        providers = try context.fetch(FetchDescriptor<Provider>(sortBy: [SortDescriptor(\.name)])).compactMap {
            guard let linked = ids($0.patients) else { return nil }
            return ProviderRecord(id: $0.id, name: $0.name, specialty: $0.specialty, practice: $0.practice, phone: $0.phone,
                           fax: $0.fax, address: $0.address, portalURL: $0.portalURL, notes: $0.notes,
                           patientIDs: linked)
        }
        pharmacies = try context.fetch(FetchDescriptor<Pharmacy>(sortBy: [SortDescriptor(\.name)])).compactMap {
            guard let linked = ids($0.patients) else { return nil }
            return PharmacyRecord(name: $0.name, phone: $0.phone, address: $0.address, notes: $0.notes,
                           latitude: $0.latitude, longitude: $0.longitude,
                           patientIDs: linked)
        }
        schools = try context.fetch(FetchDescriptor<School>(sortBy: [SortDescriptor(\.name)])).compactMap {
            guard let linked = ids($0.students) else { return nil }
            return SchoolRecord(name: $0.name, address: $0.address, phone: $0.phone, nurseName: $0.nurseName,
                         nursePhone: $0.nursePhone, nurseEmail: $0.nurseEmail, notes: $0.notes,
                         studentIDs: linked)
        }
        contacts = try context.fetch(FetchDescriptor<EmergencyContact>(sortBy: [SortDescriptor(\.name)])).compactMap {
            guard let linked = ids($0.people) else { return nil }
            return ContactRecord(name: $0.name, relationship: $0.relationship, phone: $0.phone, notes: $0.notes,
                          personIDs: linked)
        }
        insurancePolicies = try context.fetch(FetchDescriptor<InsurancePolicy>(sortBy: [SortDescriptor(\.carrier)])).compactMap {
            guard let linked = ids($0.members) else { return nil }
            return InsuranceRecord(kind: $0.kindRaw, carrier: $0.carrier, planName: $0.planName, memberID: $0.memberID,
                            groupNumber: $0.groupNumber, subscriberName: $0.subscriberName, phone: $0.phone,
                            subscriberDateOfBirth: $0.subscriberDateOfBirth, rxBIN: $0.rxBIN, rxPCN: $0.rxPCN,
                            rxGroup: $0.rxGroup, notes: $0.notes, cardFront: $0.cardFrontImage,
                            cardBack: $0.cardBackImage, memberIDs: linked)
        }
    }

    /// Replaces everything in the database with the contents of this archive.
    func restore(into context: ModelContext) throws {
        for person in try context.fetch(FetchDescriptor<Person>()) { context.delete(person) }
        for provider in try context.fetch(FetchDescriptor<Provider>()) { context.delete(provider) }
        for policy in try context.fetch(FetchDescriptor<InsurancePolicy>()) { context.delete(policy) }
        for pharmacy in try context.fetch(FetchDescriptor<Pharmacy>()) { context.delete(pharmacy) }
        for contact in try context.fetch(FetchDescriptor<EmergencyContact>()) { context.delete(contact) }
        for school in try context.fetch(FetchDescriptor<School>()) { context.delete(school) }
        for therapy in try context.fetch(FetchDescriptor<Therapy>()) { context.delete(therapy) }
        try context.save()

        var peopleByID: [UUID: Person] = [:]
        var providerLinks = ProviderLinks()
        for record in people {
            let person = Person(name: record.name)
            context.insert(person)
            person.id = record.id
            fill(person, from: record)
            insertRecords(of: record, for: person, in: context, providerLinks: &providerLinks)
            for r in record.emergencyContacts {
                // Version 1 backups: each contact belonged to one person.
                let item = EmergencyContact(name: r.name, relationship: r.relationship, phone: r.phone)
                context.insert(item)
                item.notes = r.notes
                item.people = [person]
            }
            peopleByID[record.id] = person
        }

        for r in providers {
            let provider = Provider(name: r.name)
            context.insert(provider)
            if let id = r.id { provider.id = id }
            fill(provider, from: r)
            provider.patients = r.patientIDs.compactMap { peopleByID[$0] }
            if let id = r.id {
                providerLinks.link(provider, id: id)
            }
        }
        for r in insurancePolicies {
            let policy = InsurancePolicy(carrier: r.carrier)
            context.insert(policy)
            fill(policy, from: r)
            policy.members = r.memberIDs.compactMap { peopleByID[$0] }
        }
        for r in pharmacies ?? [] {
            let pharmacy = Pharmacy(name: r.name)
            context.insert(pharmacy)
            fill(pharmacy, from: r)
            pharmacy.patients = r.patientIDs.compactMap { peopleByID[$0] }
        }
        for r in schools ?? [] {
            let school = School(name: r.name)
            context.insert(school)
            fill(school, from: r)
            school.students = r.studentIDs.compactMap { peopleByID[$0] }
        }
        for r in contacts ?? [] {
            let contact = EmergencyContact(name: r.name, relationship: r.relationship, phone: r.phone)
            context.insert(contact)
            fill(contact, from: r)
            contact.people = r.personIDs.compactMap { peopleByID[$0] }
        }

        try context.save()
        // Turns a version 1 "preferred pharmacy" into a shared pharmacy.
        try ModelStore.upgradeData(in: context)
    }

    /// Adds the family members in this archive, or updates them if they are already here,
    /// without touching anyone else. Used for a file someone shared from their phone.
    ///
    /// For each incoming person, their own records are replaced by the file's copy. Shared
    /// records are matched to ones already here (providers by id, then name; insurance by
    /// carrier and member ID; pharmacies and schools by name; contacts by name and phone),
    /// updated from the file, and linked exactly as the file says.
    /// Returns how many people were added and how many were updated.
    @discardableResult
    func merge(into context: ModelContext) throws -> (added: Int, updated: Int) {
        let existingPeople = Dictionary(
            try context.fetch(FetchDescriptor<Person>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let nextSortOrder = (existingPeople.values.map(\.sortOrder).max() ?? -1) + 1
        var peopleByID: [UUID: Person] = [:]
        var providerLinks = ProviderLinks()
        var added = 0
        for (index, record) in people.enumerated() {
            let person: Person
            if let existing = existingPeople[record.id] {
                person = existing
                let sortOrder = existing.sortOrder
                for item in person.medications { context.delete(item) }
                for item in person.allergies { context.delete(item) }
                for item in person.conditions { context.delete(item) }
                for item in person.procedures { context.delete(item) }
                for item in person.immunizations { context.delete(item) }
                for item in person.familyHistory { context.delete(item) }
                for item in person.therapies { context.delete(item) }
                for item in person.documents { context.delete(item) }
                for item in person.visits { context.delete(item) }
                fill(person, from: record)
                // Keep this phone's order of the family.
                person.sortOrder = sortOrder
            } else {
                person = Person(name: record.name)
                context.insert(person)
                person.id = record.id
                fill(person, from: record)
                person.sortOrder = nextSortOrder + index
                added += 1
            }
            insertRecords(of: record, for: person, in: context, providerLinks: &providerLinks)
            peopleByID[record.id] = person
        }
        try context.save()

        let incoming = Array(peopleByID.values)
        /// Points `linked` (a shared record's people) at exactly the file's incoming people,
        /// leaving anyone else on this phone linked as they were.
        func relink(_ linked: inout [Person], to ids: [UUID]) {
            linked.removeAll { person in incoming.contains { $0.id == person.id } }
            linked.append(contentsOf: ids.compactMap { peopleByID[$0] })
        }
        func same(_ a: String, _ b: String) -> Bool {
            a.trimmed.localizedCaseInsensitiveCompare(b.trimmed) == .orderedSame
        }

        // Drop the incoming people from shared records first, so anything the sender
        // removed them from is removed here too.
        for provider in try context.fetch(FetchDescriptor<Provider>()) { relink(&provider.patients, to: []) }
        for policy in try context.fetch(FetchDescriptor<InsurancePolicy>()) { relink(&policy.members, to: []) }
        for pharmacy in try context.fetch(FetchDescriptor<Pharmacy>()) { relink(&pharmacy.patients, to: []) }
        for school in try context.fetch(FetchDescriptor<School>()) { relink(&school.students, to: []) }
        for contact in try context.fetch(FetchDescriptor<EmergencyContact>()) { relink(&contact.people, to: []) }

        let providersHere = try context.fetch(FetchDescriptor<Provider>())
        for r in providers {
            let provider = providersHere.first { r.id != nil && $0.id == r.id }
                ?? providersHere.first { same($0.name, r.name) }
                ?? {
                    let new = Provider(name: r.name)
                    context.insert(new)
                    if let id = r.id { new.id = id }
                    return new
                }()
            fill(provider, from: r)
            relink(&provider.patients, to: r.patientIDs)
            if let id = r.id {
                providerLinks.link(provider, id: id)
            }
        }
        let policiesHere = try context.fetch(FetchDescriptor<InsurancePolicy>())
        for r in insurancePolicies {
            let policy = policiesHere.first { same($0.carrier, r.carrier) && same($0.memberID, r.memberID) } ?? {
                let new = InsurancePolicy(carrier: r.carrier)
                context.insert(new)
                return new
            }()
            fill(policy, from: r)
            relink(&policy.members, to: r.memberIDs)
        }
        let pharmaciesHere = try context.fetch(FetchDescriptor<Pharmacy>())
        for r in pharmacies ?? [] {
            let pharmacy = pharmaciesHere.first { same($0.name, r.name) } ?? {
                let new = Pharmacy(name: r.name)
                context.insert(new)
                return new
            }()
            fill(pharmacy, from: r)
            relink(&pharmacy.patients, to: r.patientIDs)
        }
        let schoolsHere = try context.fetch(FetchDescriptor<School>())
        for r in schools ?? [] {
            let school = schoolsHere.first { same($0.name, r.name) } ?? {
                let new = School(name: r.name)
                context.insert(new)
                return new
            }()
            fill(school, from: r)
            relink(&school.students, to: r.studentIDs)
        }
        let contactsHere = try context.fetch(FetchDescriptor<EmergencyContact>())
        for r in contacts ?? [] {
            let contact = contactsHere.first { same($0.name, r.name) && same($0.phone, r.phone) } ?? {
                let new = EmergencyContact(name: r.name)
                context.insert(new)
                return new
            }()
            fill(contact, from: r)
            relink(&contact.people, to: r.personIDs)
        }

        try context.save()
        try ModelStore.upgradeData(in: context)
        return (added, people.count - added)
    }

    // MARK: Filling records from the archive

    private func fill(_ person: Person, from record: PersonRecord) {
        person.name = record.name
        person.dateOfBirth = record.dateOfBirth
        person.sortOrder = record.sortOrder
        person.preferredName = record.preferredName
        person.sexRaw = record.sex
        person.bloodTypeRaw = record.bloodType
        person.height = record.height
        person.weight = record.weight
        person.preferredPharmacy = record.preferredPharmacy
        person.notes = record.notes
        person.photoData = record.photo
        person.createdAt = record.createdAt
        person.schoolGrade = record.schoolGrade ?? ""
        person.teacherName = record.teacherName ?? ""
        person.teacherEmail = record.teacherEmail ?? ""
        person.teacherPhone = record.teacherPhone ?? ""
        person.communicationNeeds = record.communicationNeeds ?? ""
    }

    /// Inserts the person's own records: medications, allergies, conditions, procedures,
    /// immunizations, family history and therapies.
    private func insertRecords(
        of record: PersonRecord, for person: Person, in context: ModelContext,
        providerLinks: inout ProviderLinks
    ) {
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
        for r in record.therapies ?? [] {
            let item = Therapy(kind: TherapyKind(rawValue: r.kind) ?? .other, isActive: r.isActive)
            context.insert(item)
            item.kindRaw = r.kind
            item.customName = r.customName
            item.frequency = r.frequency
            item.goals = r.goals
            item.notes = r.notes
            item.startDate = r.startDate
            item.endDate = r.endDate
            item.person = person
            if let providerID = r.providerID { providerLinks.therapies[providerID, default: []].append(item) }
        }
        for r in record.documents ?? [] {
            let item = HealthDocument(title: r.title, date: r.date)
            context.insert(item)
            item.kindRaw = r.kind
            item.notes = r.notes
            item.recognizedText = r.recognizedText
            item.pageCount = r.pageCount
            item.pdfData = r.pdf
            item.createdAt = r.createdAt
            item.person = person
            if let providerID = r.providerID { providerLinks.documents[providerID, default: []].append(item) }
        }
        for r in record.visits ?? [] {
            let item = Visit(date: r.date, reason: r.reason)
            context.insert(item)
            item.notes = r.notes
            item.followUp = r.followUp
            item.followUpDate = r.followUpDate
            item.createdAt = r.createdAt
            item.person = person
            if let providerID = r.providerID { providerLinks.visits[providerID, default: []].append(item) }
        }
    }

    private func fill(_ provider: Provider, from r: ProviderRecord) {
        provider.name = r.name
        provider.specialty = r.specialty
        provider.practice = r.practice
        provider.phone = r.phone
        provider.fax = r.fax
        provider.address = r.address
        provider.portalURL = r.portalURL
        provider.notes = r.notes
    }

    private func fill(_ policy: InsurancePolicy, from r: InsuranceRecord) {
        policy.carrier = r.carrier
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
    }

    private func fill(_ pharmacy: Pharmacy, from r: PharmacyRecord) {
        pharmacy.name = r.name
        pharmacy.phone = r.phone
        pharmacy.address = r.address
        pharmacy.notes = r.notes
        pharmacy.latitude = r.latitude
        pharmacy.longitude = r.longitude
    }

    private func fill(_ school: School, from r: SchoolRecord) {
        school.name = r.name
        school.address = r.address
        school.phone = r.phone
        school.nurseName = r.nurseName
        school.nursePhone = r.nursePhone
        school.nurseEmail = r.nurseEmail
        school.notes = r.notes
    }

    private func fill(_ contact: EmergencyContact, from r: ContactRecord) {
        contact.name = r.name
        contact.relationship = r.relationship
        contact.phone = r.phone
        contact.notes = r.notes
    }
}

/// Records that point at a provider by id, waiting for the provider to be created or matched.
struct ProviderLinks {
    var therapies: [UUID: [Therapy]] = [:]
    var documents: [UUID: [HealthDocument]] = [:]
    var visits: [UUID: [Visit]] = [:]

    func link(_ provider: Provider, id: UUID) {
        for item in therapies[id] ?? [] { item.provider = provider }
        for item in documents[id] ?? [] { item.provider = provider }
        for item in visits[id] ?? [] { item.provider = provider }
    }
}
