//
//  SmartUseIdeasView.swift
//  Ocean Cast
//
//  SCREEN 9 — Ranking, not magic. Your own saved meals are scored against the
//  batches you have and the dates that are closest.
//

import SwiftUI

struct SmartUseIdeasView: View {
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var navigator

    @State private var onlyFullyCovered = false
    @State private var excluded: Set<String> = []
    @State private var maxMinutesText = ""
    @State private var results: [IdeaMatch] = []
    @State private var didRun = false
    @State private var explaining: UUID?
    @State private var planningMeal: Meal?
    @State private var toast: ToastMessage?

    private var candidateMeals: [Meal] {
        store.data.meals.filter { !$0.archived && !$0.ingredients.isEmpty }
    }

    private var hasEnoughStock: Bool { store.activeBatches.count >= 3 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Smart Use Ideas",
                             title: "What your stock already covers",
                             subtitle: "This is a ranking of meals you saved — not a recipe generator and not a promise.",
                             tint: Ocean.turquoise)

                if !hasEnoughStock {
                    EmptyStateCard(symbol: "tray.fill",
                                   title: "Not enough to rank yet",
                                   message: "Add at least three inventory items to get useful matches. With fewer items every score would say more about the gaps than about your kitchen.",
                                   actionTitle: "Add an item",
                                   tint: Ocean.coral) {
                        navigator.sheet = .addProduct(barcode: nil)
                    }
                } else if candidateMeals.isEmpty {
                    EmptyStateCard(symbol: "book.closed.fill",
                                   title: "No meals to rank",
                                   message: "Ideas come from meals you saved. Create one meal and it becomes a candidate here — Ocean Cast never invents recipes.",
                                   actionTitle: "Create Meal",
                                   tint: Ocean.tide) {
                        navigator.sheet = .mealBuilder(mealID: nil)
                    }
                } else {
                    filterCard
                    OceanButton(title: "Show Matches", symbol: "sparkles") { run() }

                    if didRun {
                        if results.isEmpty {
                            EmptyStateCard(symbol: "magnifyingglass",
                                           title: "No meal fits these filters",
                                           message: "Loosen the filters, or plan a meal and add its missing items to the shopping list.",
                                           tint: Ocean.coral)
                        } else {
                            ForEach(results) { match in
                                IdeaCard(match: match,
                                         currency: store.currency,
                                         isExplaining: explaining == match.id,
                                         onExplain: {
                                             withAnimation(OceanMotion.pop) {
                                                 explaining = explaining == match.id ? nil : match.id
                                             }
                                         },
                                         onOpen: { navigator.push(.meal(match.meal.id)) },
                                         onPlan: { planningMeal = match.meal })
                            }
                        }
                    } else {
                        InfoNote(text: "Nothing is saved from this screen until you plan a meal. Ranking runs only when you ask for it.")
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
        .navigationTitle("Smart Use Ideas")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $planningMeal) { meal in
            PlanIdeaSheet(meal: meal) { message in
                toast = ToastMessage(title: "Meal planned", detail: message)
                run()
            }
        }
        .oceanTabInset()
    }

    private var filterCard: some View {
        SectionCard(title: "Filters", symbol: "slider.horizontal.3", tint: Ocean.tide) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $onlyFullyCovered) {
                    Text("Use What I Have (fully covered only)")
                        .font(OceanFont.body(14.5)).foregroundStyle(Ocean.ink)
                }
                .tint(Ocean.turquoise)

                OceanTextField(label: "Maximum time (minutes)", placeholder: "no limit",
                               keyboard: .number, text: $maxMinutesText)

                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Exclude ingredient")
                    if store.knownProductNames.isEmpty {
                        Text("Nothing recorded yet.").font(OceanFont.caption(11.5)).foregroundStyle(Ocean.inkSoft)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(store.knownProductNames.prefix(12), id: \.self) { name in
                                    let key = ProductKey.make(name)
                                    OceanChip(title: name, tint: Ocean.coral, isOn: excluded.contains(key)) {
                                        if excluded.contains(key) { excluded.remove(key) } else { excluded.insert(key) }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    private func run() {
        let limit = Parse.int(maxMinutesText)
        var matches: [IdeaMatch] = []

        for meal in candidateMeals {
            if let limit, let minutes = meal.prepMinutes, minutes > limit { continue }
            if let limit, meal.prepMinutes == nil, limit > 0 {
                // A meal without a recorded time cannot be judged against a limit.
                continue
            }
            if meal.ingredients.contains(where: { excluded.contains($0.productKey) }) { continue }

            let lines = store.stockCheck(for: meal, ignoringReservationsOf: meal.id)
            guard !lines.isEmpty else { continue }
            let coveredCount = lines.filter(\.isCovered).count
            let coverage = Double(coveredCount) / Double(lines.count)
            if onlyFullyCovered && coverage < 1 { continue }

            let usesExpiring = lines.contains { line in
                line.allocations.contains { allocation in
                    guard let batch = store.batch(allocation.batchID) else { return false }
                    return store.expiryState(batch).isAttention
                }
            }
            let expiringCount = lines.reduce(0) { partial, line in
                partial + line.allocations.filter { allocation in
                    guard let batch = store.batch(allocation.batchID) else { return false }
                    return store.expiryState(batch).isAttention
                }.count
            }
            let score = coverage * 0.65 + min(Double(expiringCount) / 3.0, 1.0) * 0.35
            matches.append(IdeaMatch(meal: meal, lines: lines, coverage: coverage,
                                     expiringUsed: expiringCount, usesExpiring: usesExpiring, score: score))
        }

        results = matches.sorted { $0.score > $1.score }
        didRun = true
        Haptics.tap()
    }
}

struct IdeaMatch: Identifiable {
    var id: UUID { meal.id }
    var meal: Meal
    var lines: [StockCheckLine]
    var coverage: Double
    var expiringUsed: Int
    var usesExpiring: Bool
    var score: Double

    var covered: [StockCheckLine] { lines.filter(\.isCovered) }
    var missing: [StockCheckLine] { lines.filter { !$0.isCovered } }
}

private struct IdeaCard: View {
    var match: IdeaMatch
    var currency: String
    var isExplaining: Bool
    var onExplain: () -> Void
    var onOpen: () -> Void
    var onPlan: () -> Void

    private var tint: Color { match.coverage >= 1 ? Ocean.turquoise : Ocean.sky }

    var body: some View {
        WaveCard(tint: tint, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    StockRing(progress: match.coverage, tint: tint, size: 52,
                              centerText: Format.percent(match.coverage))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(match.meal.name)
                            .font(OceanFont.title(17)).foregroundStyle(Ocean.ink)
                            .multilineTextAlignment(.leading)
                        Text("\(match.covered.count) of \(match.lines.count) ingredient(s) covered")
                            .font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                        if match.usesExpiring {
                            Label("uses \(match.expiringUsed) batch(es) close to your date",
                                  systemImage: "clock.fill")
                                .font(OceanFont.caption(11)).foregroundStyle(Ocean.coral)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if !match.missing.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Missing")
                            .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                        ForEach(match.missing) { line in
                            Text("· \(line.ingredient.name) — \(line.incompatibleUnits ? "unit mismatch" : Format.measure(line.missing, line.ingredient.unit))")
                                .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.coral)
                        }
                    }
                }

                if isExplaining {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Why this match?")
                            .font(OceanFont.headline(13.5)).foregroundStyle(Ocean.ink)
                        Text("Coverage \(Format.percent(match.coverage)) — how many ingredients your batches can supply right now (weight 65%).")
                            .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.inkSoft)
                        Text("Date pressure — \(match.expiringUsed) allocated batch(es) are inside your expiry window (weight 35%).")
                            .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.inkSoft)
                        Text("Nothing else is used: no popularity, no external data, no guesses about taste.")
                            .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkFaint)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Ocean.foam.opacity(0.8)))
                }

                HStack(spacing: 8) {
                    OceanChip(title: "Why This Match?", symbol: "questionmark.circle.fill",
                              tint: Ocean.tide, isOn: isExplaining, action: onExplain)
                    OceanChip(title: "Open", symbol: "arrow.right", tint: Ocean.turquoise, action: onOpen)
                    OceanChip(title: "Plan it", symbol: "calendar.badge.plus", tint: Ocean.blue, action: onPlan)
                }
            }
        }
    }
}

private struct PlanIdeaSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var meal: Meal
    var onDone: (String) -> Void

    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var servingsText = ""
    @State private var reserveNow = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(eyebrow: meal.name, title: "Plan this meal", tint: Ocean.blue)

                    WaveCard(tint: Ocean.blue) {
                        VStack(alignment: .leading, spacing: 14) {
                            OceanField(label: "Date", required: true) {
                                DatePicker("", selection: $date, displayedComponents: .date).labelsHidden()
                            }
                            QuantityStepperField(label: "Servings", error: error,
                                                 text: $servingsText, tint: Ocean.blue)
                            Toggle(isOn: $reserveNow) {
                                Text("Reserve ingredients now")
                                    .font(OceanFont.body(14.5)).foregroundStyle(Ocean.ink)
                            }
                            .tint(Ocean.tide)
                            Text("Planning copies this meal into a new dated entry. The original stays as it is.")
                                .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                        }
                    }

                    OceanButton(title: "Save Plan", symbol: "checkmark") { save() }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(OceanBackground(tint: Ocean.blue))
            .navigationTitle("Plan Meal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { servingsText = String(meal.servings) }
        }
    }

    private func save() {
        guard let servings = Parse.int(servingsText), servings > 0 else {
            error = "Servings must be at least 1."
            Haptics.warning()
            return
        }
        var planned = meal
        planned.id = UUID()
        planned.date = date
        planned.servings = servings
        planned.status = .planned
        planned.createdAt = Date()
        planned.cookedAt = nil
        planned.ingredients = meal.ingredients.map { ingredient in
            var copy = ingredient
            copy.id = UUID()
            return copy
        }
        do {
            let saved = try store.saveMeal(planned)
            var detail = "Planned for \(DateFormat.day(date))."
            if reserveNow {
                let lines = store.reserveIngredients(mealID: saved.id)
                detail += " Reserved \(lines.filter(\.isCovered).count)/\(lines.count) ingredient(s)."
            }
            Haptics.success()
            onDone(detail)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            Haptics.warning()
        }
    }
}
