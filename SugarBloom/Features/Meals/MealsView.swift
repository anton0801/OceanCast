//
//  MealsView.swift
//  Ocean Cast
//
//  Planned meals and saved recipes, plus the detail screen where a meal is
//  reserved, cooked or released.
//

import SwiftUI

struct MealsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var navigator

    enum Segment: String, CaseIterable, Identifiable {
        case planned, recipes, done
        var id: String { rawValue }
        var title: String {
            switch self {
            case .planned: return "Planned"
            case .recipes: return "Recipes"
            case .done: return "Cooked"
            }
        }
    }

    @State private var segment: Segment = .planned
    @State private var toast: ToastMessage?

    private var meals: [Meal] {
        switch segment {
        case .planned: return store.plannedMeals
        case .recipes: return store.data.meals.filter { $0.status == .recipe && !$0.archived }
        case .done: return store.data.meals.filter { $0.status == .cooked || $0.status == .cancelled }
            .sorted { ($0.cookedAt ?? $0.createdAt) > ($1.cookedAt ?? $1.createdAt) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Meals",
                             title: "Plan from what you have",
                             subtitle: "A planned meal reserves ingredients. Cooking turns those reservations into real usage.",
                             tint: Ocean.tide)

                HStack(spacing: 8) {
                    ForEach(Segment.allCases) { option in
                        OceanChip(title: option.title, tint: Ocean.tide, isOn: segment == option) {
                            segment = option
                        }
                    }
                }

                OceanButton(title: "Create Meal", symbol: "plus") {
                    navigator.sheet = .mealBuilder(mealID: nil)
                }
                OceanButton(title: "Smart Use Ideas", symbol: "sparkles",
                            kind: .secondary, tint: Ocean.turquoise) {
                    navigator.push(.ideas)
                }

                if meals.isEmpty {
                    emptyState
                } else {
                    ForEach(meals) { meal in
                        MealCard(meal: meal) { navigator.push(.meal(meal.id)) }
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
        .navigationTitle("Meals")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .oceanTabInset()
    }

    @ViewBuilder
    private var emptyState: some View {
        switch segment {
        case .planned:
            EmptyStateCard(symbol: "fork.knife",
                           title: "No planned meals",
                           message: store.activeBatches.isEmpty
                            ? "Add a few items first — a meal can only reserve stock that exists."
                            : "Create a meal to see what your batches already cover and what is missing.",
                           actionTitle: store.activeBatches.isEmpty ? "Add an item" : "Create Meal",
                           tint: Ocean.tide) {
                if store.activeBatches.isEmpty { navigator.sheet = .addProduct(barcode: nil) }
                else { navigator.sheet = .mealBuilder(mealID: nil) }
            }
        case .recipes:
            EmptyStateCard(symbol: "book.closed.fill",
                           title: "No saved recipes",
                           message: "A meal saved without a date becomes a recipe. Recipes never hold stock, and Smart Use Ideas ranks them against what you have.",
                           tint: Ocean.turquoise)
        case .done:
            EmptyStateCard(symbol: "checkmark.circle.fill",
                           title: "Nothing cooked yet",
                           message: "Once you mark a planned meal as cooked, it appears here with the batches it used.",
                           tint: Ocean.turquoise)
        }
    }
}

struct MealCard: View {
    @Environment(AppStore.self) private var store
    var meal: Meal
    var onOpen: () -> Void

    private var tint: Color { Ocean.accent(for: meal.name) }

    private var reservedCount: Int {
        store.data.reservations.filter { $0.mealID == meal.id }.count
    }

    var body: some View {
        Button(action: onOpen) {
            WaveCard(tint: tint, padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        FloatDisc(symbol: "fork.knife", tint: tint, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(meal.name)
                                .font(OceanFont.title(17)).foregroundStyle(Ocean.ink)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 6) {
                                Text(meal.status.title)
                                if let date = meal.date { Text("· \(DateFormat.shortDay(date))") }
                                Text("· \(meal.servings) serving(s)")
                            }
                            .font(OceanFont.caption(11.5))
                            .foregroundStyle(Ocean.inkSoft)
                        }
                        Spacer(minLength: 0)
                        RowChevron()
                    }

                    HStack(spacing: 8) {
                        Label("\(meal.ingredients.count) ingredient(s)", systemImage: "list.bullet")
                        if reservedCount > 0 {
                            Label("\(reservedCount) reservation(s)", systemImage: "lock.fill")
                                .foregroundStyle(Ocean.tide)
                        }
                        if let minutes = meal.prepMinutes {
                            Label("\(minutes) min", systemImage: "timer")
                        }
                    }
                    .font(OceanFont.caption(11))
                    .foregroundStyle(Ocean.inkFaint)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail

struct MealDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss

    var mealID: UUID

    @State private var lines: [StockCheckLine] = []
    @State private var toast: ToastMessage?
    @State private var showDelete = false
    @State private var showAddMissing = false
    @State private var showCookConfirm = false

    private var meal: Meal? { store.meal(mealID) }
    private var reservations: [Reservation] { store.data.reservations.filter { $0.mealID == mealID } }
    private var missing: [StockCheckLine] { lines.filter { !$0.isCovered } }

    var body: some View {
        Group {
            if let meal {
                content(meal)
            } else {
                ScrollView {
                    EmptyStateCard(symbol: "questionmark.folder.fill",
                                   title: "This meal is gone",
                                   message: "It was deleted from another screen.",
                                   actionTitle: "Back",
                                   tint: Ocean.coral) { dismiss() }
                        .padding(20)
                }
            }
        }
        .background(OceanBackground(tint: Ocean.tide))
        .toastHost($toast)
        .navigationTitle("Meal")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .oceanTabInset()
        .onAppear(perform: refresh)
    }

    private func content(_ meal: Meal) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard(meal)
                stockCard(meal)
                if !reservations.isEmpty { reservationsCard(meal) }
                actions(meal)
                historyCard(meal)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .confirmationDialog("Delete this meal?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete meal", role: .destructive) {
                store.deleteMeal(mealID: mealID)
                Haptics.warning()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.mealDeletionImpact(mealID: mealID).lines.joined(separator: "\n"))
        }
        .confirmationDialog("Add missing amounts to Shopping Plan?",
                            isPresented: $showAddMissing, titleVisibility: .visible) {
            Button("Add \(missing.count) item(s)") {
                let added = store.addMissingToShopping(meal: meal, lines: missing)
                Haptics.success()
                toast = ToastMessage(title: added == 0 ? "Already on the list" : "\(added) item(s) added")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the amounts you are short of are added. Nothing is bought automatically.")
        }
        .confirmationDialog("Mark this meal as cooked?", isPresented: $showCookConfirm, titleVisibility: .visible) {
            Button("Cook and use \(reservations.count) reservation(s)") { cook() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reserved amounts become real usage: On hand goes down and every batch records why.")
        }
    }

    private func headerCard(_ meal: Meal) -> some View {
        WaveCard(tint: Ocean.tide, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    FloatDisc(symbol: "fork.knife", tint: Ocean.tide, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(meal.name).font(OceanFont.title(20)).foregroundStyle(Ocean.ink)
                        Text("\(meal.status.title) · \(meal.servings) serving(s)")
                            .font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                        if let date = meal.date {
                            Text(DateFormat.day(date)).font(OceanFont.caption(11.5)).foregroundStyle(Ocean.tide)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let notes = meal.notes {
                    Text(notes).font(OceanFont.body(14)).foregroundStyle(Ocean.inkSoft)
                }
            }
        }
    }

    private func stockCard(_ meal: Meal) -> some View {
        SectionCard(title: "Stock check", symbol: "checklist", tint: Ocean.sky,
                    accessory: {
            Button {
                refresh()
                Haptics.tap()
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Ocean.sky)
            }
            .buttonStyle(.plain)
        }, content: {
            VStack(alignment: .leading, spacing: 12) {
                if lines.isEmpty {
                    Text("This meal has no ingredients.")
                        .font(OceanFont.body(14)).foregroundStyle(Ocean.inkSoft)
                } else {
                    ForEach(lines) { line in StockCheckRow(line: line) }
                }
                if !missing.isEmpty {
                    OceanButton(title: "Add Missing to Shopping", symbol: "cart.badge.plus",
                                kind: .secondary, tint: Ocean.coral) { showAddMissing = true }
                }
            }
        })
    }

    private func reservationsCard(_ meal: Meal) -> some View {
        SectionCard(title: "Reserved batches", symbol: "lock.fill", tint: Ocean.turquoise) {
            VStack(spacing: 8) {
                ForEach(reservations) { reservation in
                    if let batch = store.batch(reservation.batchID) {
                        Button {
                            navigator.push(.product(batch.id))
                        } label: {
                            HStack(spacing: 10) {
                                FloatDisc(symbol: "shippingbox.fill", tint: Ocean.turquoise, size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(batch.displayTitle)
                                        .font(OceanFont.headline(14)).foregroundStyle(Ocean.ink)
                                    Text("\(Format.measure(reservation.quantity, batch.unit)) held · \(Format.measure(batch.remaining, batch.unit)) on hand")
                                        .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                                }
                                Spacer()
                                RowChevron()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func actions(_ meal: Meal) -> some View {
        VStack(spacing: 10) {
            if meal.status == .planned {
                OceanButton(title: reservations.isEmpty ? "Reserve Ingredients" : "Re-check and Reserve",
                            symbol: "lock.fill") {
                    lines = store.reserveIngredients(mealID: mealID)
                    Haptics.success()
                    toast = ToastMessage(title: "Reservations updated",
                                         detail: "Available changed. On hand did not.")
                }
                if !reservations.isEmpty {
                    OceanButton(title: "Mark as Cooked", symbol: "flame.fill",
                                kind: .secondary, tint: Ocean.coral) { showCookConfirm = true }
                    OceanButton(title: "Release Reservations", symbol: "lock.open.fill",
                                kind: .ghost) {
                        store.releaseReservations(mealID: mealID)
                        refresh()
                        Haptics.success()
                        toast = ToastMessage(kind: .info, title: "Reservations released")
                    }
                }
                OceanButton(title: "Cancel Meal", symbol: "xmark", kind: .ghost) {
                    store.cancelMeal(mealID: mealID)
                    refresh()
                    toast = ToastMessage(kind: .info, title: "Meal cancelled",
                                         detail: "Reserved stock went back to Available.")
                }
            }
            OceanButton(title: "Edit Meal", symbol: "square.and.pencil",
                        kind: .secondary, tint: Ocean.tide) {
                navigator.sheet = .mealBuilder(mealID: mealID)
            }
            OceanButton(title: "Delete Meal", symbol: "trash.fill", kind: .danger) { showDelete = true }
        }
    }

    private func historyCard(_ meal: Meal) -> some View {
        let entries = store.history(mealID: mealID)
        return SectionCard(title: "History", symbol: "clock.arrow.circlepath", tint: Ocean.turquoise) {
            VStack(spacing: 8) {
                if entries.isEmpty {
                    Text("No records yet.").font(OceanFont.body(14)).foregroundStyle(Ocean.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(entries.prefix(8)) { entry in ActivityRow(entry: entry) }
                }
            }
        }
    }

    private func refresh() {
        guard let meal else { return }
        lines = store.stockCheck(for: meal, ignoringReservationsOf: mealID)
    }

    private func cook() {
        do {
            try store.cookMeal(mealID: mealID)
            refresh()
            Haptics.success()
            toast = ToastMessage(title: "Cooked", detail: "Batches were reduced and the reason recorded.")
        } catch {
            Haptics.warning()
            toast = ToastMessage(kind: .warning, title: "Not cooked", detail: error.localizedDescription)
        }
    }
}
