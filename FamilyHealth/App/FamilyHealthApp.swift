import SwiftData
import SwiftUI

@main
struct FamilyHealthApp: App {
    @State private var appLock = AppLock()
    @State private var purchases = Purchases()
    private let container = ModelStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appLock)
                .environment(purchases)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(AppLock.self) private var appLock
    @Environment(Purchases.self) private var purchases
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            PeopleListView()
                .environment(\.recordAccess, purchases.access)

            if appLock.isLocked {
                LockView()
                    .transition(.opacity)
            } else if scenePhase != .active {
                // Hides records in the app switcher.
                PrivacyCover()
            }
        }
        .animation(.default, value: appLock.isLocked)
        .task { await purchases.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                appLock.lockIfEnabled()
            case .active:
                purchases.now = .now
                Task { await appLock.unlock() }
            default:
                break
            }
        }
    }
}

struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Theme.background)
            BrandMark(size: 80)
        }
        .ignoresSafeArea()
    }
}
