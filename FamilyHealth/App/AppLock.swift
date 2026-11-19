import LocalAuthentication
import Observation
import SwiftUI

/// Keeps the app locked behind Face ID, Touch ID or the device passcode.
@MainActor
@Observable
final class AppLock {
    static let settingKey = "requireAuthentication"

    private(set) var isLocked: Bool
    private(set) var message: String?
    private var isAuthenticating = false

    /// `startsLocked` is false only on a brand-new install, while the welcome screen shows.
    init(startsLocked: Bool = true) {
        isLocked = startsLocked && AppLock.isEnabled
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    func lockIfEnabled() {
        if AppLock.isEnabled {
            isLocked = true
        }
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        guard AppLock.isEnabled else {
            isLocked = false
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode is set on this device, so there is nothing to check against.
            isLocked = false
            message = "Set a passcode on this iPhone to protect your records."
            return
        }

        do {
            if try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your family's health records"
            ) {
                isLocked = false
                message = nil
            }
        } catch {
            message = "Not unlocked. Tap Unlock to try again."
        }
    }

    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }
}

struct LockView: View {
    @Environment(AppLock.self) private var appLock

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Family Health Binder is locked")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let message = appLock.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await appLock.unlock() }
            } label: {
                Label("Unlock with \(AppLock.biometryName)", systemImage: "faceid")
                    .frame(maxWidth: 280)
            }
            .primaryButton()
            .controlSize(.large)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .task { await appLock.unlock() }
    }
}
