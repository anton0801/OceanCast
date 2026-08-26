import SwiftUI

@main
struct SugarBloomApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()
    @State private var network = NetworkMonitor()
    @State private var networkGate = NetworkGate()
    @State private var notifications = NotificationService()
    @State private var auth = AuthStore()
    @State private var sync = SyncService()
    @State private var bootstrap = AppBootstrap()
    @State private var flow = AppFlow()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(network)
                .environment(networkGate)
                .environment(notifications)
                .environment(auth)
                .environment(sync)
                .environment(bootstrap)
                .environment(flow)
                .task {
                    KeychainStore.purgeIfReinstalled()
                    await notifications.refreshStatus()
                    await auth.restore()
                    if auth.isSignedIn {
                        await sync.syncNow(store: store, auth: auth)
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    guard auth.isSignedIn else { return }
                    await sync.syncNow(store: store, auth: auth)
                }
            default:
                store.saveNow()
            }
        }
    }

}
