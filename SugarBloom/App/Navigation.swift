//
//  Navigation.swift
//  Ocean Cast
//

import SwiftUI
import Observation

enum RootTab: String, CaseIterable, Identifiable {
    case home, inventory, meals, shopping, alerts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .inventory: return "Inventory"
        case .meals: return "Meals"
        case .shopping: return "Shopping"
        case .alerts: return "Alerts"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .inventory: return "shippingbox.fill"
        case .meals: return "fork.knife"
        case .shopping: return "cart.fill"
        case .alerts: return "bell.fill"
        }
    }

    var tint: Color {
        switch self {
        case .home: return Ocean.blue
        case .inventory: return Ocean.turquoise
        case .meals: return Ocean.tide
        case .shopping: return Ocean.coral
        case .alerts: return Ocean.sky
        }
    }
}

enum Route: Hashable {
    // pushes
    case product(UUID)
    case meal(UUID)
    case expiryReview
    case ideas
    case priceHistory(key: String, name: String)
    case insights
    case activity
    case archive
    case recallDetail(String)
    case zones

    // tab jumps
    case home
    case inventory
    case meals
    case shopping
    case recalls

    // sheets
    case householdSetup
    case addProduct
    case receiptImport
    case mealBuilder
    case settings
    case profile
}

enum SheetRoute: Identifiable, Hashable {
    case householdSetup
    case addProduct(barcode: String?)
    case receiptImport
    case mealBuilder(mealID: UUID?)
    case settings
    case profile

    var id: String {
        switch self {
        case .householdSetup: return "household"
        case .addProduct(let barcode): return "add-\(barcode ?? "new")"
        case .receiptImport: return "receipt"
        case .mealBuilder(let id): return "meal-\(id?.uuidString ?? "new")"
        case .settings: return "settings"
        case .profile: return "profile"
        }
    }
}

enum InventoryFilter: String, CaseIterable, Identifiable, Hashable {
    case all, expiring, opened, reserved, lowStock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .expiring: return "Expiring"
        case .opened: return "Opened"
        case .reserved: return "Reserved"
        case .lowStock: return "Low Stock"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .expiring: return "clock.fill"
        case .opened: return "seal.fill"
        case .reserved: return "lock.fill"
        case .lowStock: return "arrow.down.circle.fill"
        }
    }
}

@MainActor
@Observable
final class Navigator {
    var tab: RootTab = .home
    var inventoryFilter: InventoryFilter = .all
    var homePath = NavigationPath()
    var inventoryPath = NavigationPath()
    var mealsPath = NavigationPath()
    var shoppingPath = NavigationPath()
    var alertsPath = NavigationPath()
    var sheet: SheetRoute?

    func push(_ route: Route) {
        switch tab {
        case .home: homePath.append(route)
        case .inventory: inventoryPath.append(route)
        case .meals: mealsPath.append(route)
        case .shopping: shoppingPath.append(route)
        case .alerts: alertsPath.append(route)
        }
    }

    func open(_ route: Route) {
        switch route {
        case .home: tab = .home
        case .inventory: tab = .inventory
        case .meals: tab = .meals
        case .shopping: tab = .shopping
        case .recalls: tab = .alerts
        case .householdSetup: sheet = .householdSetup
        case .addProduct: sheet = .addProduct(barcode: nil)
        case .receiptImport: sheet = .receiptImport
        case .mealBuilder: sheet = .mealBuilder(mealID: nil)
        case .settings: sheet = .settings
        case .profile: sheet = .profile
        default: push(route)
        }
    }

    func popToRoot() {
        switch tab {
        case .home: homePath = NavigationPath()
        case .inventory: inventoryPath = NavigationPath()
        case .meals: mealsPath = NavigationPath()
        case .shopping: shoppingPath = NavigationPath()
        case .alerts: alertsPath = NavigationPath()
        }
    }
}

/// Maps a pushed route to its screen.
struct RouteDestination: View {
    var route: Route

    var body: some View {
        switch route {
        case .product(let id): ProductDetailView(batchID: id)
        case .meal(let id): MealDetailView(mealID: id)
        case .expiryReview: ExpiryReviewView()
        case .ideas: SmartUseIdeasView()
        case .priceHistory(let key, let name): PriceHistoryView(productKey: key, productName: name)
        case .insights: InsightsView()
        case .activity: ActivityLogView(filter: .all)
        case .archive: ArchiveView()
        case .recallDetail(let id): RecallDetailView(alertID: id)
        case .zones: ZoneManagerView()
        default: EmptyView()
        }
    }
}
