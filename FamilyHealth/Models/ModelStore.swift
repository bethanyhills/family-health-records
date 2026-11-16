import Foundation
import SwiftData

/// Version 1.1: adds shared pharmacies. Uses the live model classes.
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 1, 0)

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
        ]
    }
}

/// When a model changes: freeze the current schema like `SchemaV1`, add a new
/// version with the live classes, and add a stage below.
enum FamilyHealthMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}

enum ModelStore {
    static let storeName = "FamilyHealth"

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
        let schema = Schema(versionedSchema: SchemaV2.self)
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
        let people = try context.fetch(FetchDescriptor<Person>())
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

        if context.hasChanges { try context.save() }
    }
}
