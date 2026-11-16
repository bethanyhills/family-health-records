import Foundation

extension Date {
    /// "Mar 4, 2015"
    var shortDate: String { formatted(date: .abbreviated, time: .omitted) }
    /// "03/04/2015", the way intake forms ask for it.
    var formDate: String { TypedDate.string(from: self) }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
