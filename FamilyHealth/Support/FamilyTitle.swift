import SwiftUI

/// The title of the Family screen: "My Family" unless the person names it ("Hills Family").
enum FamilyTitle {
    static let key = "familyTitle"
    static let standard = "My Family"

    static func display(_ stored: String) -> String {
        stored.isBlank ? standard : stored.trimmed
    }
}

/// The app's name, quietly, at the foot of the Family screen.
struct AppNameFooter: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.text.square.fill")
            Text("Family Health Binder")
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
