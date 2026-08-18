//
//  HomeView.swift
//  Ocean Cast
//
//  SCREEN 1 — Stock dashboard. Every number here is computed from active
//  batches; tapping one opens the records it came from.
//

import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(NetworkMonitor.self) private var network
    @Environment(AuthStore.self) private var auth
    @Environment(SyncService.self) private var sync

    @State private var toast: ToastMessage?

    private var isEmpty: Bool { store.data.batches.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if !network.isOnline {
                    OfflineBanner(lastUpdated: store.data.recallLastCheckedAt)
                }

                if isEmpty {
                    emptyState
                } else {
                    nextActionCard
                    quickActions
                    widgets
                    footerStamp
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .background(OceanBackground(tint: Ocean.blue))
        .toastHost($toast)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { navigator.open(.insights) } label: { Label("Insights", systemImage: "chart.bar.fill") }
                    Button { navigator.open(.activity) } label: { Label("Activity history", systemImage: "clock.arrow.circlepath") }
                    Button { navigator.open(.archive) } label: { Label("Archive", systemImage: "archivebox.fill") }
                    Divider()
                    Button { navigator.open(.householdSetup) } label: { Label("Household setup", systemImage: "house.fill") }
                    Button { navigator.open(.profile) } label: {
                        Label(auth.isSignedIn ? "Profile & sync" : "Sign in to sync",
                              systemImage: "person.crop.circle.fill")
                    }
                    Button { navigator.open(.settings) } label: { Label("Settings & data", systemImage: "gearshape.fill") }
                    if !store.data.settings.hiddenHomeWidgets.isEmpty {
                        Divider()
                        Button {
                            store.mutate { $0.settings.hiddenHomeWidgets.removeAll() }
                            toast = ToastMessage(kind: .info, title: "All widgets shown again")
                        } label: {
                            Label("Show hidden widgets (\(store.data.settings.hiddenHomeWidgets.count))",
                                  systemImage: "eye.fill")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Ocean.ink)
                }
            }
        }
        .oceanTabInset()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((store.household?.name ?? "Ocean Cast").uppercased())
                .font(OceanFont.caption(11))
                .tracking(1.2)
                .foregroundStyle(Ocean.blue)
            Text(isEmpty ? "Build a Kitchen That Remembers" : "Your kitchen right now")
                .font(OceanFont.display(30))
                .foregroundStyle(Ocean.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !isEmpty {
                Text("\(store.activeBatches.count) active batch(es) · \(store.data.batches.count - store.activeBatches.count) archived or used up")
                    .font(OceanFont.body(14))
                    .foregroundStyle(Ocean.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            WaveCard(tint: Ocean.blue, padding: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        FloatDisc(symbol: "sparkles", tint: Ocean.blue, size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No items yet").font(OceanFont.title(19)).foregroundStyle(Ocean.ink)
                            Text("This screen fills in from your own records.")
                                .font(OceanFont.caption(12.5)).foregroundStyle(Ocean.inkSoft)
                        }
                    }
                    Text("Add one product and Home starts showing real numbers: what is expiring, what is reserved for meals and what is left to buy. Nothing here is a sample — the app never writes demo data for you.")
                        .font(OceanFont.body(14.5))
                        .foregroundStyle(Ocean.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    OceanButton(title: "Scan Item", symbol: "barcode.viewfinder") {
                        navigator.sheet = .addProduct(barcode: nil)
                    }
                    HStack(spacing: 10) {
                        OceanButton(title: "Add Manually", symbol: "square.and.pencil",
                                    kind: .secondary, tint: Ocean.turquoise) {
                            navigator.sheet = .addProduct(barcode: nil)
                        }
                        OceanButton(title: "Import Receipt", symbol: "doc.text.viewfinder",
                                    kind: .ghost) {
                            navigator.sheet = .receiptImport
                        }
                    }
                }
            }

            if store.household == nil {
                EmptyStateCard(symbol: "house.fill",
                               title: "No household yet",
                               message: "Storage zones, currency and members live in the household. Create it first so batches can be filed correctly.",
                               actionTitle: "Create Household",
                               tint: Ocean.coral) {
                    navigator.sheet = .householdSetup
                }
            }
        }
    }

    // MARK: - Next action

    @ViewBuilder
    private var nextActionCard: some View {
        if let action = store.nextAction {
            Button {
                Haptics.tap()
                if let route = action.route { navigator.open(route) }
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    FloatDisc(symbol: action.symbol, tint: Ocean.sky, size: 46)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("NEXT ACTION")
                            .font(OceanFont.caption(10.5)).tracking(1.1)
                            .foregroundStyle(Ocean.ink.opacity(0.65))
                        Text(action.title)
                            .font(OceanFont.title(19))
                            .foregroundStyle(Ocean.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(action.detail)
                            .font(OceanFont.body(13.5))
                            .foregroundStyle(Ocean.ink.opacity(0.75))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Ocean.ink.opacity(0.6))
                        .padding(.top, 6)
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)
                        .fill(OceanGradient.cta)
                        .overlay(RoundedRectangle(cornerRadius: OceanRadius.card, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5))
                        .shadow(color: Ocean.blue.opacity(0.32), radius: 16, y: 8)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                OceanChip(title: "Scan Item", symbol: "barcode.viewfinder", tint: Ocean.blue) {
                    navigator.sheet = .addProduct(barcode: nil)
                }
                OceanChip(title: "Add Manually", symbol: "square.and.pencil", tint: Ocean.turquoise) {
                    navigator.sheet = .addProduct(barcode: nil)
                }
                OceanChip(title: "Review Expiring", symbol: "clock.fill", tint: Ocean.coral,
                          badge: store.expiringSoon.count) {
                    navigator.push(.expiryReview)
                }
                OceanChip(title: "Build a Meal", symbol: "fork.knife", tint: Ocean.tide) {
                    navigator.sheet = .mealBuilder(mealID: nil)
                }
                OceanChip(title: "Open Shopping List", symbol: "cart.fill", tint: Ocean.sky,
                          badge: store.neededShopping.count) {
                    navigator.open(.shopping)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Widgets

    private var hidden: Set<String> { store.data.settings.hiddenHomeWidgets }

    private var widgets: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                if !hidden.contains("expiring") { expiringTile }
                if !hidden.contains("lowStock") { lowStockTile }
                if !hidden.contains("meals") { mealsTile }
                if !hidden.contains("shopping") { shoppingTile }
            }

            if !hidden.contains("recalls") { recallCard }
            if !store.undatedBatches.isEmpty { undatedCard }
        }
    }

    private var expiringTile: some View {
        StatTile(value: "\(store.expiringSoon.count)",
                 label: "Expiring soon (your dates, ≤\(store.data.settings.expiryWindowDays) days)",
                 symbol: "clock.fill",
                 tint: Ocean.coral,
                 note: store.undatedBatches.isEmpty ? nil : "\(store.undatedBatches.count) item(s) have no date") {
            navigator.push(.expiryReview)
        }
        .contextMenu { hideButton("expiring") }
    }

    private var lowStockTile: some View {
        Group {
            if store.hasAnyThreshold {
                StatTile(value: "\(store.lowStockLines.count)",
                         label: "Low stock against your thresholds",
                         symbol: "arrow.down.circle.fill",
                         tint: Ocean.turquoise) {
                    navigator.inventoryFilter = .lowStock
                    navigator.open(.inventory)
                }
            } else {
                StatTile(value: "—",
                         label: "Low stock",
                         symbol: "arrow.down.circle.fill",
                         tint: Ocean.turquoise,
                         note: "No threshold set — tap to set one") {
                    navigator.inventoryFilter = .all
                    navigator.open(.inventory)
                }
            }
        }
        .contextMenu { hideButton("lowStock") }
    }

    private var mealsTile: some View {
        StatTile(value: "\(store.plannedMeals.count)",
                 label: "Planned meals holding reservations",
                 symbol: "fork.knife",
                 tint: Ocean.tide,
                 note: store.data.reservations.isEmpty ? nil : "\(store.data.reservations.count) reservation(s)") {
            navigator.open(.meals)
        }
        .contextMenu { hideButton("meals") }
    }

    private var shoppingTile: some View {
        let estimate = store.shoppingEstimate
        return StatTile(value: "\(estimate.total)",
                        label: "Items to buy",
                        symbol: "cart.fill",
                        tint: Ocean.sky,
                        note: estimate.total == 0
                            ? nil
                            : (estimate.withPrice == 0
                               ? "No target prices set — total unknown"
                               : "\(store.money(estimate.known) ?? "—") from \(estimate.withPrice)/\(estimate.total) priced")) {
            navigator.open(.shopping)
        }
        .contextMenu { hideButton("shopping") }
    }

    private var recallCard: some View {
        let pending = store.unconfirmedRecallMatches.count
        let checked = store.data.recallLastCheckedAt
        return Button {
            Haptics.tap()
            navigator.open(.recalls)
        } label: {
            WaveCard(tint: pending > 0 ? Ocean.coral : Ocean.turquoise) {
                HStack(spacing: 14) {
                    FloatDisc(symbol: pending > 0 ? "exclamationmark.shield.fill" : "checkmark.shield.fill",
                              tint: pending > 0 ? Ocean.coral : Ocean.turquoise, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pending > 0 ? "\(pending) recall notice(s) need your check" : "Recall alerts")
                            .font(OceanFont.headline(15.5))
                            .foregroundStyle(Ocean.ink)
                        Text(checked == nil
                             ? "Not checked yet — open to fetch official notices"
                             : "Last checked \(DateFormat.stamp(checked!))")
                            .font(OceanFont.caption(11.5))
                            .foregroundStyle(Ocean.inkSoft)
                    }
                    Spacer(minLength: 0)
                    RowChevron()
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu { hideButton("recalls") }
    }

    private var undatedCard: some View {
        Button {
            navigator.inventoryFilter = .all
            navigator.open(.inventory)
        } label: {
            InfoNote(text: "\(store.undatedBatches.count) batch(es) have no date you entered. They are counted in stock but stay out of expiry numbers — they are Unknown, not fresh.",
                     symbol: "questionmark.circle.fill",
                     tint: Ocean.tide)
        }
        .buttonStyle(.plain)
    }

    private func hideButton(_ key: String) -> some View {
        Button(role: .destructive) {
            store.mutate { $0.settings.hiddenHomeWidgets.insert(key) }
            toast = ToastMessage(kind: .info, title: "Widget hidden",
                                 detail: "Your records are untouched. Restore it from the ⋯ menu.")
        } label: {
            Label("Hide this widget", systemImage: "eye.slash.fill")
        }
    }

    private var footerStamp: some View {
        HStack(spacing: 8) {
            SourceStampView(source: "This device (local records)",
                            updated: store.lastSavedAt,
                            isCached: !network.isOnline)
            Spacer()
        }
        .padding(.top, 2)
    }
}
