import SwiftUI
import UIKit

/// Feedback and feature requests go by email from the person's own Mail app, so the
/// app itself still sends nothing anywhere.
enum Feedback {
    /// Where feedback goes: the app's support mailbox.
    static let address = "healthbindersupport@gmail.com"
    /// The app's App Store id, once it has one. The rating row shows only when this is set.
    static let appStoreID: String? = nil

    enum Kind: CaseIterable {
        case feedback, featureRequest

        var subject: String {
            switch self {
            case .feedback: "Family Health Binder feedback"
            case .featureRequest: "Family Health Binder feature request"
            }
        }

        var prompt: String {
            switch self {
            case .feedback: "What's working, and what isn't?"
            case .featureRequest: "What would you like the app to do?"
            }
        }
    }

    /// The app and phone details that help answer a message. Never any records.
    static func deviceDetails(version: String, system: String, model: String) -> String {
        "App version: \(version)\niOS: \(system)\nDevice: \(model)"
    }

    static func mailURL(_ kind: Kind, details: String, to address: String = address) -> URL? {
        let body = "\(kind.prompt)\n\n\n\nPlease don't include medical details about your family.\n\n---\n\(details)"
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = address
        parts.queryItems = [URLQueryItem(name: "subject", value: kind.subject),
                            URLQueryItem(name: "body", value: body)]
        // URLComponents leaves "+" alone, which some mail apps read as a space.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url
    }

    static func reviewURL(appStoreID: String?) -> URL? {
        guard let appStoreID, !appStoreID.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }
}

/// Settings rows for sending feedback, asking for a feature, and rating the app.
struct FeedbackSection: View {
    let version: String
    @Environment(\.openURL) private var openURL
    @State private var isShowingNoMail = false

    private var details: String {
        Feedback.deviceDetails(version: version, system: UIDevice.current.systemVersion, model: UIDevice.current.model)
    }

    var body: some View {
        Section {
            ForEach(Feedback.Kind.allCases, id: \.self) { kind in
                Button {
                    send(kind)
                } label: {
                    Label(kind == .feedback ? "Send feedback" : "Request a feature",
                          systemImage: kind == .feedback ? "envelope" : "lightbulb")
                }
            }
            if let review = Feedback.reviewURL(appStoreID: Feedback.appStoreID) {
                Link(destination: review) {
                    Label("Rate on the App Store", systemImage: "star")
                }
            }
        } header: {
            Text("Feedback")
        } footer: {
            Text("Opens an email to \(Feedback.address) in your Mail app. We read every message.")
        }
        .alert("No email account", isPresented: $isShowingNoMail) {
            Button("Copy address") { UIPasteboard.general.string = Feedback.address }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Set up Mail on this iPhone, or write to \(Feedback.address) from any email app.")
        }
    }

    private func send(_ kind: Feedback.Kind) {
        guard let url = Feedback.mailURL(kind, details: details) else { return }
        openURL(url) { accepted in
            if !accepted { isShowingNoMail = true }
        }
    }
}
