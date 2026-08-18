//
//  SugarBloomApp.swift
//  Ocean Cast
//

import SwiftUI

@main
struct SugarBloomApp: App {
    @State private var store = AppStore()
    @State private var network = NetworkMonitor()
    @State private var notifications = NotificationService()
    @State private var auth = AuthStore()
    @State private var sync = SyncService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(network)
                .environment(notifications)
                .environment(auth)
                .environment(sync)
                .task {
                    KeychainStore.purgeIfReinstalled()
                    await notifications.refreshStatus()
                    // Restoring a session is a network call: the UI is already
                    // usable from local records while it runs.
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
