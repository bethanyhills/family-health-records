import Foundation
import SwiftData

/// Version 1 of the on-device database. When a model changes after release,
/// add a SchemaV2 and a migration stage so existing records carry over.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

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
        ]
    }
}

enum FamilyHealthMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum ModelStore {
    /// Records live only on this device. `cloudKitDatabase: .none` keeps
    /// SwiftData from ever syncing health data to iCloud (App Store guideline 5.1.3).
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(
            "FamilyHealth",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: FamilyHealthMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            fatalError("Could not open the records database: \(error)")
        }
    }
}
