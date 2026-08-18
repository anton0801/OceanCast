//
//  ActivityLogView.swift
//  Ocean Cast
//
//  The append-only record behind every number in the app.
//

import SwiftUI

struct ActivityRow: View {
    var entry: ActivityEntry

    private var tint: Color {
        switch entry.kind {
        case .batchCreated, .receiptImported, .shoppingPurchased: return Ocean.turquoise
        case .batchAdjusted:
            if let reason = entry.reason { return reason.isWaste ? Ocean.coral : Ocean.tide }
            return Ocean.tide
        case .recallDecision, .recallArchived, .recallChecked: return Ocean.blue
        case .mealReserved, .mealCooked, .mealReleased: return Ocean.tide
        case .batchDeleted, .mealDeleted, .shoppingDeleted, .batchArchived: return Ocean.inkFaint
        default: return Ocean.sky
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            FloatDisc(symbol: entry.kind.symbol, tint: tint, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.summary)
                    .font(OceanFont.headline(13.5))
                    .foregroundStyle(Ocean.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = entry.detail {
                    Text(detail)
                        .font(OceanFont.caption(11))
                        .foregroundStyle(Ocean.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(DateFormat.stamp(entry.date))
                    .font(OceanFont.caption(10))
                    .foregroundStyle(Ocean.inkFaint)
            }
            Spacer(minLength: 0)
        }
    }
}

struct ActivityLogView: View {
    enum Filter: Equatable {
        case all
        case batch(UUID)
        case meal(UUID)
    }

    @Environment(AppStore.self) private var store

    var filter: Filter = .all

    @State private var search = ""

    private var entries: [ActivityEntry] {
        var result: [ActivityEntry]
        switch filter {
        case .all: result = store.data.activity
        case .batch(let id): result = store.history(batchID: id)
        case .meal(let id): result = store.history(mealID: id)
        }
        if !search.isEmpty {
            result = result.filter {
                $0.summary.localizedCaseInsensitiveContains(search)
                    || ($0.detail?.localizedCaseInsensitiveContains(search) ?? false)
            }
        }
        return result.sorted { $0.date > $1.date }
    }

    private var grouped: [(day: Date, items: [ActivityEntry])] {
        Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.0 > $1.0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "History",
                             title: "Everything that happened",
                             subtitle: "\(store.data.activity.count) record(s). Nothing here is generated — each line came from an action you took.",
                             tint: Ocean.turquoise)

                if entries.isEmpty {
                    EmptyStateCard(symbol: "clock.arrow.circlepath",
                                   title: search.isEmpty ? "No records yet" : "No record matches",
                                   message: search.isEmpty
                                    ? "As soon as you add, adjust, reserve or buy something, it appears here."
                                    : "Try a different search term.",
                                   tint: Ocean.turquoise)
                } else {
                    ForEach(grouped, id: \.day) { group in
                        SectionCard(title: DateFormat.day(group.day),
                                    symbol: "calendar",
                                    tint: Ocean.turquoise) {
                            VStack(spacing: 10) {
                                ForEach(group.items) { entry in
                                    ActivityRow(entry: entry)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(OceanBackground(tint: Ocean.turquoise))
        #if os(iOS)
        .searchable(text: $search, prompt: "Search history")
        #endif
        .navigationTitle("Activity")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .oceanTabInset()
    }
}

// MARK: - Archive

struct ArchiveView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var navigator

    @State private var toast: ToastMessage?

    private var archived: [Batch] {
        store.archivedBatches.sorted { $0.createdAt > $1.createdAt }
    }
    private var usedUp: [Batch] {
        store.data.batches.filter { !$0.archived && $0.isDepleted }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Archive",
                             title: "Out of the counts, still in the records",
                             subtitle: "Archived and used-up batches keep their history, prices and recall checks.",
                             tint: Ocean.tide)

                if archived.isEmpty && usedUp.isEmpty {
                    EmptyStateCard(symbol: "archivebox.fill",
                                   title: "Nothing archived",
                                   message: "Archiving is the safe alternative to deleting. Anything you archive shows up here and can be restored.",
                                   tint: Ocean.tide)
                } else {
                    if !archived.isEmpty {
                        SectionCard(title: "Archived", symbol: "archivebox.fill", tint: Ocean.tide) {
                            VStack(spacing: 10) {
                                ForEach(archived) { batch in
                                    row(batch, actionTitle: "Restore") {
                                        store.archiveBatch(batch.id, archived: false)
                                        toast = ToastMessage(title: "Restored", detail: "It counts again.")
                                    }
                                }
                            }
                        }
                    }
                    if !usedUp.isEmpty {
                        SectionCard(title: "Used up", symbol: "checkmark.circle.fill", tint: Ocean.turquoise) {
                            VStack(spacing: 10) {
                                ForEach(usedUp) { batch in
                                    row(batch, actionTitle: "Open") {
                                        navigator.push(.product(batch.id))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(OceanBackground(tint: Ocean.tide))
        .toastHost($toast)
        .navigationTitle("Archive")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .oceanTabInset()
    }

    private func row(_ batch: Batch, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            FloatDisc(symbol: "shippingbox.fill", tint: Ocean.inkFaint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(batch.displayTitle).font(OceanFont.headline(14)).foregroundStyle(Ocean.ink)
                Text("\(Format.measure(batch.remaining, batch.unit)) left · added \(DateFormat.day(batch.createdAt))")
                    .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
            }
            Spacer()
            Button(actionTitle, action: action)
                .font(OceanFont.caption(12))
                .foregroundStyle(Ocean.turquoise)
        }
    }
}

// MARK: - Zones

struct ZoneManagerView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var navigator

    @State private var toast: ToastMessage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Storage zones",
                             title: "Where things live",
                             subtitle: "Zones only group your batches. Archiving a zone never deletes what was stored in it.",
                             tint: Ocean.turquoise)

                if let household = store.household {
                    ForEach(household.zones) { zone in
                        WaveCard(tint: zone.archived ? Ocean.inkFaint : Ocean.turquoise, padding: 14) {
                            HStack(spacing: 12) {
                                FloatDisc(symbol: zone.kind.symbol,
                                          tint: zone.archived ? Ocean.inkFaint : Ocean.turquoise, size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(zone.name).font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                                    Text(zone.archived
                                         ? "Archived"
                                         : "\(store.batchCount(inZone: zone.id)) active batch(es)")
                                        .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.inkSoft)
                                }
                                Spacer()
                                if zone.archived {
                                    Button("Restore") {
                                        store.restoreZone(zone.id)
                                        toast = ToastMessage(title: "Zone restored")
                                    }
                                    .font(OceanFont.caption(12)).foregroundStyle(Ocean.turquoise)
                                }
                            }
                        }
                    }
                    OceanButton(title: "Edit zones in Household Setup", symbol: "house.fill",
                                kind: .secondary, tint: Ocean.turquoise) {
                        navigator.sheet = .householdSetup
                    }
                } else {
                    EmptyStateCard(symbol: "house.fill",
                                   title: "No household yet",
                                   message: "Zones belong to a household. Create one first.",
                                   actionTitle: "Create Household",
                                   tint: Ocean.coral) {
                        navigator.sheet = .householdSetup
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(OceanBackground(tint: Ocean.turquoise))
        .toastHost($toast)
        .navigationTitle("Storage Zones")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .oceanTabInset()
    }
}
