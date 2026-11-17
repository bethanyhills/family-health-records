import SwiftUI

/// A Social Security number, stored as its digits and shown masked to the last four.
enum SocialSecurityNumber {
    static func digits(_ text: String) -> String {
        String(text.filter(\.isASCII).filter(\.isNumber).prefix(9))
    }

    /// "123-45-6789", or as much of it as has been typed.
    static func formatted(_ text: String) -> String {
        let d = Array(digits(text))
        var result = ""
        for (index, digit) in d.enumerated() {
            if index == 3 || index == 5 { result += "-" }
            result.append(digit)
        }
        return result
    }

    /// "•••-••-6789". Short or partial numbers show only dots.
    static func masked(_ text: String) -> String {
        let d = digits(text)
        guard d.count == 9 else { return d.isEmpty ? "" : "•••-••-••••" }
        return "•••-••-" + d.suffix(4)
    }

    static func isComplete(_ text: String) -> Bool { digits(text).count == 9 }
}

/// The number on the person's page: masked until the eye is tapped, and hidden in the app switcher.
struct SocialSecurityRow: View {
    let digits: String
    @State private var isShown = false

    var body: some View {
        if !digits.isEmpty {
            LabeledContent("Social Security number") {
                HStack(spacing: 8) {
                    Text(isShown ? SocialSecurityNumber.formatted(digits) : SocialSecurityNumber.masked(digits))
                        .monospacedDigit()
                        .privacySensitive()
                    Button {
                        isShown.toggle()
                    } label: {
                        Image(systemName: isShown ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isShown ? "Hide number" : "Show number")
                }
            }
            .contextMenu {
                Button {
                    UIPasteboard.general.string = SocialSecurityNumber.formatted(digits)
                } label: {
                    Label("Copy Social Security number", systemImage: "doc.on.doc")
                }
            }
        }
    }
}

/// Typing the number: digits only, dashes added as you go, hidden unless the eye is tapped.
struct SocialSecurityField: View {
    @Binding var digits: String
    @State private var isShown = false

    var body: some View {
        HStack {
            Group {
                if isShown {
                    TextField("123-45-6789", text: Binding(
                        get: { SocialSecurityNumber.formatted(digits) },
                        set: { digits = SocialSecurityNumber.digits($0) }
                    ))
                } else {
                    SecureField("123-45-6789", text: Binding(
                        get: { digits },
                        set: { digits = SocialSecurityNumber.digits($0) }
                    ))
                }
            }
            .keyboardType(.numberPad)
            .textContentType(.none)
            .privacySensitive()
            Button {
                isShown.toggle()
            } label: {
                Image(systemName: isShown ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isShown ? "Hide number" : "Show number")
        }
    }
}
