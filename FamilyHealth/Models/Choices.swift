import Foundation

/// Fixed lists used by pickers. Stored in the database as their raw string
/// so new cases can be added later without a data migration.
protocol PickerChoice: CaseIterable, Identifiable, RawRepresentable, Hashable where RawValue == String {
    var label: String { get }
}

extension PickerChoice {
    var id: String { rawValue }
}

enum Sex: String, PickerChoice {
    case unspecified, female, male, other

    var label: String {
        switch self {
        case .unspecified: "Not specified"
        case .female: "Female"
        case .male: "Male"
        case .other: "Other"
        }
    }
}

enum BloodType: String, PickerChoice {
    case unknown
    case aPositive = "A+", aNegative = "A-"
    case bPositive = "B+", bNegative = "B-"
    case abPositive = "AB+", abNegative = "AB-"
    case oPositive = "O+", oNegative = "O-"

    var label: String { self == .unknown ? "Unknown" : rawValue }
}

enum AllergyKind: String, PickerChoice {
    case medication, food, environmental, other

    var label: String {
        switch self {
        case .medication: "Medication"
        case .food: "Food"
        case .environmental: "Environmental"
        case .other: "Other"
        }
    }
}

enum AllergySeverity: String, PickerChoice {
    case unknown, mild, moderate, severe

    var label: String {
        switch self {
        case .unknown: "Unknown"
        case .mild: "Mild"
        case .moderate: "Moderate"
        case .severe: "Severe"
        }
    }
}

enum ConditionStatus: String, PickerChoice {
    case active, managed, resolved

    var label: String {
        switch self {
        case .active: "Active"
        case .managed: "Managed"
        case .resolved: "Resolved"
        }
    }
}

enum InsuranceKind: String, PickerChoice {
    case medical, dental, vision, prescription, other

    var label: String {
        switch self {
        case .medical: "Medical"
        case .dental: "Dental"
        case .vision: "Vision"
        case .prescription: "Prescription"
        case .other: "Other"
        }
    }
}
