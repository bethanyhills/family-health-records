import SwiftUI

/// The review screen for adding what a document says to the person's records.
struct DocumentImportSheet: View {
    let person: Person
    let document: HealthDocument
    let action: DocumentImport
    var onFinished: ((String) -> Void)? = nil

    var body: some View {
        switch action {
        case .vaccines: VaccineImportView(person: person, document: document, onFinished: onFinished)
        case .prescription: PrescriptionImportView(person: person, document: document, onFinished: onFinished)
        case .visitSummary: VisitSummaryImportView(person: person, document: document, onFinished: onFinished)
        case .schoolPlan: SchoolPlanImportView(person: person, document: document, onFinished: onFinished)
        }
    }
}

/// A document and what to add from it, for `.sheet(item:)`.
struct DocumentReview: Identifiable {
    let person: Person
    let document: HealthDocument
    let action: DocumentImport
    var id: UUID { document.id }
}

extension DocumentImport {
    /// Where the contents end up, for "Added to …".
    var destination: String {
        switch self {
        case .vaccines: "Immunizations"
        case .prescription: "Medications"
        case .visitSummary: "Visit notes"
        case .schoolPlan: "school details"
        }
    }

    /// The document type a page that reads like this should be filed as.
    func documentKind(for text: String) -> DocumentKind {
        switch self {
        case .vaccines: .vaccineRecord
        case .prescription: .prescription
        case .visitSummary: .visitSummary
        case .schoolPlan: SchoolPlanParser.planKind(of: text).documentKind ?? .iep
        }
    }
}

extension DocumentOwner.Candidate {
    init(_ person: Person) {
        self.init(id: person.id, name: person.name, preferredName: person.preferredName, dateOfBirth: person.dateOfBirth)
    }
}

extension DocumentOwner {
    /// The family member a document's text names instead of `person`, if it clearly does.
    static func otherOwner(of text: String, filedUnder person: Person, family: [Person]) -> Person? {
        guard let match = otherOwner(of: text, current: Candidate(person), family: family.map { Candidate($0) }) else {
            return nil
        }
        return family.first { $0.id == match.id }
    }
}

extension Person {
    /// The name to use in short messages: the preferred name, or the first name.
    var shortName: String {
        if !preferredName.isBlank { return preferredName.trimmed }
        return name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
    }
}

/// A short confirmation that slides in at the top and goes away by itself.
private struct SuccessBanner: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .symbolRenderingMode(.multicolor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                        .padding(.top, 8)
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture { self.message = nil }
                        .task(id: message) {
                            AccessibilityNotification.Announcement(message).post()
                            try? await Task.sleep(for: .seconds(4))
                            self.message = nil
                        }
                }
            }
            .animation(.snappy, value: message)
    }
}

extension View {
    /// Shows `message` as a brief success banner, then clears it.
    func successBanner(_ message: Binding<String?>) -> some View {
        modifier(SuccessBanner(message: message))
    }
}
