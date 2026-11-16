import Foundation
import SwiftData

/// Version 1.2: adds therapies. Uses the live model classes.
enum SchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 2, 0)

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
        ]
    }
}

/// When a model changes: freeze the current schema like `SchemaV1` and `SchemaV2`,
/// add a new version with the live classes, add a stage below, and point
/// `ModelStore.currentSchema` at the new version.
enum FamilyHealthMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self, SchemaV3.self] }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
        ]
    }
}

enum ModelStore {
    static let storeName = "FamilyHealth"
    /// The newest schema version, the one that uses the live model classes.
    static let currentSchema: any VersionedSchema.Type = SchemaV3.self

    /// Records live only on this device. `cloudKitDatabase: .none` keeps
    /// SwiftData from ever syncing health data to iCloud (App Store guideline 5.1.3).
    static func makeContainer(inMemory: Bool = false, url: URL? = nil) -> ModelContainer {
        do {
            let container = try openContainer(inMemory: inMemory, url: url)
            try upgradeData(in: ModelContext(container))
            return container
        } catch {
            fatalError("Could not open the records database: \(error)")
        }
    }

    static func openContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: currentSchema)
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(storeName, schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: FamilyHealthMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// Data fix-ups that run after the database opens. Each step is safe to repeat.
    static func upgradeData(in context: ModelContext) throws {
        // 1.1: the old free-text "preferred pharmacy" becomes a shared Pharmacy.
        // In family order, so the first person's spelling of a shared pharmacy name wins every time.
        let people = try context.fetch(FetchDescriptor<Person>(sortBy: [
            SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt), SortDescriptor(\.name),
        ]))
        var pharmaciesByName = Dictionary(
            try context.fetch(FetchDescriptor<Pharmacy>()).map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for person in people where !person.preferredPharmacy.isBlank {
            let name = person.preferredPharmacy.trimmed
            let pharmacy = pharmaciesByName[name.lowercased()] ?? {
                let new = Pharmacy(name: name)
                context.insert(new)
                pharmaciesByName[name.lowercased()] = new
                return new
            }()
            if !person.pharmacies.contains(where: { $0.id == pharmacy.id }) {
                person.pharmacies.append(pharmacy)
            }
            person.preferredPharmacy = ""
        }

        // 1.1: emergency contacts can be shared, so move them off their single owner.
        let contacts = try context.fetch(FetchDescriptor<EmergencyContact>())
        for contact in contacts {
            guard let owner = contact.person else { continue }
            if !contact.people.contains(where: { $0.id == owner.id }) {
                contact.people.append(owner)
            }
            contact.person = nil
        }

        // Shared records left with nobody, e.g. an insurance card removed from its only member
        // before 1.1 deleted unused cards. Without this they kept showing up in "Add existing".
        removeUnusedSharedRecords(in: context)

        if context.hasChanges { try context.save() }
    }

    /// Deletes insurance, providers, pharmacies, emergency contacts and schools that no
    /// family member uses any more. Shared records are only reachable through a person, so
    /// one with nobody left is effectively deleted and should not be offered again.
    static func removeUnusedSharedRecords(in context: ModelContext) {
        // Saving first brings both sides of each relationship up to date.
        try? context.save()
        func prune<T: PersistentModel>(_ type: T.Type, isUnused: (T) -> Bool) {
            for item in (try? context.fetch(FetchDescriptor<T>())) ?? [] where isUnused(item) {
                context.delete(item)
            }
        }
        prune(InsurancePolicy.self) { $0.members.isEmpty }
        prune(Provider.self) { $0.patients.isEmpty }
        prune(Pharmacy.self) { $0.patients.isEmpty }
        prune(School.self) { $0.students.isEmpty }
        prune(EmergencyContact.self) { $0.people.isEmpty && $0.person == nil }
    }
}
