//
//  RootView.swift
//  Ocean Cast
//

import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var navigator = Navigator()

    var body: some View {
        Group {
            switch store.loadState {
            case .loading:
                LoadingScreen()
            case .failed(let message):
                LoadFailureScreen(message: message)
            case .ready:
                if store.data.onboardingCompleted {
                    MainShell()
                        .environment(navigator)
                        .transition(.opacity)
                } else {
                    OnboardingView()
                        .environment(navigator)
                        .transition(.opacity)
                }
            }
        }
        .animation(OceanMotion.soft, value: store.data.onboardingCompleted)
        .tint(Ocean.blue)
    }
}

private struct LoadingScreen: View {
    var body: some View {
        ZStack {
            OceanBackground()
            VStack(spacing: 18) {
                FloatDisc(symbol: "sparkles", tint: Ocean.blue, size: 72)
                Text("Opening your kitchen…")
                    .font(OceanFont.title(19))
                    .foregroundStyle(Ocean.ink)
                ProgressView().tint(Ocean.blue)
            }
        }
    }
}

private struct LoadFailureScreen: View {
    @Environment(AppStore.self) private var store
    var message: String

    var body: some View {
        ZStack {
            OceanBackground(tint: Ocean.coral)
            ScrollView {
                VStack(spacing: 18) {
                    ScreenHeader(eyebrow: "Storage", title: "Your saved data could not be opened",
                                 subtitle: "Nothing was deleted. Your file was kept so it can be recovered.",
                                 tint: Ocean.coral)
                    ErrorCard(title: "Read error", message: message, onRetry: { store.load() })
                    InfoNote(text: "If retrying does not help, you can import a backup from Settings once the app opens, or erase local data and start again. Both actions ask for confirmation first.",
                             tint: Ocean.coral)
                }
                .padding(20)
            }
        }
    }
}

// MARK: - Shell

struct MainShell: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var navigator

    var body: some View {
        @Bindable var nav = navigator

        ZStack(alignment: .bottom) {
            ZStack {
                tabStack(.home) {
                    NavigationStack(path: $nav.homePath) {
                        HomeView().navigationDestination(for: Route.self) { RouteDestination(route: $0) }
                    }
                }
                tabStack(.inventory) {
                    NavigationStack(path: $nav.inventoryPath) {
                        InventoryView().navigationDestination(for: Route.self) { RouteDestination(route: $0) }
                    }
                }
                tabStack(.meals) {
                    NavigationStack(path: $nav.mealsPath) {
                        MealsView().navigationDestination(for: Route.self) { RouteDestination(route: $0) }
                    }
                }
                tabStack(.shopping) {
                    NavigationStack(path: $nav.shoppingPath) {
                        ShoppingPlanView().navigationDestination(for: Route.self) { RouteDestination(route: $0) }
                    }
                }
                tabStack(.alerts) {
                    NavigationStack(path: $nav.alertsPath) {
                        RecallCenterView().navigationDestination(for: Route.self) { RouteDestination(route: $0) }
                    }
                }
            }

            OceanTabBar(selection: $nav.tab,
                        shoppingBadge: store.neededShopping.count,
                        alertsBadge: store.unconfirmedRecallMatches.count)
        }
        .sheet(item: $nav.sheet) { sheet in
            switch sheet {
            case .householdSetup:
                HouseholdSetupView()
            case .addProduct(let barcode):
                AddProductView(initialBarcode: barcode)
            case .receiptImport:
                ReceiptImportView()
            case .mealBuilder(let mealID):
                MealBuilderView(mealID: mealID)
            case .settings:
                SettingsView()
            case .profile:
                ProfileView()
            }
        }
    }

    @ViewBuilder
    private func tabStack<Content: View>(_ tab: RootTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(navigator.tab == tab ? 1 : 0)
            .allowsHitTesting(navigator.tab == tab)
            .accessibilityHidden(navigator.tab != tab)
    }
}

// MARK: - Tab bar

struct OceanTabBar: View {
    @Binding var selection: RootTab
    var shoppingBadge: Int
    var alertsBadge: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RootTab.allCases) { tab in
                item(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Ocean.surface)
                .overlay(Capsule().strokeBorder(Ocean.tide.opacity(0.16), lineWidth: 1.4))
                .shadow(color: Ocean.ink.opacity(0.16), radius: 18, y: 8)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private func badge(for tab: RootTab) -> Int {
        switch tab {
        case .shopping: return shoppingBadge
        case .alerts: return alertsBadge
        default: return 0
        }
    }

    @ViewBuilder
    private func item(_ tab: RootTab) -> some View {
        let isOn = selection == tab
        Button {
            Haptics.tap()
            withAnimation(OceanMotion.pop) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        if isOn {
                            Circle()
                                .fill(OceanGradient.token(tab.tint))
                                .frame(width: 38, height: 38)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.2))
                                .shadow(color: tab.tint.opacity(0.4), radius: 7, y: 3)
                        }
                        Image(systemName: tab.symbol)
                            .font(.system(size: isOn ? 16 : 17, weight: .bold))
                            .foregroundStyle(isOn ? Color.white : Ocean.inkFaint)
                    }
                    .frame(width: 38, height: 38)

                    let count = badge(for: tab)
                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.system(size: 9.5, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Ocean.blue))
                            .overlay(Capsule().strokeBorder(Color.white, lineWidth: 1.2))
                            .offset(x: 6, y: -2)
                    }
                }
                Text(tab.title)
                    .font(.system(size: 10, weight: isOn ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(isOn ? Ocean.ink : Ocean.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}
