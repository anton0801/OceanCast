//
//  InventoryView.swift
//  Ocean Cast
//
//  SCREEN 5 — Batches by zone, with filters that never merge different dates
//  or prices into one number.
//

import SwiftUI

struct InventoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(NetworkMonitor.self) private var network

    enum SortOption: String, CaseIterable, Identifiable {
        case date, name, quantity, added
        var id: String { rawValue }
        var title: String {
            switch self {
            case .date: return "Your date"
            case .name: return "Name"
            case .quantity: return "Quantity"
            case .added: return "Recently added"
            }
        }
    }

    @State private var sort: SortOption = .date
    @State private var search = ""
    @State private var expanded: Set<String> = []
    @State private var adjustBatchID: UUID?
    @State private var moveBatchID: UUID?
    @State private var toast: ToastMessage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Inventory",
                             title: "What is actually here",
                             subtitle: store.activeBatches.isEmpty
                                ? nil
                                : "\(store.activeBatches.count) batch(es) · \(groups.count) product(s)",
                             tint: Ocean.turquoise)

                filterBar

                if store.activeBatches.isEmpty {
                    EmptyStateCard(symbol: "shippingbox.fill",
                                   title: "Nothing in stock yet",
                                   message: "Inventory fills from real purchases. Add one item — a batch keeps its own date, price and remaining amount.",
                                   actionTitle: "Add an item",
                                   tint: Ocean.turquoise) {
                        navigator.sheet = .addProduct(barcode: nil)
                    }
                } else if groups.isEmpty {
                    EmptyStateCard(symbol: "line.3.horizontal.decrease.circle.fill",
                                   title: "No items match this filter",
                                   message: filterExplanation,
                                   actionTitle: "Show all items",
                                   tint: Ocean.tide) {
                        navigator.inventoryFilter = .all
                        search = ""
                    }
                } else {
                    ForEach(groups) { group in
                        ProductGroupCard(group: group,
                                         isExpanded: expanded.contains(group.id),
                                         onToggle: {
                                             withAnimation(OceanMotion.pop) {
                                                 if expanded.contains(group.id) { expanded.remove(group.id) }
                                                 else { expanded.insert(group.id) }
                                             }
                                         },
                                         onOpenBatch: { navigator.push(.product($0)) },
                                         onAdjust: { adjustBatchID = $0 },
                                         onMove: { moveBatchID = $0 },
                                         onToggleOpened: { id in
                                             let opened = store.batch(id)?.opened ?? false
                                             store.markOpened(batchID: id, opened: !opened)
                                             toast = ToastMessage(title: opened ? "Marked unopened" : "Marked opened")
                                         },
                                         onArchive: { id in
                                             store.archiveBatch(id, archived: true)
                                             toast = ToastMessage(kind: .info, title: "Archived",
                                                                  detail: "It no longer counts. Restore it from Archive.")
                                         })
                    }
                }

                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .background(OceanBackground(tint: Ocean.turquoise))
        .toastHost($toast)
        #if os(iOS)
        .searchable(text: $search, prompt: "Search products")
        #endif
        .navigationTitle("Inventory")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Divider()
                    Button { navigator.push(.archive) } label: {
                        Label("Archive (\(store.archivedBatches.count))", systemImage: "archivebox.fill")
                    }
                    Button { navigator.push(.zones) } label: {
                        Label("Storage zones", systemImage: "square.grid.2x2.fill")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Ocean.ink)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { navigator.sheet = .addProduct(barcode: nil) } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Ocean.blue)
                }
                .accessibilityLabel("Add item")
            }
        }
        .sheet(item: Binding(get: { adjustBatchID.map(IdentifiedUUID.init) },
                             set: { adjustBatchID = $0?.id })) { wrapper in
            AdjustQuantitySheet(batchID: wrapper.id) { message in
                toast = ToastMessage(title: "Quantity updated", detail: message)
            }
        }
        .sheet(item: Binding(get: { moveBatchID.map(IdentifiedUUID.init) },
                             set: { moveBatchID = $0?.id })) { wrapper in
            MoveBatchSheet(batchID: wrapper.id) { message in
                toast = ToastMessage(title: "Item moved", detail: message)
            }
        }
        .oceanTabInset()
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(InventoryFilter.allCases) { filter in
                        OceanChip(title: filter.title, symbol: filter.symbol,
                                  tint: Ocean.turquoise,
                                  isOn: navigator.inventoryFilter == filter,
                                  badge: count(for: filter)) {
                            navigator.inventoryFilter = filter
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            if navigator.inventoryFilter == .lowStock && !store.hasAnyThreshold {
                InfoNote(text: "No restock threshold has been set yet, so low stock cannot be computed. Open a product and set one — the app will not guess.",
                         symbol: "exclamationmark.circle.fill", tint: Ocean.coral)
            }
        }
    }

    private func count(for filter: InventoryFilter) -> Int {
        switch filter {
        case .all: return store.activeBatches.count
        case .expiring: return store.expiringSoon.count
        case .opened: return store.openedBatches.count
        case .reserved: return store.reservedBatches.count
        case .lowStock: return store.lowStockLines.count
        }
    }

    private var filterExplanation: String {
        switch navigator.inventoryFilter {
        case .expiring: return "No batch has a date inside your \(store.data.settings.expiryWindowDays)-day window. Items without a date are not counted here — they are Unknown."
        case .opened: return "No batch is marked opened."
        case .reserved: return "No batch is reserved by a planned meal."
        case .lowStock: return "No product is at or below its threshold."
        case .all: return "Try a different search term."
        }
    }

    // MARK: - Grouping

    private var filteredBatches: [Batch] {
        var result = store.activeBatches
        switch navigator.inventoryFilter {
        case .all: break
        case .expiring: result = store.expiringSoon
        case .opened: result = result.filter { $0.opened }
        case .reserved: result = result.filter { store.reserved($0.id) > 0 }
        case .lowStock:
            let keys = Set(store.lowStockLines.map(\.key))
            result = result.filter { keys.contains($0.productKey) }
        }
        if !search.isEmpty {
            let needle = ProductKey.make(search)
            result = result.filter {
                $0.productKey.contains(needle) || ($0.brand.map { ProductKey.make($0).contains(needle) } ?? false)
            }
        }
        return result
    }

    private var groups: [ProductGroup] {
        let grouped = Dictionary(grouping: filteredBatches, by: \.productKey)
        var result: [ProductGroup] = grouped.map { key, batches in
            ProductGroup(id: key,
                         name: batches.first?.productName ?? key,
                         batches: batches.sorted {
                             ($0.bestBefore ?? .distantFuture, $0.createdAt) < ($1.bestBefore ?? .distantFuture, $1.createdAt)
                         },
                         store: store)
        }
        switch sort {
        case .date:
            result.sort { ($0.earliestDate ?? .distantFuture) < ($1.earliestDate ?? .distantFuture) }
        case .name:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .quantity:
            result.sort { ($0.totalOnHand ?? 0) > ($1.totalOnHand ?? 0) }
        case .added:
            result.sort { ($0.batches.map(\.createdAt).max() ?? .distantPast) > ($1.batches.map(\.createdAt).max() ?? .distantPast) }
        }
        return result
    }

    private var footer: some View {
        SourceStampView(source: "This device (local records)",
                        updated: store.lastSavedAt,
                        isCached: !network.isOnline)
    }
}

/// Wrapper so an optional UUID can drive `.sheet(item:)`.
struct IdentifiedUUID: Identifiable, Hashable {
    var id: UUID
    init(_ id: UUID) { self.id = id }
}

// MARK: - Group model

struct ProductGroup: Identifiable {
    var id: String
    var name: String
    var batches: [Batch]

    /// nil when the batches use units that cannot be added together.
    var totalOnHand: Double?
    var totalAvailable: Double?
    var unit: MeasureUnit
    var earliestDate: Date?
    var reservedTotal: Double
    var mixedUnits: Bool
    var zoneNames: [String]
    var attentionCount: Int

    @MainActor
    init(id: String, name: String, batches: [Batch], store: AppStore) {
        self.id = id
        self.name = name
        self.batches = batches
        let unit = batches.first?.unit ?? .piece
        self.unit = unit

        var onHand = 0.0
        var availableTotal = 0.0
        var reserved = 0.0
        var mixed = false
        for batch in batches {
            guard let converted = MeasureUnit.convert(batch.remaining, from: batch.unit, to: unit),
                  let availableConverted = MeasureUnit.convert(store.available(batch), from: batch.unit, to: unit),
                  let reservedConverted = MeasureUnit.convert(store.reserved(batch.id), from: batch.unit, to: unit)
            else { mixed = true; continue }
            onHand += converted
            availableTotal += availableConverted
            reserved += reservedConverted
        }
        self.mixedUnits = mixed
        self.totalOnHand = mixed ? nil : onHand
        self.totalAvailable = mixed ? nil : availableTotal
        self.reservedTotal = reserved
        self.earliestDate = batches.compactMap(\.bestBefore).min()
        self.zoneNames = Array(Set(batches.compactMap { store.zoneName($0.zoneID) })).sorted()
        self.attentionCount = batches.filter { store.expiryState($0).isAttention }.count
    }
}

// MARK: - Group card

private struct ProductGroupCard: View {
    @Environment(AppStore.self) private var store

    var group: ProductGroup
    var isExpanded: Bool
    var onToggle: () -> Void
    var onOpenBatch: (UUID) -> Void
    var onAdjust: (UUID) -> Void
    var onMove: (UUID) -> Void
    var onToggleOpened: (UUID) -> Void
    var onArchive: (UUID) -> Void

    private var tint: Color { Ocean.accent(for: group.id) }

    private var ringProgress: Double? {
        guard let onHand = group.totalOnHand, onHand > 0 else { return nil }
        let purchased = group.batches.reduce(0.0) { partial, batch in
            partial + (MeasureUnit.convert(batch.quantity, from: batch.unit, to: group.unit) ?? 0)
        }
        guard purchased > 0 else { return nil }
        return min(1, onHand / purchased)
    }

    var body: some View {
        WaveCard(tint: tint, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: onToggle) {
                    HStack(spacing: 14) {
                        StockRing(progress: ringProgress, tint: tint, size: 54,
                                  centerText: group.totalOnHand.map { Format.quantity($0) } ?? "?")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                                .font(OceanFont.title(17))
                                .foregroundStyle(Ocean.ink)
                                .multilineTextAlignment(.leading)
                            if group.mixedUnits {
                                Text("Mixed units — open to see each batch")
                                    .font(OceanFont.caption(11.5))
                                    .foregroundStyle(Ocean.coral)
                            } else {
                                Text("\(Format.measure(group.totalAvailable ?? 0, group.unit)) available" +
                                     (group.reservedTotal > 0 ? " · \(Format.measure(group.reservedTotal, group.unit)) reserved" : ""))
                                    .font(OceanFont.caption(12))
                                    .foregroundStyle(Ocean.inkSoft)
                            }
                            HStack(spacing: 4) {
                                Text("\(group.batches.count) batch(es)")
                                if let date = group.earliestDate {
                                    Text("· first date \(DateFormat.shortDay(date))")
                                }
                                if group.attentionCount > 0 {
                                    Text("· \(group.attentionCount) to review")
                                        .foregroundStyle(Ocean.coral)
                                }
                            }
                            .font(OceanFont.caption(11))
                            .foregroundStyle(Ocean.inkFaint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(tint)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(spacing: 10) {
                        ForEach(group.batches) { batch in
                            BatchRow(batch: batch,
                                     onOpen: { onOpenBatch(batch.id) },
                                     onAdjust: { onAdjust(batch.id) },
                                     onMove: { onMove(batch.id) },
                                     onToggleOpened: { onToggleOpened(batch.id) },
                                     onArchive: { onArchive(batch.id) })
                        }
                    }
                }
            }
        }
    }
}

struct BatchRow: View {
    @Environment(AppStore.self) private var store

    var batch: Batch
    var onOpen: () -> Void
    var onAdjust: () -> Void
    var onMove: () -> Void
    var onToggleOpened: () -> Void
    var onArchive: () -> Void

    private var state: ExpiryState { store.expiryState(batch) }

    private var stateTint: Color {
        switch state {
        case .expired: return Ocean.blue
        case .soon: return Ocean.coral
        case .later: return Ocean.turquoise
        case .unknown: return Ocean.tide
        }
    }

    private var stateLabel: String {
        switch state {
        case .expired(let days): return "Past your date by \(days) day(s)"
        case .soon(let days): return days == 0 ? "Your date is today" : "Your date in \(days) day(s)"
        case .later(let days): return "Your date in \(days) day(s)"
        case .unknown: return "No date — Unknown"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(Format.measure(batch.remaining, batch.unit))
                                .font(OceanFont.headline(15))
                                .foregroundStyle(Ocean.ink)
                            if store.reserved(batch.id) > 0 {
                                Label(Format.measure(store.reserved(batch.id), batch.unit),
                                      systemImage: "lock.fill")
                                    .font(OceanFont.caption(10.5))
                                    .foregroundStyle(Ocean.tide)
                            }
                            if batch.opened {
                                Text("opened")
                                    .font(OceanFont.caption(10))
                                    .foregroundStyle(Ocean.sky)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Ocean.sky.opacity(0.2)))
                            }
                        }
                        Text(stateLabel)
                            .font(OceanFont.caption(11))
                            .foregroundStyle(stateTint)
                        HStack(spacing: 6) {
                            Image(systemName: batch.origin.symbol).font(.system(size: 9, weight: .bold))
                            Text(store.zoneName(batch.zoneID) ?? "No zone")
                            if let price = store.money(batch.price) { Text("· \(price)") }
                        }
                        .font(OceanFont.caption(10.5))
                        .foregroundStyle(Ocean.inkFaint)
                    }
                    Spacer(minLength: 0)
                    RowChevron()
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                OceanChip(title: "Adjust", symbol: "slider.horizontal.3", tint: Ocean.turquoise, action: onAdjust)
                OceanChip(title: "Move", symbol: "arrow.left.arrow.right", tint: Ocean.tide, action: onMove)
                OceanChip(title: batch.opened ? "Unopen" : "Opened", symbol: "seal.fill",
                          tint: Ocean.sky, action: onToggleOpened)
                OceanChip(title: "Archive", symbol: "archivebox.fill", tint: Ocean.coral, action: onArchive)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Ocean.foam.opacity(0.75))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(stateTint.opacity(0.2), lineWidth: 1.2))
        )
    }
}
