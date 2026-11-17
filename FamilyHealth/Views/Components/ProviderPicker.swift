import SwiftData
import SwiftUI

/// Picks one of the family's providers (this person's first), none, or a new one.
/// `selection` is the provider's id as text, "" for none.
struct ProviderPicker: View {
    let person: Person
    @Binding var selection: String
    var label = "Provider"

    @Query(sort: \Provider.name) private var providers: [Provider]
    @State private var isAddingProvider = false

    private static let newProvider = "new"

    var body: some View {
        Picker(label, selection: Binding(
            get: { selection },
            set: { choice in
                if choice == Self.newProvider {
                    isAddingProvider = true
                } else {
                    selection = choice
                }
            }
        )) {
            Text("None").tag("")
            ForEach(ordered) { provider in
                Text(provider.specialty.isBlank ? provider.name : "\(provider.name) (\(provider.specialty))")
                    .tag(provider.id.uuidString)
            }
            Text("New provider…").tag(Self.newProvider)
        }
        .sheet(isPresented: $isAddingProvider) {
            NavigationStack {
                ProviderEditView(provider: nil, defaultPatient: person) { selection = $0.id.uuidString }
            }
        }
    }

    private var ordered: [Provider] {
        let mine = Set(person.providers.map(\.id))
        return providers.filter { mine.contains($0.id) } + providers.filter { !mine.contains($0.id) }
    }

    /// The chosen provider, also added to the person's care team.
    static func resolve(_ selection: String, for person: Person, in providers: [Provider]) -> Provider? {
        guard let provider = providers.first(where: { $0.id.uuidString == selection }) else { return nil }
        if !provider.patients.contains(where: { $0.id == person.id }) {
            provider.patients.append(person)
        }
        return provider
    }
}
