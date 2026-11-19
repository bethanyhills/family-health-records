import SwiftUI

/// Links Apple requires on a subscription screen.
enum PlanLinks {
    /// Apple's standard license agreement, which the app uses as its terms.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://bethanyhills.github.io/familyhealthbinder/privacy.html")!
    /// Apple's own page for cancelling or changing a subscription.
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
}

/// The plans screen: annual (starting with Apple's free trial) or lifetime.
/// On a new install the Family screen's first button opens it, so the free
/// trial starts on day one.
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
                            .foregroundStyle(Theme.success)
                    case .subscribed(let until, let inFreeTrial):
                        subscribedNote(until: until, inFreeTrial: inFreeTrial)
                        planCard(.lifetime)
                        buyButton
                    case .noPlan:
                        planCard(.annual)
                        planCard(.lifetime)
                        buyButton
                    }

                    if selection == .annual, !purchases.status.hasPlan {
                        Text(PlanPolicy.renewalTerms(yearlyPrice: purchases.annualPrice, freeTrial: purchases.freeTrialText))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if purchases.status != .lifetime {
                        Button("Restore purchases") {
                            Task { await purchases.restore() }
                        }
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
        case .noPlan: purchases.freeTrialText.map { "Try everything free for \($0)" } ?? "Choose a plan"
        }
    }

    private var subtitle: String {
        switch purchases.status {
        case .lifetime, .subscribed:
            "Everything is included, for everyone in your Family Sharing group."
        case .noPlan:
            purchases.freeTrialText == nil
                ? "Pick a plan to add and edit records. Anything you've already entered stays viewable and exportable."
                : "Start the free trial now. Cancel before it ends and you won't be charged."
        }
    }

    private func subscribedNote(until: Date, inFreeTrial: Bool) -> some View {
        VStack(spacing: 8) {
            Label(
                inFreeTrial
                    ? PlanPolicy.trialEndsText(until: until, now: purchases.now)
                    : "Annual plan, renews \(until.formatted(date: .abbreviated, time: .omitted))",
                systemImage: "checkmark.seal.fill"
            )
            .font(.headline)
            .foregroundStyle(Theme.success)
            .multilineTextAlignment(.center)
            if inFreeTrial {
                Text(purchases.annualPrice.map { "Then \($0) a year, starting \(until.formatted(date: .abbreviated, time: .omitted))." } ?? "Then the annual price, starting \(until.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
            if purchases.freeTrialText != nil { return "Start free trial" }
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
        .primaryButton()
        .disabled(purchases.isPurchasing)
    }
}

/// The banner on the Family screen and at the top of a person's page:
/// - no plan: records are view-only, with a button to the plans;
/// - the last days of Apple's free trial: when the first charge comes, so
///   it's never a surprise.
struct PlanBanner: View {
    let status: PlanStatus
    let onShowPlans: () -> Void
    @Environment(Purchases.self) private var purchases

    var body: some View {
        switch status {
        case .lifetime:
            EmptyView()
        case .subscribed(let until, let inFreeTrial):
            if inFreeTrial {
                Button(action: onShowPlans) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(PlanPolicy.trialEndsText(until: until, now: purchases.now))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(purchases.annualPrice.map { "Your annual plan (\($0) a year) starts \(until.formatted(date: .abbreviated, time: .omitted)). Cancel anytime before then and you won't be charged." }
                                 ?? "Your annual plan starts \(until.formatted(date: .abbreviated, time: .omitted)). Cancel anytime before then and you won't be charged.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.purple)
                    }
                }
                .buttonStyle(.plain)
            }
        case .noPlan:
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("View only")
                        .font(.subheadline.weight(.semibold))
                    Text("Records stay viewable and exportable. Choose a plan to add or edit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("See plans", action: onShowPlans)
                    .primaryButton()
                    .buttonBorderShape(.capsule)
            }
        }
    }
}

/// Settings: the current plan, with plans, manage and restore. The plans
/// sheet is attached to the settings page, because a sheet attached to a
/// list section closes itself.
struct PurchaseSection: View {
    let onUnlock: () -> Void
    @Environment(Purchases.self) private var purchases

    var body: some View {
        Section {
            switch purchases.status {
            case .lifetime:
                Label("Lifetime access. Thank you!", systemImage: "checkmark.seal.fill")
            case .subscribed(let until, let inFreeTrial):
                Label(
                    inFreeTrial
                        ? PlanPolicy.trialEndsText(until: until, now: purchases.now)
                        : "Annual plan, renews \(until.formatted(date: .abbreviated, time: .omitted))",
                    systemImage: "checkmark.seal.fill"
                )
                Link("Manage or cancel subscription", destination: PlanLinks.manageSubscriptions)
                Button("Switch to lifetime", action: onUnlock)
            case .noPlan:
                Label("No plan. Records stay viewable.", systemImage: "lock")
                Button(purchases.startTitle, action: onUnlock)
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
        return "\(annual.prefix(1).uppercased())\(annual.dropFirst()) after a free trial, or \(lifetime). Both cover your Family Sharing group, and records always stay viewable and exportable."
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
