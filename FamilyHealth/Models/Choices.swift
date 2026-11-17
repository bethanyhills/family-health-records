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
    case medical, dental, vision, prescription
    case medicare, medicareAdvantage, medigap, medicarePartD, medicaid
    case other

    var label: String {
        switch self {
        case .medical: "Medical"
        case .dental: "Dental"
        case .vision: "Vision"
        case .prescription: "Prescription"
        case .medicare: "Medicare (Parts A and B)"
        case .medicareAdvantage: "Medicare Advantage (Part C)"
        case .medigap: "Medicare supplement (Medigap)"
        case .medicarePartD: "Medicare Part D (drugs)"
        case .medicaid: "Medicaid"
        case .other: "Other"
        }
    }
}

enum TherapyKind: String, PickerChoice {
    case occupational, speech, aba, physical, feeding, counseling, other

    var label: String {
        switch self {
        case .occupational: "Occupational therapy (OT)"
        case .speech: "Speech therapy"
        case .aba: "ABA therapy"
        case .physical: "Physical therapy (PT)"
        case .feeding: "Feeding therapy"
        case .counseling: "Counseling"
        case .other: "Other"
        }
    }
}

enum DocumentKind: String, PickerChoice {
    case labResults, imaging, diagnosticReport, visitSummary, referral, prescription
    case vaccineRecord, schoolForm, plan504, iep, insuranceLetter
    case powerOfAttorney, advanceDirective, polst, hipaaRelease
    case other

    var label: String {
        switch self {
        case .labResults: "Lab results"
        case .imaging: "Imaging report (X-ray, MRI, ultrasound)"
        case .diagnosticReport: "Evaluation or diagnostic report"
        case .visitSummary: "Visit or discharge summary"
        case .referral: "Referral"
        case .prescription: "Prescription"
        case .vaccineRecord: "Vaccine record"
        case .schoolForm: "School form"
        case .plan504: "504 plan"
        case .iep: "IEP (Individualized Education Program)"
        case .insuranceLetter: "Insurance letter"
        case .powerOfAttorney: "Power of attorney"
        case .advanceDirective: "Advance directive or living will"
        case .polst: "POLST / DNR"
        case .hipaaRelease: "HIPAA release"
        case .other: "Other"
        }
    }

    /// A 504 plan or IEP; listed in their own section and linked from the school details.
    var isSchoolPlan: Bool { self == .plan504 || self == .iep }

    /// Legal papers a caregiver needs on hand; listed in their own section.
    var isLegal: Bool {
        [.powerOfAttorney, .advanceDirective, .polst, .hipaaRelease].contains(self)
    }
}

/// A child's school support plan. The plan itself is stored as a document.
enum SchoolPlan: String, PickerChoice {
    case noPlan = "none", plan504, iep

    var label: String {
        switch self {
        case .noPlan: "None"
        case .plan504: "504 plan"
        case .iep: "IEP"
        }
    }

    /// "Active IEP", as shown in the school details and on the intake summary.
    var activeLabel: String { self == .noPlan ? "" : "Active \(label)" }

    var documentKind: DocumentKind? {
        switch self {
        case .noPlan: nil
        case .plan504: .plan504
        case .iep: .iep
        }
    }
}
