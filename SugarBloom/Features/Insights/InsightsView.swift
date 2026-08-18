//
//  InsightsView.swift
//  Ocean Cast
//
//  SCREEN 13 — Only what the saved records can prove. No decorative charts,
//  no filler statistics, and an honest wait until there is enough history.
//

import SwiftUI

struct InsightsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var navigator

    enum Period: String, CaseIterable, Identifiable {
        case week, month, quarter, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .week: return "7 days"
            case .month: return "30 days"
            case .quarter: return "90 days"
            case .all: return "All time"
            }
        }
        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            case .all: return nil
            }
        }
    }

    private let requiredDays = 30

    @State private var period: Period = .month
    @State private var expanded: String?
    @State private var exportURL: URL?
    @State private var toast: ToastMessage?

    private var recordedDays: Int { store.recordedDays }
    private var hasEnoughHistory: Bool { recordedDays >= requiredDays }

    private var entries: [ActivityEntry] {
        guard let days = period.days else { return store.data.activity }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return store.data.activity.filter { $0.date >= cutoff }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Insights",
                             title: hasEnoughHistory ? "What your records show" : "Still collecting",
                             subtitle: hasEnoughHistory
                                ? "Every number below opens the records it was computed from."
                                : nil,
                             tint: Ocean.tide)

                if !hasEnoughHistory {
                    gateCard
                } else {
                    periodPicker
                    wasteCard
                    refilledCard
                    basketCard
                    forgottenCard
                    exportCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(OceanBackground(tint: Ocean.tide))
        .toastHost($toast)
        .navigationTitle("Insights")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .oceanTabInset()
    }

    // MARK: - Gate

    private var gateCard: some View {
        VStack(spacing: 14) {
            WaveCard(tint: Ocean.tide, padding: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        StockRing(progress: min(1, Double(recordedDays) / Double(requiredDays)),
                                  tint: Ocean.tide, size: 64,
                                  centerText: "\(recordedDays)d")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(recordedDays) of \(requiredDays) days recorded")
                                .font(OceanFont.title(17)).foregroundStyle(Ocean.ink)
                            Text("\(max(0, requiredDays - recordedDays)) day(s) to go")
                                .font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                        }
                    }
                    Text("Averages built from a few days would say more about the start of your history than about your kitchen. Ocean Cast waits instead of showing a number it cannot back up.")
                        .font(OceanFont.body(14)).foregroundStyle(Ocean.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(store.data.activity.count) record(s) saved so far.")
                        .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.tide)
                    OceanButton(title: "View recorded activity", symbol: "clock.arrow.circlepath",
                                kind: .secondary, tint: Ocean.tide) {
                        navigator.push(.activity)
                    }
                }
            }
        }
    }

    private var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Period.allCases) { option in
                    OceanChip(title: option.title, tint: Ocean.tide, isOn: period == option) {
                        period = option
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Waste

    private struct WasteLine: Identifiable {
        var id: String { reason.rawValue }
        var reason: AdjustReason
        var events: Int
        var knownCost: Double
        var withoutPrice: Int
    }

    private var wasteLines: [WasteLine] {
        let wasteEntries = entries.filter { $0.reason?.isWaste == true }
        return AdjustReason.allCases.filter(\.isWaste).compactMap { reason in
            let matching = wasteEntries.filter { $0.reason == reason }
            guard !matching.isEmpty else { return nil }
            let priced = matching.compactMap(\.amount)
            return WasteLine(reason: reason,
                             events: matching.count,
                             knownCost: priced.reduce(0, +),
                             withoutPrice: matching.count - priced.count)
        }
    }

    private var wasteCard: some View {
        SectionCard(title: "Waste by Reason", symbol: "trash.fill", tint: Ocean.coral) {
            VStack(alignment: .leading, spacing: 12) {
                if wasteLines.isEmpty {
                    Text("No spilled or discarded amounts were recorded in this period.")
                        .font(OceanFont.body(14)).foregroundStyle(Ocean.inkSoft)
                } else {
                    ForEach(wasteLines) { line in
                        HStack(spacing: 12) {
                            FloatDisc(symbol: line.reason.symbol, tint: Ocean.coral, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.reason.title)
                                    .font(OceanFont.headline(14.5)).foregroundStyle(Ocean.ink)
                                Text("\(line.events) event(s)"
                                     + (line.knownCost > 0 ? " · \(store.money(line.knownCost) ?? "")" : ""))
                                    .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.inkSoft)
                                if line.withoutPrice > 0 {
                                    Text("\(line.withoutPrice) without a recorded price — cost unknown, not zero")
                                        .font(OceanFont.caption(10.5)).foregroundStyle(Ocean.coral)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    sourceToggle(key: "waste",
                                 entries: entries.filter { $0.reason?.isWaste == true })
                }
            }
        }
    }

    // MARK: - Refilled

    private struct CountLine: Identifiable {
        var id: String { name }
        var name: String
        var count: Int
    }

    private var refilledLines: [CountLine] {
        let created = entries.filter { $0.kind == .batchCreated }
        var counts: [String: Int] = [:]
        for entry in created {
            guard let batchID = entry.batchID, let batch = store.batch(batchID) else { continue }
            counts[batch.productName, default: 0] += 1
        }
        return counts.filter { $0.value > 1 }
            .map { CountLine(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var refilledCard: some View {
        SectionCard(title: "Frequently Refilled", symbol: "arrow.triangle.2.circlepath", tint: Ocean.turquoise) {
            VStack(alignment: .leading, spacing: 12) {
                if refilledLines.isEmpty {
                    Text("Nothing was bought more than once in this period.")
                        .font(OceanFont.body(14)).foregroundStyle(Ocean.inkSoft)
                } else {
                    ForEach(refilledLines.prefix(6)) { line in
                        Button {
                            navigator.push(.priceHistory(key: ProductKey.make(line.name), name: line.name))
                        } label: {
                            HStack(spacing: 12) {
                                FloatDisc(symbol: "shippingbox.fill", tint: Ocean.turquoise, size: 32)
                                Text(line.name).font(OceanFont.headline(14.5)).foregroundStyle(Ocean.ink)
                                Spacer()
                                Text("\(line.count)×")
                                    .font(OceanFont.numeric(17)).foregroundStyle(Ocean.turquoise)
                                RowChevron()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    sourceToggle(key: "refilled", entries: entries.filter { $0.kind == .batchCreated })
                }
            }
        }
    }

    // MARK: - Basket

    private var basketStats: (average: Double?, days: Int, unpriced: Int) {
        let purchases = entries.filter { $0.kind == .batchCreated || $0.kind == .shoppingPurchased }
        let priced = purchases.filter { $0.amount != nil }
        let unpriced = purchases.count - priced.count
        guard !priced.isEmpty else { return (nil, 0, unpriced) }
        let byDay = Dictionary(grouping: priced) { Calendar.current.startOfDay(for: $0.date) }
        let totals = byDay.map { $0.value.compactMap(\.amount).reduce(0, +) }
        guard !totals.isEmpty else { return (nil, 0, unpriced) }
        return (totals.reduce(0, +) / Double(totals.count), totals.count, unpriced)
    }

    private var basketCard: some View {
        let stats = basketStats
        return SectionCard(title: "Average Basket", symbol: "cart.fill", tint: Ocean.sky) {
            VStack(alignment: .leading, spacing: 12) {
                if let average = stats.average {
                    HStack(spacing: 14) {
                        FloatDisc(symbol: "creditcard.fill", tint: Ocean.sky, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.money(average) ?? "—")
                                .font(OceanFont.numeric(24)).foregroundStyle(Ocean.ink)
                            Text("across \(stats.days) shopping day(s) with prices")
                                .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.inkSoft)
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    Text("No purchase in this period has a price recorded, so an average cannot be computed. It is unknown — not zero.")
                        .font(OceanFont.body(14)).foregroundStyle(Ocean.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if stats.unpriced > 0 {
                    Text("\(stats.unpriced) purchase record(s) have no price and are left out of the average.")
                        .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                }
                sourceToggle(key: "basket",
                             entries: entries.filter { ($0.kind == .batchCreated || $0.kind == .shoppingPurchased) && $0.amount != nil })
            }
        }
    }

    // MARK: - Forgotten

    private var forgottenLines: [CountLine] {
        let wasted = entries.filter { $0.reason?.isWaste == true }
        var counts: [String: Int] = [:]
        for entry in wasted {
            guard let batchID = entry.batchID, let batch = store.batch(batchID) else { continue }
            counts[batch.productName, default: 0] += 1
        }
        return counts.map { CountLine(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var forgottenCard: some View {
        SectionCard(title: "Items Often Forgotten", symbol: "clock.badge.exclamationmark.fill", tint: Ocean.blue) {
            VStack(alignment: .leading, spacing: 12) {
                if forgottenLines.isEmpty {
                    Text("Nothing was recorded as spilled or discarded in this period.")
                        .font(OceanFont.body(14)).foregroundStyle(Ocean.inkSoft)
                } else {
                    ForEach(forgottenLines.prefix(6)) { line in
                        HStack(spacing: 12) {
                            FloatDisc(symbol: "exclamationmark", tint: Ocean.blue, size: 32)
                            Text(line.name).font(OceanFont.headline(14.5)).foregroundStyle(Ocean.ink)
                            Spacer()
                            Text("\(line.count)×")
                                .font(OceanFont.numeric(17)).foregroundStyle(Ocean.blue)
                        }
                    }
                    Text("These come only from adjustments where you chose Spilled or Discarded.")
                        .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkFaint)
                }
            }
        }
    }

    // MARK: - Source drill-down

    @ViewBuilder
    private func sourceToggle(key: String, entries: [ActivityEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(OceanMotion.pop) { expanded = expanded == key ? nil : key }
            } label: {
                HStack(spacing: 6) {
                    Text(expanded == key ? "Hide source items" : "View Source Items (\(entries.count))")
                        .font(OceanFont.caption(12.5)).foregroundStyle(Ocean.tide)
                    Image(systemName: expanded == key ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Ocean.tide)
                }
            }
            .buttonStyle(.plain)

            if expanded == key {
                VStack(spacing: 8) {
                    ForEach(entries.prefix(20)) { entry in
                        ActivityRow(entry: entry)
                    }
                    if entries.count > 20 {
                        Text("+\(entries.count - 20) more in Activity history")
                            .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkFaint)
                    }
                }
            }
        }
    }

    // MARK: - Export

    private var exportCard: some View {
        SectionCard(title: "Export Summary", symbol: "square.and.arrow.up.fill", tint: Ocean.turquoise) {
            VStack(alignment: .leading, spacing: 12) {
                Text("The export contains exactly the rows above, with the period and the record counts they were computed from.")
                    .font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share summary CSV", systemImage: "square.and.arrow.up")
                            .font(OceanFont.headline(15))
                    }
                    .buttonStyle(OceanButtonStyle(kind: .secondary, tint: Ocean.turquoise))
                }
                OceanButton(title: "Prepare CSV", symbol: "doc.badge.gearshape",
                            kind: .secondary, tint: Ocean.turquoise) { prepareExport() }
            }
        }
    }

    private func prepareExport() {
        var rows = ["section,label,value,note"]
        rows.append("period,window,\(period.title),\(entries.count) records")
        for line in wasteLines {
            rows.append("waste,\(line.reason.title),\(line.events),\(line.withoutPrice) without price")
        }
        for line in refilledLines {
            rows.append("refilled,\(csvSafe(line.name)),\(line.count),purchases in period")
        }
        let stats = basketStats
        rows.append("basket,average,\(stats.average.map { String(format: "%.2f", $0) } ?? "unknown"),\(stats.days) priced days")
        for line in forgottenLines {
            rows.append("forgotten,\(csvSafe(line.name)),\(line.count),waste events")
        }
        do {
            exportURL = try PersistenceController.shared.exportCSV(rows.joined(separator: "\n"), name: "insights")
            Haptics.success()
            toast = ToastMessage(title: "CSV ready", detail: "Use Share summary CSV to send it.")
        } catch {
            Haptics.warning()
            toast = ToastMessage(kind: .warning, title: "Export failed", detail: error.localizedDescription)
        }
    }

    private func csvSafe(_ value: String) -> String {
        value.replacingOccurrences(of: ",", with: " ")
    }
}
