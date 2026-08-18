//
//  MealBuilderView.swift
//  Ocean Cast
//
//  SCREEN 8 — Build a meal, check it against real batches, reserve what exists
//  and confirm what has to be bought.
//

import SwiftUI

struct MealBuilderView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var mealID: UUID?

    @State private var name = ""
    @State private var servingsText = "2"
    @State private var date: Date? = Calendar.current.startOfDay(for: Date())
    @State private var prepText = ""
    @State private var notes = ""
    @State private var ingredients: [MealIngredient] = []
    @State private var errors: [String: String] = [:]
    @State private var checkLines: [StockCheckLine] = []
    @State private var didCheck = false
    @State private var isSaving = false
    @State private var toast: ToastMessage?
    @State private var showAddMissing = false
    @State private var savedMealID: UUID?

    private var isEditing: Bool { mealID != nil }

    private var draft: Meal {
        var meal = Meal(name: name.isEmpty ? "Untitled meal" : name,
                        servings: Parse.int(servingsText) ?? 1,
                        date: date,
                        prepMinutes: Parse.int(prepText),
                        notes: notes.nilIfBlank,
                        ingredients: ingredients,
                        status: date == nil ? .recipe : .planned)
        if let mealID { meal.id = mealID }
        else if let savedMealID { meal.id = savedMealID }
        if let existing = mealID.flatMap({ store.meal($0) }) {
            meal.createdAt = existing.createdAt
            meal.status = existing.status == .cooked ? .cooked : (date == nil ? .recipe : .planned)
        }
        return meal
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(eyebrow: isEditing ? "Edit meal" : "New meal",
                                 title: isEditing ? "Update this meal" : "Build a meal from real stock",
                                 subtitle: "Reserving lowers Available for other plans, but never touches On hand.",
                                 tint: Ocean.tide)

                    basicsCard
                    ingredientsCard
                    if didCheck { stockCheckCard }
                    actions
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(OceanBackground(tint: Ocean.tide))
            .toastHost($toast)
            .navigationTitle(isEditing ? "Edit Meal" : "Create Meal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Meal") { save() }.disabled(isSaving)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog("Add missing amounts to Shopping Plan?",
                                isPresented: $showAddMissing, titleVisibility: .visible) {
                Button("Add \(missingLines.count) item(s)") { addMissing() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(missingLines.map { line in
                    line.incompatibleUnits
                        ? "\(line.ingredient.name): units do not match your stock — the full amount will be added"
                        : "\(line.ingredient.name): \(Format.measure(line.missing, line.ingredient.unit))"
                }.joined(separator: "\n"))
            }
        }
    }

    private var missingLines: [StockCheckLine] {
        checkLines.filter { !$0.isCovered }
    }

    // MARK: - Cards

    private var basicsCard: some View {
        SectionCard(title: "Meal", symbol: "fork.knife", tint: Ocean.tide) {
            VStack(alignment: .leading, spacing: 14) {
                OceanTextField(label: "Meal name", placeholder: "Sunday pasta",
                               required: true, error: errors["name"], text: $name)

                HStack(alignment: .top, spacing: 12) {
                    QuantityStepperField(label: "Servings", error: errors["servings"],
                                         text: $servingsText, tint: Ocean.tide)
                    OceanTextField(label: "Prep minutes", placeholder: "optional",
                                   keyboard: .number, text: $prepText)
                }

                OptionalDateField(label: "Date",
                                  note: date == nil
                                    ? "No date — this is saved as a recipe and reserves nothing."
                                    : "A dated meal can reserve ingredients.",
                                  date: $date, tint: Ocean.tide)

                OceanTextField(label: "Notes", placeholder: "optional", text: $notes)
            }
        }
    }

    private var ingredientsCard: some View {
        SectionCard(title: "Ingredients", symbol: "list.bullet", tint: Ocean.turquoise,
                    accessory: {
            Text("per serving").font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
        }, content: {
            VStack(alignment: .leading, spacing: 12) {
                if ingredients.isEmpty {
                    Text("No ingredients yet. Add at least one — the stock check works from these lines.")
                        .font(OceanFont.body(14)).foregroundStyle(Ocean.inkSoft)
                }
                if let error = errors["ingredients"] {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.coral)
                }

                ForEach($ingredients) { $ingredient in
                    IngredientEditor(ingredient: $ingredient,
                                     suggestions: store.knownProductNames,
                                     servings: Parse.int(servingsText) ?? 1,
                                     onDelete: {
                                         ingredients.removeAll { $0.id == ingredient.id }
                                         didCheck = false
                                     })
                }

                OceanButton(title: "Add Ingredient", symbol: "plus",
                            kind: .secondary, tint: Ocean.turquoise) {
                    ingredients.append(MealIngredient(name: "", quantityPerServing: 1, unit: .piece))
                    didCheck = false
                }
            }
        })
    }

    private var stockCheckCard: some View {
        SectionCard(title: "Stock check", symbol: "checklist", tint: Ocean.sky) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(checkLines) { line in
                    StockCheckRow(line: line)
                }
                if missingLines.isEmpty {
                    Text("Everything is covered by batches you already have.")
                        .font(OceanFont.caption(12)).foregroundStyle(Ocean.turquoise)
                } else {
                    Text("\(missingLines.count) ingredient(s) are short. Nothing goes to Shopping until you confirm it.")
                        .font(OceanFont.caption(12)).foregroundStyle(Ocean.coral)
                    OceanButton(title: "Add Missing to Shopping", symbol: "cart.badge.plus",
                                kind: .secondary, tint: Ocean.coral) {
                        showAddMissing = true
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            OceanButton(title: "Check Stock", symbol: "magnifyingglass",
                        kind: .secondary, tint: Ocean.sky) { checkStock() }
            OceanButton(title: "Reserve Ingredients", symbol: "lock.fill",
                        kind: .secondary, tint: Ocean.tide) { reserve() }
            OceanButton(title: "Save Meal", symbol: "checkmark", isBusy: isSaving) { save() }
        }
    }

    // MARK: - Actions

    private func load() {
        guard let mealID, let meal = store.meal(mealID) else { return }
        name = meal.name
        servingsText = String(meal.servings)
        date = meal.date
        prepText = meal.prepMinutes.map(String.init) ?? ""
        notes = meal.notes ?? ""
        ingredients = meal.ingredients
    }

    private func validate() -> Bool {
        var found: [String: String] = [:]
        if name.trimmingCharacters(in: .whitespaces).isEmpty { found["name"] = "Meal name is required." }
        if let servings = Parse.int(servingsText) {
            if servings <= 0 { found["servings"] = "Servings must be at least 1." }
        } else {
            found["servings"] = "Enter how many servings."
        }
        let filled = ingredients.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        if filled.isEmpty { found["ingredients"] = "Add at least one ingredient with a name." }
        if filled.contains(where: { $0.quantityPerServing <= 0 }) {
            found["ingredients"] = "Every ingredient needs a quantity greater than 0."
        }
        errors = found
        if !found.isEmpty { Haptics.warning() }
        return found.isEmpty
    }

    private func checkStock() {
        guard validate() else { return }
        checkLines = store.stockCheck(for: draft, ignoringReservationsOf: mealID ?? savedMealID)
        didCheck = true
        Haptics.tap()
        let incompatible = checkLines.filter(\.incompatibleUnits).count
        if incompatible > 0 {
            toast = ToastMessage(kind: .warning,
                                 title: "\(incompatible) ingredient(s) use different units",
                                 detail: "Conversion is blocked — choose a matching unit.")
        }
    }

    @discardableResult
    private func save() -> Meal? {
        guard !isSaving, validate() else { return nil }
        isSaving = true
        defer { isSaving = false }
        var meal = draft
        meal.ingredients = ingredients.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        do {
            let saved = try store.saveMeal(meal)
            savedMealID = saved.id
            Haptics.success()
            toast = ToastMessage(title: "Meal saved",
                                 detail: saved.status == .recipe
                                    ? "Saved as a recipe — it reserves nothing until you give it a date."
                                    : "Planned for \(saved.date.map(DateFormat.day) ?? "no date")")
            return saved
        } catch {
            errors["name"] = error.localizedDescription
            Haptics.warning()
            return nil
        }
    }

    private func reserve() {
        guard date != nil else {
            toast = ToastMessage(kind: .warning, title: "Give the meal a date first",
                                 detail: "Recipes without a date never hold stock.")
            Haptics.warning()
            return
        }
        guard let saved = save() else { return }
        let lines = store.reserveIngredients(mealID: saved.id)
        checkLines = lines
        didCheck = true
        let covered = lines.filter(\.isCovered).count
        Haptics.success()
        toast = ToastMessage(title: "Reserved from \(covered)/\(lines.count) ingredient(s)",
                             detail: "Available went down. On hand did not change.")
    }

    private func addMissing() {
        let meal = draft
        let added = store.addMissingToShopping(meal: meal, lines: missingLines)
        Haptics.success()
        toast = ToastMessage(title: added == 0 ? "Already on the list" : "\(added) item(s) added to Shopping",
                             detail: "Open Shopping to set store, target price and who buys it.")
    }
}

// MARK: - Ingredient editor

private struct IngredientEditor: View {
    @Binding var ingredient: MealIngredient
    var suggestions: [String]
    var servings: Int
    var onDelete: () -> Void

    @State private var quantityText = ""

    private var matches: [String] {
        guard !ingredient.name.isEmpty else { return [] }
        let needle = ProductKey.make(ingredient.name)
        return suggestions.filter { ProductKey.make($0).contains(needle) && ProductKey.make($0) != needle }.prefix(3).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                OceanTextField(label: "Ingredient", placeholder: "Pasta", text: $ingredient.name)
                Button {
                    Haptics.tap()
                    onDelete()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Ocean.coral)
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
            }

            if !matches.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(matches, id: \.self) { suggestion in
                            OceanChip(title: suggestion, tint: Ocean.turquoise) {
                                ingredient.name = suggestion
                            }
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 10) {
                OceanField(label: "Per serving", tint: Ocean.turquoise) {
                    TextField("1", text: Binding(
                        get: { quantityText.isEmpty ? Format.quantity(ingredient.quantityPerServing) : quantityText },
                        set: { newValue in
                            quantityText = newValue
                            ingredient.quantityPerServing = Parse.double(newValue) ?? 0
                        }
                    ))
                    .font(OceanFont.headline(15))
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                }
                VStack(alignment: .leading, spacing: 6) {
                    FieldLabel(text: "Unit")
                    Menu {
                        ForEach(MeasureUnit.allCases) { unit in
                            Button(unit.title) { ingredient.unit = unit }
                        }
                    } label: {
                        HStack {
                            Text(ingredient.unit.short).font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(Ocean.inkFaint)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: OceanRadius.chip, style: .continuous)
                            .fill(Ocean.foam.opacity(0.85)))
                    }
                }
            }

            Text("Total for \(servings) serving(s): \(Format.measure(ingredient.quantityPerServing * Double(max(servings, 0)), ingredient.unit))")
                .font(OceanFont.caption(11))
                .foregroundStyle(Ocean.inkSoft)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Ocean.foam.opacity(0.7)))
    }
}

// MARK: - Stock check row

struct StockCheckRow: View {
    var line: StockCheckLine

    private var tint: Color {
        if line.incompatibleUnits { return Ocean.tide }
        return line.isCovered ? Ocean.turquoise : Ocean.coral
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FloatDisc(symbol: line.incompatibleUnits ? "ruler.fill" : (line.isCovered ? "checkmark" : "cart.badge.plus"),
                      tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(line.ingredient.name)
                    .font(OceanFont.headline(14)).foregroundStyle(Ocean.ink)
                if line.incompatibleUnits {
                    Text("Your stock uses a different kind of unit. Ocean Cast will not convert pieces into weight — Choose Unit to match.")
                        .font(OceanFont.caption(11)).foregroundStyle(Ocean.tide)
                        .fixedSize(horizontal: false, vertical: true)
                } else if line.isCovered {
                    Text("Covered: \(Format.measure(line.need, line.ingredient.unit)) from \(line.allocations.count) batch(es)")
                        .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                } else {
                    Text("Need \(Format.measure(line.need, line.ingredient.unit)) · have \(Format.measure(line.covered, line.ingredient.unit)) · short \(Format.measure(line.missing, line.ingredient.unit))")
                        .font(OceanFont.caption(11)).foregroundStyle(Ocean.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
