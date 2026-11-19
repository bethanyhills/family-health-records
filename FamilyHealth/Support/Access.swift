import SwiftUI

/// Single place that decides whether records can be added or edited.
///
/// The app is a free download, and the first family member is free to add
/// and edit, so people see what the app does before paying. More people
/// need a plan: $9.99 a year, starting with a 14-day free trial through
/// Apple, or $19.99 once (see `Purchases`). Without one, records always
/// stay viewable and exportable. The rules live in `PlanPolicy.access`.
struct RecordAccess: Equatable {
    /// Records can be added and edited.
    var canEdit: Bool = true
    /// Another family member can be added.
    var canAddPerson: Bool = true
    /// Shared family members can be imported from another phone.
    var canImportPeople: Bool = true

    static let unlocked = RecordAccess()
}

private struct RecordAccessKey: EnvironmentKey {
    static let defaultValue = RecordAccess.unlocked
}

extension EnvironmentValues {
    var recordAccess: RecordAccess {
        get { self[RecordAccessKey.self] }
        set { self[RecordAccessKey.self] = newValue }
    }
}
