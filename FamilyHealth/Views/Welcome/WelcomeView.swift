import SwiftUI

/// When to show the welcome screen.
enum Welcome {
    static let seenKey = "hasSeenWelcome"

    /// Only on a brand-new install. Someone who already has records knows the app,
    /// and the screen would otherwise show before Face ID.
    static func shouldShow(hasSeen: Bool, hasPeople: Bool) -> Bool {
        !hasSeen && !hasPeople
    }
}

/// Two short pages on first launch: what the app does, and how it keeps records private.
struct WelcomeView: View {
    let onDone: () -> Void

    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                WelcomePage(
                    systemImage: nil,
                    title: "Welcome to Family Health Binder",
                    subtitle: "Your whole family's health records in one place, ready when a form asks.",
                    points: [
                        WelcomePoint(
                            systemImage: "person.2.fill",
                            title: "Everyone in one binder",
                            detail: "Medications, allergies, doctors, insurance, vaccines and school plans for each person."
                        ),
                        WelcomePoint(
                            systemImage: "list.clipboard.fill",
                            title: "Forms filled out fast",
                            detail: "Each person's intake summary has what a new doctor's form asks. Tap a line to copy it, or share a PDF."
                        ),
                        WelcomePoint(
                            systemImage: "doc.viewfinder",
                            title: "Scan your papers",
                            detail: "Scan a prescription label, vaccine record or visit summary, and the app fills in the details for you to check."
                        ),
                    ]
                )
                .tag(0)

                WelcomePage(
                    systemImage: "lock.shield.fill",
                    title: "Private by design",
                    subtitle: "Your records belong to you and stay with you.",
                    points: [
                        WelcomePoint(
                            systemImage: "iphone",
                            title: "Stays on this iPhone",
                            detail: "No account, no cloud and no tracking or ads. Nothing is sent to a server."
                        ),
                        WelcomePoint(
                            systemImage: AppLock.biometryName == "Touch ID" ? "touchid" : "faceid",
                            title: "Locked with \(AppLock.biometryName)",
                            detail: "The app asks for \(AppLock.biometryName) or your passcode each time it opens. You can change this in Settings."
                        ),
                        WelcomePoint(
                            systemImage: "lock.doc.fill",
                            title: "Encrypted backups",
                            detail: "Back up to a file locked with a password you choose. You keep the file, and only that password opens it."
                        ),
                    ]
                )
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 8) {
                Button {
                    if page == 0 {
                        withAnimation { page = 1 }
                    } else {
                        onDone()
                    }
                } label: {
                    Text(page == 0 ? "Next" : "Get started")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .primaryButton()
                .controlSize(.large)

                Button("Skip") { onDone() }
                    .minimumTapTarget()
                    .opacity(page == 0 ? 1 : 0)
                    .disabled(page != 0)
                    .accessibilityHidden(page != 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

private struct WelcomePoint: Identifiable {
    let systemImage: String
    let title: String
    let detail: String
    var id: String { title }
}

private struct WelcomePage: View {
    /// nil shows the app icon.
    let systemImage: String?
    let title: String
    let subtitle: String
    let points: [WelcomePoint]

    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 32

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 56))
                            .foregroundStyle(.tint)
                            .frame(height: 88)
                            .accessibilityHidden(true)
                    } else {
                        BrandMark(size: 88)
                    }
                    Text(title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 20) {
                    ForEach(points) { point in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: point.systemImage)
                                .font(.title2)
                                .foregroundStyle(.tint)
                                .frame(width: iconSize)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(point.title)
                                    .font(.headline)
                                Text(point.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 24)
            // Room for the page dots.
            .padding(.bottom, 48)
        }
    }
}

#Preview {
    WelcomeView {}
}
