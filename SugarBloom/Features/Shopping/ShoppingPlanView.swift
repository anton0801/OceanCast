//
//  ShoppingPlanView.swift
//  Ocean Cast
//
//  SCREEN 10 — Automatic shortfalls plus manual lines. A confirmed purchase is
//  what creates a batch; buying twice never doubles it.
//

import SwiftUI

struct ShoppingPlanView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var navigator

    @State private var showAdd = false
    @State private var purchaseItemID: UUID?
    @State private var excludeItemID: UUID?
    @State private var showMissingPicker = false
    @State private var groupByStore = true
    @State private var toast: ToastMessage?

    private var needed: [ShoppingItem] { store.neededShopping }
    private var purchased: [ShoppingItem] {
        store.data.shopping.filter { $0.status == .purchased }
            .sorted { ($0.purchasedAt ?? .distantPast) > ($1.purchasedAt ?? .distantPast) }
    }
    private var excluded: [ShoppingItem] { store.data.shopping.filter { $0.status == .excluded } }

    private var groups: [(store: String, items: [ShoppingItem])] {
        guard groupByStore else { return [("All items", needed)] }
        let grouped = Dictionary(grouping: needed) { $0.store?.nilIfBlank ?? "No store set" }
        return grouped.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Shopping Plan",
                             title: needed.isEmpty ? "Nothing to buy yet" : "\(needed.count) item(s) to buy",
                             subtitle: estimateText,
                             tint: Ocean.coral)

                actions

                if needed.isEmpty && purchased.isEmpty && excluded.isEmpty {
                    EmptyStateCard(symbol: "cart.fill",
                                   title: "Your list is empty",
                                   message: "Two things fill this list: items you add here, and shortfalls you confirm from a planned meal. Nothing is added behind your back.",
                                   actionTitle: "Add an item",
                                   tint: Ocean.coral) { showAdd = true }
                } else {
                    ForEach(groups, id: \.store) { group in
                        if !group.items.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                if groupByStore {
                                    HStack(spacing: 8) {
                                        FloatDisc(symbol: "storefront.fill", tint: Ocean.sky, size: 28)
                                        Text(group.store)
                                            .font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                                        Spacer()
                                        Text("\(group.items.count)")
                                            .font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                                    }
                                }
                                ForEach(group.items) { item in
                                    ShoppingRow(item: item,
                                                currency: store.currency,
                                                assignee: store.member(item.assigneeID)?.name,
                                                onPurchase: { purchaseItemID = item.id },
                                                onExclude: { excludeItemID = item.id },
                                                onDelete: {
                                                    store.deleteShoppingItem(itemID: item.id)
                                                    toast = ToastMessage(kind: .info, title: "Removed from list")
                                                },
                                                onOpenMeal: { mealID in navigator.push(.meal(mealID)) },
                                                onPriceHistory: {
                                                    navigator.push(.priceHistory(key: item.productKey, name: item.name))
                                                })
                                }
                            }
                        }
                    }

                    if !purchased.isEmpty { purchasedSection }
                    if !excluded.isEmpty { excludedSection }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(OceanBackground(tint: Ocean.coral))
        .toastHost($toast)
        .navigationTitle("Shopping")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !needed.isEmpty {
                    ShareLink(item: shareText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Ocean.ink)
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddShoppingItemSheet { message in
                toast = ToastMessage(title: "Added to list", detail: message)
            }
        }
        .sheet(item: Binding(get: { purchaseItemID.map(IdentifiedUUID.init) },
                             set: { purchaseItemID = $0?.id })) { wrapper in
            MarkPurchasedSheet(itemID: wrapper.id) { message in
                toast = ToastMessage(title: "Purchase recorded", detail: message)
            }
        }
        .sheet(item: Binding(get: { excludeItemID.map(IdentifiedUUID.init) },
                             set: { excludeItemID = $0?.id })) { wrapper in
            ExcludeItemSheet(itemID: wrapper.id) { message in
                toast = ToastMessage(kind: .info, title: "Excluded", detail: message)
            }
        }
        .sheet(isPresented: $showMissingPicker) {
            MissingIngredientsPicker { message in
                toast = ToastMessage(title: "Added from meals", detail: message)
            }
        }
        .onAppear { groupByStore = store.household?.preferences.groupByStore ?? true }
        .oceanTabInset()
    }

    private var estimateText: String? {
        let estimate = store.shoppingEstimate
        guard estimate.total > 0 else { return nil }
        if estimate.withPrice == 0 {
            return "No target prices set yet — the total is unknown, not zero."
        }
        let known = store.money(estimate.known) ?? "—"
        return "\(known) from \(estimate.withPrice) of \(estimate.total) item(s) with a target price."
    }

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                OceanButton(title: "Add Item", symbol: "plus") { showAdd = true }
                OceanButton(title: "Add Missing", symbol: "fork.knife",
                            kind: .secondary, tint: Ocean.tide) { showMissingPicker = true }
            }
            HStack(spacing: 10) {
                OceanChip(title: "Group by Store", symbol: "storefront.fill",
                          tint: Ocean.sky, isOn: groupByStore) {
                    groupByStore.toggle()
                    if var preferences = store.household?.preferences {
                        preferences.groupByStore = groupByStore
                        store.updatePreferences(preferences)
                    }
                }
                Spacer()
            }
        }
    }

    private var purchasedSection: some View {
        SectionCard(title: "Purchased", symbol: "checkmark.circle.fill", tint: Ocean.turquoise) {
            VStack(spacing: 8) {
                ForEach(purchased.prefix(8)) { item in
                    HStack(spacing: 10) {
                        FloatDisc(symbol: "cart.fill", tint: Ocean.turquoise, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(OceanFont.headline(14)).foregroundStyle(Ocean.ink)
                            Text("\(Format.measure(item.actualQuantity ?? item.quantity, item.unit))"
                                 + (store.money(item.actualPrice).map { " · \($0)" } ?? " · price not recorded")
                                 + (item.purchasedAt.map { " · \(DateFormat.shortDay($0))" } ?? ""))
                                .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                        }
                        Spacer()
                        Button("Undo") { undo(item) }
                            .font(OceanFont.caption(12))
                            .foregroundStyle(Ocean.coral)
                    }
                }
                Text("Undo removes the batch this purchase created, but only while it is untouched.")
                    .font(OceanFont.caption(10.5)).foregroundStyle(Ocean.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var excludedSection: some View {
        SectionCard(title: "Excluded", symbol: "eye.slash.fill", tint: Ocean.inkFaint) {
            VStack(spacing: 8) {
                ForEach(excluded) { item in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(OceanFont.headline(14)).foregroundStyle(Ocean.inkSoft)
                            Text(item.excludeReason ?? "no reason recorded")
                                .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkFaint)
                        }
                        Spacer()
                        Button("Restore") {
                            store.restoreShoppingItem(itemID: item.id)
                            toast = ToastMessage(kind: .info, title: "Back on the list")
                        }
                        .font(OceanFont.caption(12))
                        .foregroundStyle(Ocean.turquoise)
                    }
                }
            }
        }
    }

    private var shareText: String {
        var lines = ["Shopping list — \(store.household?.name ?? "Ocean Cast")"]
        for group in groups where !group.items.isEmpty {
            if groupByStore { lines.append("\n\(group.store):") }
            for item in group.items {
                var line = "· \(item.name) — \(Format.measure(item.quantity, item.unit))"
                if let target = store.money(item.targetPrice) { line += " (target \(target))" }
                lines.append(line)
            }
        }
        lines.append("\nShared as text only — nothing is ordered or delivered from this app.")
        return lines.joined(separator: "\n")
    }

    private func undo(_ item: ShoppingItem) {
        do {
            try store.undoPurchase(itemID: item.id)
            Haptics.success()
            toast = ToastMessage(kind: .info, title: "Purchase undone",
                                 detail: "The batch it created was removed.")
        } catch {
            Haptics.warning()
            toast = ToastMessage(kind: .warning, title: "Cannot undo", detail: error.localizedDescription)
        }
    }
}

// MARK: - Row

private struct ShoppingRow: View {
    var item: ShoppingItem
    var currency: String
    var assignee: String?
    var onPurchase: () -> Void
    var onExclude: () -> Void
    var onDelete: () -> Void
    var onOpenMeal: (UUID) -> Void
    var onPriceHistory: () -> Void

    private var isAutomatic: Bool {
        if case .mealShortfall = item.source { return true }
        return false
    }

    private var tint: Color { isAutomatic ? Ocean.tide : Ocean.coral }

    var body: some View {
        WaveCard(tint: tint, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    FloatDisc(symbol: isAutomatic ? "fork.knife" : "cart.fill", tint: tint, size: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(OceanFont.headline(15.5)).foregroundStyle(Ocean.ink)
                        Text(Format.measure(item.quantity, item.unit)
                             + (item.targetPrice.flatMap { Format.money($0, currency: currency) }.map { " · target \($0)" } ?? ""))
                            .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.inkSoft)
                        HStack(spacing: 6) {
                            Text(item.source.title)
                            if let assignee { Text("· \(assignee)") }
                        }
                        .font(OceanFont.caption(10.5))
                        .foregroundStyle(Ocean.inkFaint)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    OceanChip(title: "Purchased", symbol: "checkmark", tint: Ocean.turquoise, action: onPurchase)
                    OceanChip(title: "Prices", symbol: "chart.line.uptrend.xyaxis",
                              tint: Ocean.sky, action: onPriceHistory)
                    if isAutomatic {
                        OceanChip(title: "Exclude", symbol: "eye.slash.fill", tint: Ocean.inkFaint, action: onExclude)
                        if case .mealShortfall(let mealID, _) = item.source {
                            OceanChip(title: "Meal", symbol: "arrow.right", tint: Ocean.tide) {
                                onOpenMeal(mealID)
                            }
                        }
                    } else {
                        OceanChip(title: "Remove", symbol: "trash.fill", tint: Ocean.coral, action: onDelete)
                    }
                }
            }
        }
    }
}

// MARK: - Add item

private struct AddShoppingItemSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var onDone: (String) -> Void

    @State private var name = ""
    @State private var quantityText = "1"
    @State private var unit: MeasureUnit = .piece
    @State private var storeName = ""
    @State private var targetPriceText = ""
    @State private var assigneeID: UUID?
    @State private var errors: [String: String] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(eyebrow: "Shopping", title: "Add an item", tint: Ocean.coral)

                    WaveCard(tint: Ocean.coral) {
                        VStack(alignment: .leading, spacing: 14) {
                            OceanTextField(label: "Item", placeholder: "Olive oil", required: true,
                                           error: errors["name"], text: $name)
                            HStack(alignment: .top, spacing: 12) {
                                QuantityStepperField(label: "Quantity", error: errors["quantity"],
                                                     text: $quantityText, tint: Ocean.coral)
                                VStack(alignment: .leading, spacing: 6) {
                                    FieldLabel(text: "Unit")
                                    Menu {
                                        ForEach(MeasureUnit.allCases) { option in
                                            Button(option.title) { unit = option }
                                        }
                                    } label: {
                                        HStack {
                                            Text(unit.short).font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(Ocean.inkFaint)
                                        }
                                        .padding(.horizontal, 12).padding(.vertical, 12)
                                        .background(RoundedRectangle(cornerRadius: OceanRadius.chip, style: .continuous)
                                            .fill(Ocean.foam.opacity(0.85)))
                                    }
                                }
                            }
                            OceanTextField(label: "Store", placeholder: "optional", text: $storeName)
                            OceanTextField(label: "Target price (\(store.currency))", placeholder: "optional",
                                           error: errors["price"], keyboard: .decimal, text: $targetPriceText)

                            if let members = store.household?.activeMembers, !members.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    FieldLabel(text: "Who buys it")
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            OceanChip(title: "Anyone", tint: Ocean.tide, isOn: assigneeID == nil) {
                                                assigneeID = nil
                                            }
                                            ForEach(members) { member in
                                                OceanChip(title: member.name, tint: Ocean.tide,
                                                          isOn: assigneeID == member.id) {
                                                    assigneeID = member.id
                                                }
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                        }
                    }

                    OceanButton(title: "Add Item", symbol: "plus") { save() }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(OceanBackground(tint: Ocean.coral))
            .navigationTitle("Add Item")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { storeName = store.household?.preferences.defaultStore ?? "" }
        }
    }

    private func save() {
        var found: [String: String] = [:]
        if name.trimmingCharacters(in: .whitespaces).isEmpty { found["name"] = "Item name is required." }
        guard let quantity = Parse.double(quantityText), quantity > 0 else {
            found["quantity"] = "Quantity must be greater than 0."
            errors = found
            Haptics.warning()
            return
        }
        if !targetPriceText.isEmpty && Parse.double(targetPriceText) == nil {
            found["price"] = "Target price must be a number."
        }
        errors = found
        guard found.isEmpty else {
            Haptics.warning()
            return
        }

        let item = ShoppingItem(name: name,
                                quantity: quantity,
                                unit: unit,
                                store: storeName.nilIfBlank,
                                targetPrice: Parse.double(targetPriceText),
                                assigneeID: assigneeID,
                                source: .manual)
        do {
            _ = try store.addShoppingItem(item)
            Haptics.success()
            onDone("\(item.name) · \(Format.measure(quantity, unit))")
            dismiss()
        } catch {
            errors["name"] = error.localizedDescription
            Haptics.warning()
        }
    }
}

// MARK: - Mark purchased

private struct MarkPurchasedSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var itemID: UUID
    var onDone: (String) -> Void

    @State private var quantityText = ""
    @State private var unit: MeasureUnit = .piece
    @State private var priceText = ""
    @State private var storeName = ""
    @State private var bestBefore: Date?
    @State private var zoneID: UUID?
    @State private var error: String?
    @State private var isSaving = false

    private var item: ShoppingItem? { store.shoppingItem(itemID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let item {
                    VStack(alignment: .leading, spacing: 18) {
                        ScreenHeader(eyebrow: item.name,
                                     title: "What did you actually buy?",
                                     subtitle: "Confirming creates one new batch in Inventory and records the price.",
                                     tint: Ocean.turquoise)

                        if let best = store.bestRecentPrice(for: item.productKey) {
                            InfoNote(text: "Your best recent price: \(store.money(best.price) ?? "—") for \(Format.measure(best.quantity, best.unit))\(best.store.map { " at \($0)" } ?? "") on \(DateFormat.day(best.date)).",
                                     symbol: "tag.fill", tint: Ocean.sky)
                        }

                        WaveCard(tint: Ocean.turquoise) {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .top, spacing: 12) {
                                    QuantityStepperField(label: "Quantity bought", error: error,
                                                         text: $quantityText)
                                    VStack(alignment: .leading, spacing: 6) {
                                        FieldLabel(text: "Unit")
                                        Menu {
                                            ForEach(MeasureUnit.allCases) { option in
                                                Button(option.title) { unit = option }
                                            }
                                        } label: {
                                            HStack {
                                                Text(unit.short).font(OceanFont.headline(15))
                                                    .foregroundStyle(Ocean.ink)
                                                Image(systemName: "chevron.up.chevron.down")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(Ocean.inkFaint)
                                            }
                                            .padding(.horizontal, 12).padding(.vertical, 12)
                                            .background(RoundedRectangle(cornerRadius: OceanRadius.chip, style: .continuous)
                                                .fill(Ocean.foam.opacity(0.85)))
                                        }
                                    }
                                }
                                OceanTextField(label: "Price paid (\(store.currency))", placeholder: "optional",
                                               keyboard: .decimal, text: $priceText)
                                OceanTextField(label: "Store", placeholder: "optional", text: $storeName)
                                OptionalDateField(label: "Best before (your date)", date: $bestBefore,
                                                  tint: Ocean.turquoise)
                                VStack(alignment: .leading, spacing: 6) {
                                    FieldLabel(text: "Storage zone")
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            OceanChip(title: "No zone", tint: Ocean.turquoise, isOn: zoneID == nil) {
                                                zoneID = nil
                                            }
                                            ForEach(store.household?.activeZones ?? []) { zone in
                                                OceanChip(title: zone.name, symbol: zone.kind.symbol,
                                                          tint: Ocean.turquoise, isOn: zoneID == zone.id) {
                                                    zoneID = zone.id
                                                }
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                        }

                        OceanButton(title: "Confirm Purchase", symbol: "checkmark", isBusy: isSaving) { save() }

                        InfoNote(text: "Marking the same line purchased twice does nothing the second time — one line can create only one batch.")
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
            }
            .scrollIndicators(.hidden)
            .background(OceanBackground(tint: Ocean.turquoise))
            .navigationTitle("Mark Purchased")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                guard let item else { return }
                quantityText = Format.quantity(item.quantity)
                unit = item.unit
                storeName = item.store ?? store.household?.preferences.defaultStore ?? ""
                zoneID = store.household?.activeZones.first?.id
            }
        }
    }

    private func save() {
        guard !isSaving, let item else { return }
        guard let quantity = Parse.double(quantityText), quantity > 0 else {
            error = "Quantity must be greater than 0."
            Haptics.warning()
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let details = AppStore.PurchaseDetails(quantity: quantity,
                                                   unit: unit,
                                                   price: Parse.double(priceText),
                                                   store: storeName.nilIfBlank,
                                                   bestBefore: bestBefore,
                                                   zoneID: zoneID)
            if let batch = try store.markPurchased(itemID: item.id, details: details) {
                store.rebuildRecallMatches()
                Haptics.success()
                onDone("\(batch.productName) · \(Format.measure(batch.quantity, batch.unit)) added to Inventory")
            } else {
                onDone("This line was already purchased — nothing was duplicated.")
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
            Haptics.warning()
        }
    }
}

// MARK: - Exclude

private struct ExcludeItemSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var itemID: UUID
    var onDone: (String) -> Void

    @State private var reason = ""
    @State private var error: String?

    private let presets = ["Already have enough", "Buying later", "Changed the meal", "Too expensive"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(eyebrow: store.shoppingItem(itemID)?.name ?? "Item",
                                 title: "Why exclude it?",
                                 subtitle: "This line came from a meal. A reason keeps the meal's history readable.",
                                 tint: Ocean.tide)

                    WaveCard(tint: Ocean.tide) {
                        VStack(alignment: .leading, spacing: 12) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(presets, id: \.self) { preset in
                                        OceanChip(title: preset, tint: Ocean.tide, isOn: reason == preset) {
                                            reason = preset
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            OceanTextField(label: "Reason", placeholder: "in your words",
                                           required: true, error: error, text: $reason)
                        }
                    }

                    OceanButton(title: "Exclude with Reason", symbol: "eye.slash.fill") { save() }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(OceanBackground(tint: Ocean.tide))
            .navigationTitle("Exclude")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() {
        do {
            try store.excludeShoppingItem(itemID: itemID, reason: reason)
            Haptics.success()
            onDone(reason)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            Haptics.warning()
        }
    }
}

// MARK: - Missing ingredients picker

private struct MissingIngredientsPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var onDone: (String) -> Void

    private struct Row: Identifiable {
        var id: UUID { meal.id }
        var meal: Meal
        var lines: [StockCheckLine]
    }

    @State private var rows: [Row] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(eyebrow: "Planned meals",
                                 title: "Add missing ingredients",
                                 subtitle: "Only shortfalls you confirm here reach the shopping list.",
                                 tint: Ocean.tide)

                    if rows.isEmpty {
                        EmptyStateCard(symbol: "checkmark.circle.fill",
                                       title: "Nothing is missing",
                                       message: store.plannedMeals.isEmpty
                                        ? "There are no planned meals yet."
                                        : "Every planned meal is fully covered by your batches.",
                                       tint: Ocean.turquoise)
                    } else {
                        ForEach(rows) { row in
                            SectionCard(title: row.meal.name, symbol: "fork.knife", tint: Ocean.tide) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(row.lines) { line in StockCheckRow(line: line) }
                                    OceanButton(title: "Add \(row.lines.count) item(s)", symbol: "cart.badge.plus",
                                                kind: .secondary, tint: Ocean.tide) {
                                        let added = store.addMissingToShopping(meal: row.meal, lines: row.lines)
                                        Haptics.success()
                                        onDone(added == 0 ? "Those lines were already on the list"
                                                          : "\(added) item(s) from \(row.meal.name)")
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(OceanBackground(tint: Ocean.tide))
            .navigationTitle("Add Missing")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                rows = store.plannedMeals.compactMap { meal in
                    let lines = store.stockCheck(for: meal, ignoringReservationsOf: meal.id)
                        .filter { !$0.isCovered }
                    return lines.isEmpty ? nil : Row(meal: meal, lines: lines)
                }
            }
        }
    }
}
