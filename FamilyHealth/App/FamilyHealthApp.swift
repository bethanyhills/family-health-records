import SwiftData
import SwiftUI

@main
struct FamilyHealthApp: App {
    @State private var appLock = AppLock()
    private let container = ModelStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appLock)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(AppLock.self) private var appLock
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            PeopleListView()

            if appLock.isLocked {
                LockView()
                    .transition(.opacity)
            } else if scenePhase != .active {
                // Hides records in the app switcher.
                PrivacyCover()
            }
        }
        .animation(.default, value: appLock.isLocked)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                appLock.lockIfEnabled()
            case .active:
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
            Rectangle().fill(.background)
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
        }
        .ignoresSafeArea()
    }
}
