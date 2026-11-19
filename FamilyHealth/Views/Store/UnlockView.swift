import SwiftUI

/// Links Apple requires on a subscription screen.
enum PlanLinks {
    /// Apple's standard license agreement, which the app uses as its terms.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://bethanyhills.github.io/familyhealthbinder/privacy.html")!
    /// Apple's own page for cancelling or changing a subscription.
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
}

/// The plans screen: annual (with Apple's free trial) or lifetime.
/// It opens by itself once, after the first family member is added, and
/// otherwise only when someone taps a plans button.
struct UnlockView: View {
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Purchases.Plan = .annual

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    BrandMark(size: 64)
                        .padding(.top, 16)

                    VStack(spacing: 6) {
                        Text(title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Add and edit records for the whole family", systemImage: "checkmark.circle.fill")
                        Label("Documents, scans, visit notes and search", systemImage: "checkmark.circle.fill")
                        Label("Intake summary, PDF, backup and sharing", systemImage: "checkmark.circle.fill")
                        Label("Covers your Family Sharing group", systemImage: "checkmark.circle.fill")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))

                    switch purchases.status {
                    case .lifetime:
                        Label("You have lifetime access. Thank you!", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                    case .subscribed(let until):
                        subscribedNote(until: until)
                        planCard(.lifetime)
                        buyButton
                    case .trial, .ended:
                        planCard(.annual)
                        planCard(.lifetime)
                        buyButton
                    }

                    if purchases.status != .lifetime {
                        Button("Restore purchases") {
                            Task { await purchases.restore() }
                        }
                    }

                    if selection == .annual, !purchases.status.hasPlan {
                        Text(TrialPolicy.renewalTerms(yearlyPrice: purchases.annualPrice, freeTrial: purchases.freeTrialText))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text("Your records stay on this iPhone and remain viewable and exportable whether or not you choose a plan.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 20) {
                        Link("Terms of Use", destination: PlanLinks.terms)
                        Link("Privacy Policy", destination: PlanLinks.privacy)
                    }
                    .font(.footnote)
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(purchases.status.hasPlan ? "Done" : "Not now") { dismiss() }
                }
            }
            .onAppear {
                // Someone on the annual plan can only switch to lifetime.
                if case .subscribed = purchases.status { selection = .lifetime }
            }
            .task { await purchases.loadProducts() }
            .purchaseAlert(purchases)
            .onChange(of: purchases.status) { old, new in
                // Close once a purchase goes through (a new plan, or annual to lifetime).
                if new.hasPlan, new != old { dismiss() }
            }
        }
    }

    private var title: String {
        switch purchases.status {
        case .lifetime: "Family Health Binder"
        case .subscribed: "Your plan"
        case .trial: "Choose a plan"
        case .ended: "Your trial has ended"
        }
    }

    private var subtitle: String {
        switch purchases.status {
        case .lifetime, .subscribed:
            "Everything is included, for everyone in your Family Sharing group."
        case .trial(let daysLeft):
            "\(TrialPolicy.daysLeftText(daysLeft)). Pick a plan now and keep going without a break."
        case .ended:
            "Pick a plan to keep adding and editing. Nothing has been deleted."
        }
    }

    private func subscribedNote(until: Date) -> some View {
        VStack(spacing: 8) {
            Label("Annual plan, active through \(until.formatted(date: .abbreviated, time: .omitted))", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Link("Manage or cancel your subscription", destination: PlanLinks.manageSubscriptions)
                .font(.subheadline)
            Text("Rather pay once? Switch to lifetime below, then cancel the annual plan.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func planCard(_ plan: Purchases.Plan) -> some View {
        let isSelected = selection == plan
        return Button {
            selection = plan
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(plan == .annual ? "Annual" : "Lifetime")
                            .font(.headline)
                        if plan == .annual, let trial = purchases.freeTrialText {
                            Text("\(trial) free")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Theme.amber.opacity(0.2), in: Capsule())
                        }
                    }
                    Text(planDetail(plan))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(planPrice(plan))
                    .font(.headline)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func planPrice(_ plan: Purchases.Plan) -> String {
        switch plan {
        case .annual: purchases.annualPrice.map { "\($0)/yr" } ?? ""
        case .lifetime: purchases.lifetimePrice ?? ""
        }
    }

    private func planDetail(_ plan: Purchases.Plan) -> String {
        switch plan {
        case .annual: "Renews each year. Cancel anytime."
        case .lifetime: "Pay once. Yours for good."
        }
    }

    private var buyTitle: String {
        switch selection {
        case .annual:
            if let trial = purchases.freeTrialText { return "Start \(trial) free" }
            return purchases.annualPrice.map { "Subscribe for \($0) a year" } ?? "Subscribe"
        case .lifetime:
            return purchases.lifetimePrice.map { "Buy lifetime for \($0)" } ?? "Buy lifetime"
        }
    }

    private var buyButton: some View {
        Button {
            Task { await purchases.purchase(selection) }
        } label: {
            Group {
                if purchases.isPurchasing {
                    ProgressView()
                } else {
                    Text(buyTitle)
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .disabled(purchases.isPurchasing)
    }
}

/// The quiet banner on the Family screen (last days of the trial, or after it)
/// and at the top of a person's page once the trial has ended.
struct TrialBanner: View {
    let status: TrialStatus
    let onUnlock: () -> Void
    @Environment(Purchases.self) private var purchases

    var body: some View {
        switch status {
        case .lifetime, .subscribed:
            EmptyView()
        case .trial(let daysLeft):
            Button(action: onUnlock) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TrialPolicy.daysLeftText(daysLeft))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Everything works during the trial.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(purchases.plansFromText)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                } icon: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.purple)
                }
            }
            .buttonStyle(.plain)
        case .ended:
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your trial has ended")
                        .font(.subheadline.weight(.semibold))
                    Text("Records stay viewable and exportable. Choose a plan to add or edit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("See plans", action: onUnlock)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
    }
}

/// Settings: where the trial or plan stands, with plans, manage and restore.
/// The plans sheet is attached to the settings page, because a sheet
/// attached to a list section closes itself.
struct PurchaseSection: View {
    let onUnlock: () -> Void
    @Environment(Purchases.self) private var purchases

    var body: some View {
        Section {
            switch purchases.status {
            case .lifetime:
                Label("Lifetime access. Thank you!", systemImage: "checkmark.seal.fill")
            case .subscribed(let until):
                Label("Annual plan, active through \(until.formatted(date: .abbreviated, time: .omitted))", systemImage: "checkmark.seal.fill")
                Link("Manage or cancel subscription", destination: PlanLinks.manageSubscriptions)
                Button("Switch to lifetime", action: onUnlock)
            case .trial(let daysLeft):
                Label(TrialPolicy.daysLeftText(daysLeft), systemImage: "star")
                Button("See plans", action: onUnlock)
            case .ended:
                Label("Trial ended. Records stay viewable.", systemImage: "lock")
                Button("See plans", action: onUnlock)
            }
            if purchases.status != .lifetime {
                Button("Restore purchases") {
                    Task { await purchases.restore() }
                }
            }
        } header: {
            Text("Plan")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        let annual = purchases.annualPrice.map { "\($0) a year" } ?? "a yearly plan"
        let lifetime = purchases.lifetimePrice.map { "\($0) once" } ?? "a one-time lifetime price"
        return "Free for \(TrialPolicy.length) days with everything included, then \(annual) or \(lifetime). Both cover your Family Sharing group, and records always stay viewable and exportable."
    }
}

extension View {
    /// Shows a purchase or restore message from `Purchases`.
    @MainActor
    func purchaseAlert(_ purchases: Purchases, when isActive: Bool = true) -> some View {
        alert(
            "Purchase",
            isPresented: Binding(
                get: { isActive && purchases.message != nil },
                set: { if !$0 { purchases.message = nil } }
            )
        ) {
            Button("OK") { purchases.message = nil }
        } message: {
            Text(purchases.message ?? "")
        }
    }
}
