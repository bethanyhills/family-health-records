import SwiftUI

/// Single place that decides whether records can be added or edited.
///
/// The App Store version will be a free download with a full-featured
/// 14-day trial and one in-app purchase to unlock it for good. After the
/// trial, records always stay viewable and exportable; only adding and
/// editing need the purchase. Until the store work lands (milestone 4),
/// everything is unlocked.
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
