import SwiftUI

/// A label and value that can be copied with a long press, for pasting into
/// online intake forms. Hidden when the value is empty.
struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        if !value.isBlank {
            LabeledContent(label) {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            .contextMenu {
                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Label("Copy \(label)", systemImage: "doc.on.doc")
                }
            }
        }
    }
}
