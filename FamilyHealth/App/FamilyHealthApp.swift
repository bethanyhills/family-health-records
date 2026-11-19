import SwiftData
import SwiftUI

@main
struct FamilyHealthApp: App {
    @State private var appLock: AppLock
    @State private var purchases = Purchases()
    private let container: ModelContainer

    init() {
        let container = ModelStore.makeContainer()
        self.container = container
        let defaults = UserDefaults.standard
        let hasPeople = ((try? container.mainContext.fetchCount(FetchDescriptor<Person>())) ?? 0) > 0
        let showsWelcome = Welcome.shouldShow(hasSeen: defaults.bool(forKey: Welcome.seenKey), hasPeople: hasPeople)
        if !showsWelcome {
            // People who had the app before the welcome screen existed skip it.
            defaults.set(true, forKey: Welcome.seenKey)
        }
        // A brand-new install has nothing to protect yet, so the welcome screen
        // comes first and Face ID starts on the next launch.
        _appLock = State(initialValue: AppLock(startsLocked: !showsWelcome))
    }

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
    @AppStorage(Welcome.seenKey) private var hasSeenWelcome = false

    var body: some View {
        ZStack {
            PeopleListView()
                .environment(\.recordAccess, purchases.access)
                // VoiceOver can otherwise read records hidden behind the lock screen.
                .accessibilityHidden(appLock.isLocked || !hasSeenWelcome)

            if !hasSeenWelcome {
                WelcomeView { hasSeenWelcome = true }
                    .transition(.opacity)
                    .accessibilityHidden(appLock.isLocked)
            }

            if appLock.isLocked {
                LockView()
                    .transition(.opacity)
            } else if scenePhase != .active {
                // Hides records in the app switcher.
                PrivacyCover()
            }
        }
        .animation(.default, value: appLock.isLocked)
        .animation(.default, value: hasSeenWelcome)
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
