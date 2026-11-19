import SwiftUI

/// Single place that decides whether records can be added or edited.
///
/// The app is a free download. Adding and editing need a plan: $9.99 a
/// year, starting with a 14-day free trial through Apple, or $19.99 once
/// (see `Purchases`). Without one, records always stay viewable and
/// exportable.
struct RecordAccess: Equatable {
    var canEdit: Bool = true

    static let unlocked = RecordAccess(canEdit: true)
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
