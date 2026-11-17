import SwiftUI

/// Results of searching every family member's records, each opening the list it came from.
struct SearchResultsList: View {
    let hits: [FamilySearch.Hit]

    var body: some View {
        List(hits) { hit in
            NavigationLink {
                destination(for: hit)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(hit.title)
                        .font(.body.weight(.medium))
                    Text("\(hit.person.displayName) · \(hit.area.label)")
                        .font(.footnote)
                        .foregroundStyle(.tint)
                    if !hit.detail.isEmpty {
                        Text(hit.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .overlay {
            if hits.isEmpty {
                ContentUnavailableView.search
            }
        }
    }

    @ViewBuilder
    private func destination(for hit: FamilySearch.Hit) -> some View {
        let person = hit.person
        switch hit.area {
        case .person, .school: PersonDetailView(person: person)
        case .medication: MedicationsView(person: person)
        case .allergy: AllergiesView(person: person)
        case .condition: ConditionsView(person: person)
        case .therapy: TherapiesView(person: person)
        case .procedure: ProceduresView(person: person)
        case .immunization: ImmunizationsView(person: person)
        case .familyHistory: FamilyHistoryView(person: person)
        case .visit: VisitsView(person: person)
        case .document:
            if let document = hit.document {
                DocumentDetailView(person: person, document: document)
            } else {
                DocumentsView(person: person)
            }
        case .provider: ProvidersView(person: person)
        case .pharmacy: PharmaciesView(person: person)
        case .insurance: InsuranceView(person: person)
        case .contact: EmergencyContactsView(person: person)
        }
    }
}
