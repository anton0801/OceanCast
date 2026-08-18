//
//  PriceHistoryView.swift
//  Ocean Cast
//
//  SCREEN 11 — Prices you confirmed yourself. Packs and weights are never
//  compared without a factor that exists.
//

import SwiftUI
import Charts

struct PriceHistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(NetworkMonitor.self) private var network

    var productKey: String
    var productName: String

    @State private var targetText = ""
    @State private var toast: ToastMessage?
    @State private var selectedDimension: MeasureDimension?

    private var entries: [PriceEntry] { store.priceEntries(for: productKey) }

    private var dimensions: [MeasureDimension] {
        Array(Set(entries.map { $0.unit.dimension })).sorted { $0.rawValue < $1.rawValue }
    }

    private var activeDimension: MeasureDimension? {
        selectedDimension ?? dimensions.first
    }

    private var comparable: [PriceEntry] {
        guard let activeDimension else { return [] }
        return entries.filter { $0.unit.dimension == activeDimension && $0.pricePerBaseUnit != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Price History",
                             title: productName,
                             subtitle: entries.isEmpty
                                ? nil
                                : "\(entries.count) record(s) from your own purchases.",
                             tint: Ocean.sky)

                if entries.isEmpty {
                    EmptyStateCard(symbol: "tag.fill",
                                   title: "No price recorded yet",
                                   message: "A price appears here when you enter one while adding an item or confirming a purchase. Ocean Cast does not fetch shop prices, so nothing is filled in for you.",
                                   tint: Ocean.sky)
                } else {
                    if dimensions.count > 1 { dimensionPicker }
                    bestPriceCard
                    if comparable.count >= 2 { chartCard }
                    entriesCard
                    targetCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(OceanBackground(tint: Ocean.sky))
        .toastHost($toast)
        .navigationTitle("Price History")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .oceanTabInset()
    }

    private var dimensionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(dimensions, id: \.self) { dimension in
                        OceanChip(title: dimension.title, tint: Ocean.sky,
                                  isOn: activeDimension == dimension) {
                            selectedDimension = dimension
                        }
                    }
                }
            }
            InfoNote(text: "This product was bought in more than one kind of unit. Packs, pieces, weight and volume are compared separately — mixing them would need a factor Ocean Cast does not have.",
                     symbol: "ruler.fill", tint: Ocean.tide)
        }
    }

    private var bestPriceCard: some View {
        let best = comparable.min { ($0.pricePerBaseUnit ?? .infinity) < ($1.pricePerBaseUnit ?? .infinity) }
        let latest = comparable.first
        return SectionCard(title: "Best Recent Price", symbol: "star.fill", tint: Ocean.sky) {
            VStack(alignment: .leading, spacing: 12) {
                if let best, let perUnit = best.pricePerBaseUnit, let unit = activeDimension {
                    HStack(spacing: 14) {
                        FloatDisc(symbol: "tag.fill", tint: Ocean.turquoise, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.money(best.price) ?? "—")
                                .font(OceanFont.numeric(22)).foregroundStyle(Ocean.ink)
                            Text("for \(Format.measure(best.quantity, best.unit))"
                                 + (best.store.map { " at \($0)" } ?? ""))
                                .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.inkSoft)
                            Text("\(store.money(perUnit) ?? "—") per \(baseUnitLabel(unit)) · \(DateFormat.day(best.date))")
                                .font(OceanFont.caption(11)).foregroundStyle(Ocean.turquoise)
                        }
                        Spacer(minLength: 0)
                    }
                    if let latest, latest.id != best.id, let latestPerUnit = latest.pricePerBaseUnit {
                        let difference = latestPerUnit - perUnit
                        Text("Your latest purchase was \(store.money(latestPerUnit) ?? "—") per \(baseUnitLabel(unit)) — \(difference > 0 ? "higher" : "lower") by \(store.money(abs(difference)) ?? "—").")
                            .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.inkSoft)
                    }
                } else {
                    Text("No record in this unit group has a usable quantity, so price per unit cannot be computed.")
                        .font(OceanFont.body(14)).foregroundStyle(Ocean.coral)
                }
                SourceStampView(source: "Your confirmed purchases",
                                updated: entries.first?.date,
                                isCached: !network.isOnline)
            }
        }
    }

    private func baseUnitLabel(_ dimension: MeasureDimension) -> String {
        switch dimension {
        case .count: return "piece"
        case .pack: return "pack"
        case .mass: return "g"
        case .volume: return "ml"
        }
    }

    private var chartCard: some View {
        SectionCard(title: "Price per Unit", symbol: "chart.line.uptrend.xyaxis", tint: Ocean.tide) {
            VStack(alignment: .leading, spacing: 10) {
                Chart(comparable) { entry in
                    LineMark(
                        x: .value("Date", entry.date),
                        y: .value("Price", entry.pricePerBaseUnit ?? 0)
                    )
                    .foregroundStyle(Ocean.tide)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", entry.date),
                        y: .value("Price", entry.pricePerBaseUnit ?? 0)
                    )
                    .foregroundStyle(Ocean.blue)
                }
                .frame(height: 170)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }

                Text("Each point is one purchase you confirmed, converted to \(activeDimension.map(baseUnitLabel) ?? "base") units. No estimates are drawn between them.")
                    .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
            }
        }
    }

    private var entriesCard: some View {
        SectionCard(title: "All records", symbol: "list.bullet.rectangle.fill", tint: Ocean.turquoise) {
            VStack(spacing: 10) {
                ForEach(entries) { entry in
                    HStack(spacing: 12) {
                        FloatDisc(symbol: entry.origin == .userPurchase ? "cart.fill" : "globe",
                                  tint: entry.origin == .userPurchase ? Ocean.turquoise : Ocean.tide,
                                  size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.money(entry.price) ?? "—")
                                .font(OceanFont.headline(14.5)).foregroundStyle(Ocean.ink)
                            Text("\(Format.measure(entry.quantity, entry.unit))"
                                 + (entry.store.map { " · \($0)" } ?? "")
                                 + " · \(DateFormat.day(entry.date))")
                                .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                            Text(entry.origin.title)
                                .font(OceanFont.caption(10)).foregroundStyle(Ocean.inkFaint)
                        }
                        Spacer(minLength: 0)
                        if let perUnit = entry.pricePerBaseUnit {
                            Text("\(store.money(perUnit) ?? "—")/\(baseUnitLabel(entry.unit.dimension))")
                                .font(OceanFont.caption(11)).foregroundStyle(Ocean.tide)
                        } else {
                            Text("per-unit unknown")
                                .font(OceanFont.caption(10)).foregroundStyle(Ocean.coral)
                        }
                    }
                }
            }
        }
    }

    private var targetCard: some View {
        SectionCard(title: "Add Target Price", symbol: "scope", tint: Ocean.blue) {
            VStack(alignment: .leading, spacing: 12) {
                OceanTextField(label: "Target price (\(store.currency))",
                               placeholder: "what you want to pay",
                               keyboard: .decimal, text: $targetText)
                OceanButton(title: "Save to shopping lines", symbol: "checkmark",
                            kind: .secondary, tint: Ocean.blue) {
                    applyTarget()
                }
                Text("The target is stored on the shopping lines for this product, so the list can total what is actually planned.")
                    .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
            }
        }
    }

    private func applyTarget() {
        guard let target = Parse.double(targetText), target >= 0 else {
            toast = ToastMessage(kind: .warning, title: "Enter a number", detail: "The target must be 0 or more.")
            Haptics.warning()
            return
        }
        var updated = 0
        for item in store.data.shopping where item.productKey == productKey && item.status == .needed {
            var copy = item
            copy.targetPrice = target
            try? store.updateShoppingItem(copy)
            updated += 1
        }
        Haptics.success()
        toast = updated == 0
            ? ToastMessage(kind: .info, title: "No open shopping line",
                           detail: "Add \(productName) to the shopping list and the target will apply.")
            : ToastMessage(title: "Target saved", detail: "\(updated) shopping line(s) updated.")
    }
}
