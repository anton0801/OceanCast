import SwiftUI

struct ContentView: View {
    @Environment(NetworkGate.self) private var gate
    @Environment(AppBootstrap.self) private var bootstrap
    @Environment(AppFlow.self) private var flow

    var body: some View {
        ZStack {
            routed
            if gate.isBlocked {
                NoConnectionView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(OceanMotion.soft, value: gate.isBlocked)
        .animation(OceanMotion.soft, value: flow.route)
        .task { await advanceWhenReady() }
    }

    @ViewBuilder private var routed: some View {
        switch flow.route {
        case .splash:
            SplashView()
        case .specialOfferForAccount:
            NotificationOfferView()
        case .specialOfferForAccountAccepted:
            WaveView()
        case .normal:
            RootView()
        }
    }

    private func advanceWhenReady() async {
        bootstrap.run()
        await bootstrap.waitUntilFinished()
        let elapsed = Date().timeIntervalSince(flow.splashStart)
        let remaining = BeaconConfig.minimumSplash - elapsed
        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
        }
        flow.leaveSplash(with: bootstrap.result)
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
        .environment(NetworkMonitor())
        .environment(NetworkGate())
        .environment(NotificationService())
        .environment(AuthStore())
        .environment(SyncService())
        .environment(AppBootstrap())
        .environment(AppFlow())
}
