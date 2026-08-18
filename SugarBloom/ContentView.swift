//
//  ContentView.swift
//  Ocean Cast
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        RootView()
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
        .environment(NetworkMonitor())
        .environment(NotificationService())
        .environment(AuthStore())
        .environment(SyncService())
}
