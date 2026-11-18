import SwiftUI

/// The one-time purchase sheet. No subscription, no pop-ups: it opens only
/// when someone taps Unlock.
struct UnlockView: View {
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    BrandMark(size: 72)
                        .padding(.top, 24)

                    VStack(spacing: 6) {
                        Text("Unlock Family Health Binder")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text("One payment, shared with your Family Sharing group. No subscription.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Add and edit records for the whole family", systemImage: "checkmark.circle.fill")
                        Label("Documents, visit notes and search", systemImage: "checkmark.circle.fill")
                        Label("Intake summary, PDF, backup and sharing", systemImage: "checkmark.circle.fill")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))

                    if purchases.status == .unlocked {
                        Label("Unlocked. Thank you!", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            Task { await purchases.purchase() }
                        } label: {
                            Group {
                                if purchases.isPurchasing {
                                    ProgressView()
                                } else {
                                    Text(purchases.unlockTitle)
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(purchases.isPurchasing)

                        Button("Restore purchase") {
                            Task { await purchases.restore() }
                        }
                    }

                    Text("Your records stay on this iPhone and remain viewable and exportable whether or not you unlock.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(purchases.status == .unlocked ? "Done" : "Not now") { dismiss() }
                }
            }
            .task { await purchases.loadProduct() }
            .purchaseAlert(purchases)
            .onChange(of: purchases.isUnlocked) { _, unlocked in
                if unlocked { dismiss() }
            }
        }
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
        case .unlocked:
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
                        Text(purchases.price.map { "Unlock for good: \($0) once" } ?? "Unlock for good with one payment")
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
                    Text("Records stay viewable and exportable. Unlock to add or edit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Unlock", action: onUnlock)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
    }
}

/// Settings: where the trial stands, with Unlock and Restore. The unlock
/// sheet is attached to the settings page, because a sheet attached to a
/// list section closes itself.
struct PurchaseSection: View {
    let onUnlock: () -> Void
    @Environment(Purchases.self) private var purchases

    var body: some View {
        Section {
            switch purchases.status {
            case .unlocked:
                Label("Unlocked. Thank you!", systemImage: "checkmark.seal.fill")
            case .trial(let daysLeft):
                Label(TrialPolicy.daysLeftText(daysLeft), systemImage: "star")
            case .ended:
                Label("Trial ended. Records stay viewable.", systemImage: "lock")
            }
            if purchases.status != .unlocked {
                Button(purchases.unlockTitle, action: onUnlock)
                Button("Restore purchase") {
                    Task { await purchases.restore() }
                }
            }
        } header: {
            Text("Purchase")
        } footer: {
            Text("Free for \(TrialPolicy.length) days with everything included, then one payment to keep adding and editing. No subscription.")
        }
    }
}

extension View {
    /// Shows a purchase or restore message from `Purchases`.
    @MainActor
    func purchaseAlert(_ purchases: Purchases, when isActive: Bool = true) -> some View {
        alert(
            "Unlock",
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
