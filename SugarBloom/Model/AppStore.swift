//
//  AppStore.swift
//  Ocean Cast
//
//  Single source of truth. Every number on every screen is derived here from
//  saved records — nothing is duplicated, nothing is invented.
//

import Foundation
import Observation

enum AppError: LocalizedError {
    case validation(String)
    case conflict(String)

    var errorDescription: String? {
        switch self {
        case .validation(let m): return m
        case .conflict(let m): return m
        }
    }
}

/// How a dated batch stands relative to the user's own date.
enum ExpiryState: Equatable {
    case unknown
    case expired(days: Int)
    case soon(days: Int)
    case later(days: Int)

    var isAttention: Bool {
        switch self {
        case .expired, .soon: return true
        default: return false
        }
    }
}

struct LowStockLine: Identifiable, Hashable {
    var id: String { key }
    var key: String
    var name: String
    var available: Double
    var unit: MeasureUnit
    var threshold: Double
}

struct NextAction: Equatable {
    var title: String
    var detail: String
    var symbol: String
    var route: Route?
}

struct DeletionImpact {
    var lines: [String]
    var blocking: Bool
}

@MainActor
@Observable
final class AppStore {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var data = AppData()
    private(set) var loadState: LoadState = .loading
    private(set) var lastSavedAt: Date?
    var saveErrorMessage: String?

    @ObservationIgnored private let persistence = PersistenceController.shared
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(loadImmediately: Bool = true) {
        if loadImmediately { load() }
    }

    // MARK: - Loading & saving

    func load() {
        loadState = .loading
        do {
            data = try persistence.load()
            lastSavedAt = data.savedAt
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func mutate(_ block: (inout AppData) -> Void) {
        block(&data)
        scheduleSave()
    }

    /// Remembers a local delete so the next sync can replicate it instead of
    /// letting the record reappear from the server.
    static func tombstone(_ resource: String, _ ids: [String], into data: inout AppData) {
        guard !ids.isEmpty else { return }
        let now = Date()
        for id in ids {
            data.tombstones.append(Tombstone(resource: resource, recordID: id, deletedAt: now))
        }
        // Keep the list bounded; anything older than 90 days has long been synced.
        if data.tombstones.count > 2000 {
            data.tombstones.removeFirst(data.tombstones.count - 2000)
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        do {
            try persistence.save(data)
            lastSavedAt = Date()
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Convenience

    var household: Household? { data.household }
    var currency: String { data.household?.currencyCode ?? "USD" }
    var hasHousehold: Bool { data.household != nil }

    func money(_ value: Double?) -> String? { Format.money(value, currency: currency) }

    func zone(_ id: UUID?) -> StorageZone? {
        guard let id else { return nil }
        return data.household?.zones.first { $0.id == id }
    }

    func zoneName(_ id: UUID?) -> String? { zone(id)?.name }

    func member(_ id: UUID?) -> Member? {
        guard let id else { return nil }
        return data.household?.members.first { $0.id == id }
    }

    func batch(_ id: UUID) -> Batch? { data.batches.first { $0.id == id } }
    func meal(_ id: UUID) -> Meal? { data.meals.first { $0.id == id } }
    func shoppingItem(_ id: UUID) -> ShoppingItem? { data.shopping.first { $0.id == id } }
    func alert(_ id: String) -> RecallAlert? { data.recallAlerts.first { $0.id == id } }

    // MARK: - Derived inventory

    var activeBatches: [Batch] {
        data.batches.filter { !$0.archived && !$0.isDepleted }
    }

    var archivedBatches: [Batch] {
        data.batches.filter { $0.archived }
    }

    func reserved(_ batchID: UUID) -> Double {
        data.reservations.filter { $0.batchID == batchID }.reduce(0) { $0 + $1.quantity }
    }

    func available(_ batch: Batch) -> Double {
        max(0, batch.remaining - reserved(batch.id))
    }

    func reservations(for batchID: UUID) -> [Reservation] {
        data.reservations.filter { $0.batchID == batchID }
    }

    func batches(key: String) -> [Batch] {
        activeBatches.filter { $0.productKey == key }
    }

    /// Product names the user has actually recorded, most recent first.
    var knownProductNames: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for batch in data.batches.sorted(by: { $0.createdAt > $1.createdAt }) {
            if seen.insert(batch.productKey).inserted { result.append(batch.productName) }
        }
        return result
    }

    func expiryState(_ batch: Batch, now: Date = Date()) -> ExpiryState {
        guard let date = batch.bestBefore else { return .unknown }
        let days = DateFormat.daysBetween(now, date)
        if days < 0 { return .expired(days: -days) }
        if days <= max(0, data.settings.expiryWindowDays) { return .soon(days: days) }
        return .later(days: days)
    }

    /// Batches worth reviewing: past the user's date or inside the window.
    var expiringSoon: [Batch] {
        activeBatches
            .filter { expiryState($0).isAttention }
            .sorted { ($0.bestBefore ?? .distantFuture) < ($1.bestBefore ?? .distantFuture) }
    }

    /// Batches with no user date — reported as unknown, never as fresh or expired.
    var undatedBatches: [Batch] {
        activeBatches.filter { $0.bestBefore == nil }
    }

    var openedBatches: [Batch] { activeBatches.filter { $0.opened } }

    var reservedBatches: [Batch] { activeBatches.filter { reserved($0.id) > 0 } }

    // MARK: - Low stock

    var hasAnyThreshold: Bool {
        !data.restockThresholds.isEmpty || data.household?.preferences.defaultLowStockThreshold != nil
    }

    func threshold(for key: String) -> Double? {
        data.restockThresholds[key] ?? data.household?.preferences.defaultLowStockThreshold
    }

    func setThreshold(_ value: Double?, for key: String, name: String) {
        mutate { data in
            if let value {
                data.restockThresholds[key] = value
            } else if data.restockThresholds.removeValue(forKey: key) != nil {
                Self.tombstone("thresholds", [key], into: &data)
            }
        }
    }

    var lowStockLines: [LowStockLine] {
        let grouped = Dictionary(grouping: activeBatches, by: \.productKey)
        var lines: [LowStockLine] = []
        for (key, batches) in grouped {
            guard let threshold = threshold(for: key), let first = batches.first else { continue }
            // Sum only units that can be combined; fall back to the first unit's dimension.
            let unit = first.unit
            var total = 0.0
            var comparable = true
            for batch in batches {
                if let converted = MeasureUnit.convert(available(batch), from: batch.unit, to: unit) {
                    total += converted
                } else {
                    comparable = false
                }
            }
            guard comparable else { continue }
            if total <= threshold {
                lines.append(LowStockLine(key: key, name: first.productName, available: total,
                                          unit: unit, threshold: threshold))
            }
        }
        return lines.sorted { $0.available / max($0.threshold, 0.0001) < $1.available / max($1.threshold, 0.0001) }
    }

    // MARK: - Household

    func createHousehold(name: String, currency: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw AppError.validation("Household name is required.") }
        guard data.household == nil else { throw AppError.conflict("A household already exists on this device.") }
        var household = Household(name: clean, currencyCode: currency)
        household.zones = [
            StorageZone(name: "Pantry", kind: .pantry),
            StorageZone(name: "Fridge", kind: .fridge),
            StorageZone(name: "Freezer", kind: .freezer)
        ]
        mutate { data in
            data.household = household
            data.activity.insert(ActivityEntry(kind: .householdCreated,
                                               summary: "Household “\(clean)” created",
                                               detail: "3 default storage zones added"), at: 0)
        }
    }

    func updateHousehold(name: String, currency: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw AppError.validation("Household name is required.") }
        guard var household = data.household else { throw AppError.validation("No household yet.") }
        let changed = household.name != clean || household.currencyCode != currency
        household.name = clean
        household.currencyCode = currency
        mutate { data in
            data.household = household
            if changed {
                data.activity.insert(ActivityEntry(kind: .householdEdited,
                                                   summary: "Household details updated",
                                                   detail: "Name: \(clean) · Currency: \(currency)"), at: 0)
            }
        }
    }

    func updatePreferences(_ preferences: ShoppingPreferences) {
        guard var household = data.household else { return }
        household.preferences = preferences
        mutate { data in
            data.household = household
            data.settings.expiryWindowDays = preferences.expiryWindowDays
            data.activity.insert(ActivityEntry(kind: .householdEdited,
                                               summary: "Shopping preferences updated"), at: 0)
        }
    }

    func addMember(name: String, email: String?, role: Member.Role) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw AppError.validation("Member name is required.") }
        guard var household = data.household else { throw AppError.validation("Create the household first.") }
        let cleanEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let cleanEmail, !cleanEmail.isEmpty,
           household.members.contains(where: { $0.email?.lowercased() == cleanEmail && !$0.removed }) {
            throw AppError.conflict("Already a Member — this email is already in the household.")
        }
        if household.members.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame && !$0.removed }) {
            throw AppError.conflict("Already a Member — someone with this name is already in the household.")
        }
        household.members.append(Member(name: clean,
                                        email: (cleanEmail?.isEmpty == false) ? cleanEmail : nil,
                                        role: role))
        mutate { data in
            data.household = household
            data.activity.insert(ActivityEntry(kind: .memberAdded, summary: "Member “\(clean)” added"), at: 0)
        }
    }

    /// Removing a member keeps every action they recorded.
    func removeMember(_ id: UUID) {
        guard var household = data.household,
              let index = household.members.firstIndex(where: { $0.id == id }) else { return }
        let name = household.members[index].name
        household.members[index].removed = true
        mutate { data in
            data.household = household
            data.activity.insert(ActivityEntry(kind: .memberRemoved,
                                               summary: "Member “\(name)” removed",
                                               detail: "Their recorded actions were kept"), at: 0)
        }
    }

    func restoreMember(_ id: UUID) {
        guard var household = data.household,
              let index = household.members.firstIndex(where: { $0.id == id }) else { return }
        household.members[index].removed = false
        mutate { data in data.household = household }
    }

    func addZone(name: String, kind: StorageZone.Kind) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw AppError.validation("Zone name is required.") }
        guard var household = data.household else { throw AppError.validation("Create the household first.") }
        guard !household.zones.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame && !$0.archived })
        else { throw AppError.conflict("A zone with this name already exists.") }
        household.zones.append(StorageZone(name: clean, kind: kind))
        mutate { data in
            data.household = household
            data.activity.insert(ActivityEntry(kind: .zoneAdded, summary: "Storage zone “\(clean)” added"), at: 0)
        }
    }

    func renameZone(_ id: UUID, name: String, kind: StorageZone.Kind) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw AppError.validation("Zone name is required.") }
        guard var household = data.household,
              let index = household.zones.firstIndex(where: { $0.id == id }) else { return }
        household.zones[index].name = clean
        household.zones[index].kind = kind
        mutate { data in
            data.household = household
            data.activity.insert(ActivityEntry(kind: .zoneEdited, summary: "Storage zone renamed to “\(clean)”"), at: 0)
        }
    }

    func batchCount(inZone id: UUID) -> Int {
        activeBatches.filter { $0.zoneID == id }.count
    }

    func archiveZone(_ id: UUID, moveTo destination: UUID?) {
        guard var household = data.household,
              let index = household.zones.firstIndex(where: { $0.id == id }) else { return }
        let name = household.zones[index].name
        household.zones[index].archived = true
        let affected = activeBatches.filter { $0.zoneID == id }.count
        let destinationName = zoneName(destination) ?? "No zone"
        mutate { data in
            data.household = household
            for i in data.batches.indices where data.batches[i].zoneID == id {
                data.batches[i].zoneID = destination
            }
            data.activity.insert(ActivityEntry(
                kind: .zoneArchived,
                summary: "Storage zone “\(name)” archived",
                detail: affected == 0 ? "No items were stored there"
                                      : "\(affected) item(s) moved to \(destinationName)"
            ), at: 0)
        }
    }

    func restoreZone(_ id: UUID) {
        guard var household = data.household,
              let index = household.zones.firstIndex(where: { $0.id == id }) else { return }
        household.zones[index].archived = false
        mutate { data in data.household = household }
    }

    // MARK: - Batches

    @discardableResult
    func addBatch(_ batch: Batch) throws -> Batch {
        var new = batch
        new.productName = new.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.productName.isEmpty else { throw AppError.validation("Product name is required.") }
        guard new.quantity > 0 else { throw AppError.validation("Quantity must be greater than 0.") }
        if let price = new.price, price < 0 { throw AppError.validation("Price cannot be negative.") }
        new.remaining = new.quantity

        mutate { data in
            data.batches.insert(new, at: 0)
            data.activity.insert(ActivityEntry(
                kind: .batchCreated,
                summary: "Added \(Format.measure(new.quantity, new.unit)) of \(new.productName)",
                detail: new.origin.title,
                batchID: new.id,
                quantityDelta: new.quantity,
                unit: new.unit,
                amount: new.price
            ), at: 0)
            if let price = new.price {
                data.prices.insert(PriceEntry(productName: new.productName, brand: new.brand, store: new.store,
                                              price: price, quantity: new.quantity, unit: new.unit,
                                              date: new.purchaseDate ?? Date(), origin: .userPurchase,
                                              batchID: new.id), at: 0)
            }
        }
        return new
    }

    func updateBatch(_ batch: Batch) throws {
        guard let index = data.batches.firstIndex(where: { $0.id == batch.id }) else { return }
        var updated = batch
        updated.productName = updated.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.productName.isEmpty else { throw AppError.validation("Product name is required.") }
        guard updated.quantity > 0 else { throw AppError.validation("Quantity must be greater than 0.") }
        if let price = updated.price, price < 0 { throw AppError.validation("Price cannot be negative.") }
        let reservedNow = reserved(batch.id)
        guard updated.remaining >= reservedNow else {
            throw AppError.conflict("\(Format.measure(reservedNow, updated.unit)) is reserved for planned meals. Release the reservation first.")
        }
        let previous = data.batches[index]
        var changes: [String] = []
        if previous.productName != updated.productName { changes.append("name") }
        if previous.bestBefore != updated.bestBefore {
            changes.append("date → \(updated.bestBefore.map(DateFormat.day) ?? "not set")")
        }
        if previous.zoneID != updated.zoneID { changes.append("zone") }
        if previous.price != updated.price { changes.append("price") }
        if previous.unit != updated.unit { changes.append("unit") }

        mutate { data in
            data.batches[index] = updated
            data.activity.insert(ActivityEntry(
                kind: .batchEdited,
                summary: "Edited \(updated.productName)",
                detail: changes.isEmpty ? "No field changed" : "Changed: " + changes.joined(separator: ", "),
                batchID: updated.id
            ), at: 0)
        }
    }

    /// The only path that changes `remaining`. A reason is always required.
    func adjust(batchID: UUID, delta: Double, reason: AdjustReason, note: String? = nil) throws {
        guard let index = data.batches.firstIndex(where: { $0.id == batchID }) else { return }
        let batch = data.batches[index]
        let next = batch.remaining + delta
        guard next >= -0.0001 else {
            throw AppError.validation("Only \(Format.measure(batch.remaining, batch.unit)) is on hand — the result cannot be negative.")
        }
        let reservedNow = reserved(batchID)
        if next < reservedNow - 0.0001 {
            throw AppError.conflict("\(Format.measure(reservedNow, batch.unit)) is reserved for planned meals. Release a reservation before removing this much.")
        }
        let priceShare = batch.price.map { $0 / max(batch.quantity, 0.0001) * abs(delta) }

        mutate { data in
            data.batches[index].remaining = max(0, next)
            let verb = delta < 0 ? "Removed" : "Added back"
            data.activity.insert(ActivityEntry(
                kind: .batchAdjusted,
                summary: "\(verb) \(Format.measure(abs(delta), batch.unit)) · \(batch.productName)",
                detail: note?.isEmpty == false ? "\(reason.title) — \(note!)" : reason.title,
                batchID: batchID,
                quantityDelta: delta,
                unit: batch.unit,
                reason: reason,
                amount: priceShare
            ), at: 0)
        }
    }

    func markOpened(batchID: UUID, opened: Bool = true) {
        guard let index = data.batches.firstIndex(where: { $0.id == batchID }) else { return }
        let name = data.batches[index].productName
        mutate { data in
            data.batches[index].opened = opened
            data.batches[index].openedAt = opened ? Date() : nil
            data.activity.insert(ActivityEntry(
                kind: .batchOpened,
                summary: opened ? "Marked opened · \(name)" : "Marked unopened · \(name)",
                detail: opened ? "Opened on \(DateFormat.day(Date()))" : nil,
                batchID: batchID
            ), at: 0)
        }
    }

    func move(batchID: UUID, to zoneID: UUID?) {
        guard let index = data.batches.firstIndex(where: { $0.id == batchID }) else { return }
        let batch = data.batches[index]
        let from = zoneName(batch.zoneID) ?? "No zone"
        let to = zoneName(zoneID) ?? "No zone"
        mutate { data in
            data.batches[index].zoneID = zoneID
            data.activity.insert(ActivityEntry(
                kind: .batchMoved,
                summary: "Moved \(batch.productName)",
                detail: "\(from) → \(to)",
                batchID: batchID
            ), at: 0)
        }
    }

    func setBestBefore(batchID: UUID, date: Date?, note: String) {
        guard let index = data.batches.firstIndex(where: { $0.id == batchID }) else { return }
        let batch = data.batches[index]
        mutate { data in
            data.batches[index].bestBefore = date
            data.activity.insert(ActivityEntry(
                kind: .batchEdited,
                summary: "Date changed · \(batch.productName)",
                detail: "\(batch.bestBefore.map(DateFormat.day) ?? "not set") → \(date.map(DateFormat.day) ?? "not set") — \(note)",
                batchID: batchID
            ), at: 0)
        }
    }

    func archiveBatch(_ id: UUID, archived: Bool) {
        guard let index = data.batches.firstIndex(where: { $0.id == id }) else { return }
        let name = data.batches[index].productName
        mutate { data in
            data.batches[index].archived = archived
            data.activity.insert(ActivityEntry(
                kind: archived ? .batchArchived : .batchRestored,
                summary: archived ? "Archived \(name)" : "Restored \(name)",
                detail: archived ? "Hidden from counts — can be restored" : "Counted again",
                batchID: id
            ), at: 0)
        }
    }

    /// Everything the user must know before a batch disappears.
    func deletionImpact(batchID: UUID) -> DeletionImpact {
        var lines: [String] = []
        let linked = reservations(for: batchID)
        let mealNames = Set(linked.compactMap { meal($0.mealID)?.name })
        if !linked.isEmpty {
            lines.append("\(linked.count) meal reservation(s) will be released: \(mealNames.sorted().joined(separator: ", "))")
        }
        let history = data.activity.filter { $0.batchID == batchID }.count
        if history > 0 { lines.append("\(history) history record(s) will be deleted with it") }
        let prices = data.prices.filter { $0.batchID == batchID }.count
        if prices > 0 { lines.append("\(prices) price record(s) will be removed from Price History") }
        let matches = data.recallMatches.filter { $0.batchID == batchID }.count
        if matches > 0 { lines.append("\(matches) recall check(s) linked to this batch will be removed") }
        if lines.isEmpty { lines.append("Nothing else references this batch") }
        return DeletionImpact(lines: lines, blocking: false)
    }

    func deleteBatch(_ id: UUID) {
        guard let batch = batch(id) else { return }
        let reservationIDs = reservations(for: id).map { $0.id.uuidString }
        mutate { data in
            Self.tombstone("batches", [id.uuidString], into: &data)
            Self.tombstone("reservations", reservationIDs, into: &data)
            data.reservations.removeAll { $0.batchID == id }
            data.prices.removeAll { $0.batchID == id }
            data.recallMatches.removeAll { $0.batchID == id }
            data.activity.removeAll { $0.batchID == id }
            data.batches.removeAll { $0.id == id }
            data.activity.insert(ActivityEntry(
                kind: .batchDeleted,
                summary: "Deleted \(batch.productName)",
                detail: "Batch and its linked records were removed"
            ), at: 0)
        }
        persistence.deletePhoto(batch.photoFilename)
    }

    // MARK: - Meals

    @discardableResult
    func saveMeal(_ meal: Meal) throws -> Meal {
        var new = meal
        new.name = new.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.name.isEmpty else { throw AppError.validation("Meal name is required.") }
        guard new.servings > 0 else { throw AppError.validation("Servings must be at least 1.") }
        guard !new.ingredients.isEmpty else { throw AppError.validation("Add at least one ingredient.") }
        guard new.ingredients.allSatisfy({ $0.quantityPerServing > 0 }) else {
            throw AppError.validation("Every ingredient needs a quantity greater than 0.")
        }

        if let index = data.meals.firstIndex(where: { $0.id == new.id }) {
            mutate { data in
                data.meals[index] = new
                data.activity.insert(ActivityEntry(kind: .mealEdited,
                                                   summary: "Meal “\(new.name)” updated",
                                                   detail: "\(new.ingredients.count) ingredient(s) · \(new.servings) serving(s)",
                                                   mealID: new.id), at: 0)
            }
        } else {
            mutate { data in
                data.meals.insert(new, at: 0)
                data.activity.insert(ActivityEntry(kind: .mealCreated,
                                                   summary: "Meal “\(new.name)” created",
                                                   detail: "\(new.ingredients.count) ingredient(s) · \(new.servings) serving(s)",
                                                   mealID: new.id), at: 0)
            }
        }
        return new
    }

    /// Allocates stock to a meal without changing anything.
    func stockCheck(for meal: Meal, ignoringReservationsOf mealID: UUID? = nil) -> [StockCheckLine] {
        meal.ingredients.map { ingredient in
            let need = meal.need(for: ingredient)
            let candidates = activeBatches
                .filter { $0.productKey == ingredient.productKey }
                .sorted {
                    ($0.bestBefore ?? .distantFuture, $0.createdAt) < ($1.bestBefore ?? .distantFuture, $1.createdAt)
                }
            let compatible = candidates.filter { MeasureUnit.compatible($0.unit, ingredient.unit) }
            let incompatible = !candidates.isEmpty && compatible.isEmpty

            var remainingNeed = need
            var allocations: [(batchID: UUID, quantity: Double)] = []
            for batch in compatible where remainingNeed > 0.0001 {
                var freeInBatchUnit = batch.remaining - reserved(batch.id)
                if let ignore = mealID {
                    freeInBatchUnit += data.reservations
                        .filter { $0.batchID == batch.id && $0.mealID == ignore }
                        .reduce(0) { $0 + $1.quantity }
                }
                guard freeInBatchUnit > 0.0001,
                      let freeInIngredientUnit = MeasureUnit.convert(freeInBatchUnit, from: batch.unit, to: ingredient.unit)
                else { continue }
                let take = min(remainingNeed, freeInIngredientUnit)
                guard let takeInBatchUnit = MeasureUnit.convert(take, from: ingredient.unit, to: batch.unit) else { continue }
                allocations.append((batch.id, takeInBatchUnit))
                remainingNeed -= take
            }

            return StockCheckLine(ingredient: ingredient,
                                  need: need,
                                  covered: need - max(0, remainingNeed),
                                  incompatibleUnits: incompatible,
                                  allocations: allocations)
        }
    }

    @discardableResult
    func reserveIngredients(mealID: UUID) -> [StockCheckLine] {
        guard let meal = meal(mealID), meal.status == .planned else { return [] }
        let lines = stockCheck(for: meal, ignoringReservationsOf: mealID)
        let replaced = data.reservations.filter { $0.mealID == mealID }.map { $0.id.uuidString }
        mutate { data in
            Self.tombstone("reservations", replaced, into: &data)
            data.reservations.removeAll { $0.mealID == mealID }
            for line in lines {
                for allocation in line.allocations {
                    data.reservations.append(Reservation(mealID: mealID,
                                                         ingredientID: line.ingredient.id,
                                                         batchID: allocation.batchID,
                                                         quantity: allocation.quantity))
                }
            }
            let coveredCount = lines.filter(\.isCovered).count
            data.activity.insert(ActivityEntry(
                kind: .mealReserved,
                summary: "Reserved stock for “\(meal.name)”",
                detail: "\(coveredCount) of \(lines.count) ingredient(s) fully covered · on-hand unchanged",
                mealID: mealID
            ), at: 0)
        }
        return lines
    }

    func releaseReservations(mealID: UUID, logged: Bool = true) {
        guard !data.reservations.filter({ $0.mealID == mealID }).isEmpty else { return }
        let name = meal(mealID)?.name ?? "meal"
        let released = data.reservations.filter { $0.mealID == mealID }.map { $0.id.uuidString }
        mutate { data in
            Self.tombstone("reservations", released, into: &data)
            data.reservations.removeAll { $0.mealID == mealID }
            if logged {
                data.activity.insert(ActivityEntry(kind: .mealReleased,
                                                   summary: "Released reserved stock for “\(name)”",
                                                   detail: "Available quantity went back up",
                                                   mealID: mealID), at: 0)
            }
        }
    }

    /// Turns reservations into real consumption.
    func cookMeal(mealID: UUID) throws {
        guard let index = data.meals.firstIndex(where: { $0.id == mealID }) else { return }
        let meal = data.meals[index]
        let linked = data.reservations.filter { $0.mealID == mealID }
        guard !linked.isEmpty else {
            throw AppError.validation("Nothing is reserved for this meal yet. Tap Reserve Ingredients first.")
        }
        for reservation in linked {
            guard let batchIndex = data.batches.firstIndex(where: { $0.id == reservation.batchID }) else { continue }
            let batch = data.batches[batchIndex]
            let used = min(reservation.quantity, batch.remaining)
            let priceShare = batch.price.map { $0 / max(batch.quantity, 0.0001) * used }
            mutate { data in
                data.batches[batchIndex].remaining = max(0, batch.remaining - used)
                data.activity.insert(ActivityEntry(
                    kind: .batchAdjusted,
                    summary: "Used \(Format.measure(used, batch.unit)) · \(batch.productName)",
                    detail: "Cooked “\(meal.name)”",
                    batchID: batch.id,
                    mealID: mealID,
                    quantityDelta: -used,
                    unit: batch.unit,
                    reason: .used,
                    amount: priceShare
                ), at: 0)
            }
        }
        mutate { data in
            Self.tombstone("reservations", linked.map { $0.id.uuidString }, into: &data)
            data.reservations.removeAll { $0.mealID == mealID }
            data.meals[index].status = .cooked
            data.meals[index].cookedAt = Date()
            data.activity.insert(ActivityEntry(kind: .mealCooked,
                                               summary: "Cooked “\(meal.name)”",
                                               detail: "\(linked.count) batch(es) reduced",
                                               mealID: mealID), at: 0)
        }
    }

    func cancelMeal(mealID: UUID) {
        guard let index = data.meals.firstIndex(where: { $0.id == mealID }) else { return }
        let name = data.meals[index].name
        releaseReservations(mealID: mealID, logged: false)
        mutate { data in
            data.meals[index].status = .cancelled
            data.activity.insert(ActivityEntry(kind: .mealCancelled,
                                               summary: "Cancelled “\(name)”",
                                               detail: "Reserved stock returned to Available",
                                               mealID: mealID), at: 0)
        }
    }

    func deleteMeal(mealID: UUID) {
        guard let meal = meal(mealID) else { return }
        let reservationIDs = data.reservations.filter { $0.mealID == mealID }.map { $0.id.uuidString }
        mutate { data in
            Self.tombstone("meals", [mealID.uuidString], into: &data)
            Self.tombstone("reservations", reservationIDs, into: &data)
            data.reservations.removeAll { $0.mealID == mealID }
            data.meals.removeAll { $0.id == mealID }
            data.activity.insert(ActivityEntry(kind: .mealDeleted,
                                               summary: "Deleted “\(meal.name)”",
                                               detail: "Any reserved stock was released"), at: 0)
        }
    }

    func mealDeletionImpact(mealID: UUID) -> DeletionImpact {
        var lines: [String] = []
        let linked = data.reservations.filter { $0.mealID == mealID }
        if linked.isEmpty { lines.append("No stock is reserved for this meal") }
        else { lines.append("\(linked.count) reservation(s) will be released back to Available") }
        let shoppingLines = data.shopping.filter {
            if case .mealShortfall(let id, _) = $0.source { return id == mealID && $0.status == .needed }
            return false
        }
        if !shoppingLines.isEmpty {
            lines.append("\(shoppingLines.count) shopping item(s) created from this meal stay on the list")
        }
        return DeletionImpact(lines: lines, blocking: false)
    }

    // MARK: - Shopping

    @discardableResult
    func addShoppingItem(_ item: ShoppingItem) throws -> ShoppingItem {
        var new = item
        new.name = new.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.name.isEmpty else { throw AppError.validation("Item name is required.") }
        guard new.quantity > 0 else { throw AppError.validation("Quantity must be greater than 0.") }
        if let target = new.targetPrice, target < 0 { throw AppError.validation("Target price cannot be negative.") }
        mutate { data in
            data.shopping.insert(new, at: 0)
            data.activity.insert(ActivityEntry(kind: .shoppingAdded,
                                               summary: "Added \(new.name) to Shopping Plan",
                                               detail: new.source.title,
                                               shoppingItemID: new.id), at: 0)
        }
        return new
    }

    func updateShoppingItem(_ item: ShoppingItem) throws {
        guard let index = data.shopping.firstIndex(where: { $0.id == item.id }) else { return }
        guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.validation("Item name is required.")
        }
        guard item.quantity > 0 else { throw AppError.validation("Quantity must be greater than 0.") }
        mutate { data in data.shopping[index] = item }
    }

    /// Adds only the shortfalls the user confirmed. Existing needed lines for the
    /// same meal + ingredient are updated instead of duplicated.
    @discardableResult
    func addMissingToShopping(meal: Meal, lines: [StockCheckLine]) -> Int {
        var added = 0
        mutate { data in
            for line in lines where line.missing > 0.0001 || line.incompatibleUnits {
                let quantity = line.incompatibleUnits ? line.need : line.missing
                let existing = data.shopping.firstIndex {
                    if case .mealShortfall(let id, _) = $0.source {
                        return id == meal.id && $0.productKey == line.ingredient.productKey && $0.status == .needed
                    }
                    return false
                }
                if let existing {
                    data.shopping[existing].quantity = quantity
                    data.shopping[existing].unit = line.ingredient.unit
                } else {
                    let item = ShoppingItem(name: line.ingredient.name,
                                            quantity: quantity,
                                            unit: line.ingredient.unit,
                                            store: data.household?.preferences.defaultStore.isEmpty == false
                                                ? data.household?.preferences.defaultStore : nil,
                                            source: .mealShortfall(mealID: meal.id, mealName: meal.name))
                    data.shopping.insert(item, at: 0)
                    added += 1
                }
            }
            if added > 0 {
                data.activity.insert(ActivityEntry(kind: .shoppingAdded,
                                                   summary: "Added \(added) missing item(s) from “\(meal.name)”",
                                                   detail: "Confirmed by you in Meal Builder",
                                                   mealID: meal.id), at: 0)
            }
        }
        return added
    }

    struct PurchaseDetails {
        var quantity: Double
        var unit: MeasureUnit
        var price: Double?
        var store: String?
        var bestBefore: Date?
        var zoneID: UUID?
    }

    /// Idempotent: an item that already created a batch is never doubled.
    @discardableResult
    func markPurchased(itemID: UUID, details: PurchaseDetails) throws -> Batch? {
        guard let index = data.shopping.firstIndex(where: { $0.id == itemID }) else { return nil }
        let item = data.shopping[index]
        if item.createdBatchID != nil { return nil }
        guard details.quantity > 0 else { throw AppError.validation("Quantity must be greater than 0.") }
        if let price = details.price, price < 0 { throw AppError.validation("Price cannot be negative.") }

        let batch = Batch(productName: item.name,
                          quantity: details.quantity,
                          remaining: details.quantity,
                          unit: details.unit,
                          purchaseDate: Date(),
                          bestBefore: details.bestBefore,
                          zoneID: details.zoneID,
                          price: details.price,
                          store: details.store,
                          origin: .shopping)
        let created = try addBatch(batch)

        mutate { data in
            data.shopping[index].status = .purchased
            data.shopping[index].purchasedAt = Date()
            data.shopping[index].actualQuantity = details.quantity
            data.shopping[index].actualPrice = details.price
            data.shopping[index].store = details.store ?? data.shopping[index].store
            data.shopping[index].createdBatchID = created.id
            data.activity.insert(ActivityEntry(
                kind: .shoppingPurchased,
                summary: "Purchased \(Format.measure(details.quantity, details.unit)) of \(item.name)",
                detail: "New batch added to Inventory",
                batchID: created.id,
                shoppingItemID: itemID,
                amount: details.price
            ), at: 0)
        }
        return created
    }

    func undoPurchase(itemID: UUID) throws {
        guard let index = data.shopping.firstIndex(where: { $0.id == itemID }),
              let batchID = data.shopping[index].createdBatchID else { return }
        let name = data.shopping[index].name
        if let batch = batch(batchID) {
            if batch.remaining < batch.quantity - 0.0001 {
                throw AppError.conflict("Some of this batch has already been used. Adjust the batch in Inventory instead of undoing the purchase.")
            }
            if !reservations(for: batchID).isEmpty {
                throw AppError.conflict("This batch is reserved for a planned meal. Release the reservation first.")
            }
            deleteBatch(batchID)
        }
        mutate { data in
            data.shopping[index].status = .needed
            data.shopping[index].purchasedAt = nil
            data.shopping[index].actualPrice = nil
            data.shopping[index].actualQuantity = nil
            data.shopping[index].createdBatchID = nil
            data.activity.insert(ActivityEntry(kind: .shoppingUndone,
                                               summary: "Undid purchase of \(name)",
                                               detail: "The created batch was removed",
                                               shoppingItemID: itemID), at: 0)
        }
    }

    func excludeShoppingItem(itemID: UUID, reason: String) throws {
        let clean = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw AppError.validation("A reason is required to exclude an automatic item.") }
        guard let index = data.shopping.firstIndex(where: { $0.id == itemID }) else { return }
        let name = data.shopping[index].name
        mutate { data in
            data.shopping[index].status = .excluded
            data.shopping[index].excludeReason = clean
            data.activity.insert(ActivityEntry(kind: .shoppingExcluded,
                                               summary: "Excluded \(name)",
                                               detail: clean,
                                               shoppingItemID: itemID), at: 0)
        }
    }

    func restoreShoppingItem(itemID: UUID) {
        guard let index = data.shopping.firstIndex(where: { $0.id == itemID }) else { return }
        mutate { data in
            data.shopping[index].status = .needed
            data.shopping[index].excludeReason = nil
        }
    }

    func deleteShoppingItem(itemID: UUID) {
        guard let item = shoppingItem(itemID) else { return }
        mutate { data in
            Self.tombstone("shopping-items", [itemID.uuidString], into: &data)
            data.shopping.removeAll { $0.id == itemID }
            data.activity.insert(ActivityEntry(kind: .shoppingDeleted,
                                               summary: "Removed \(item.name) from Shopping Plan"), at: 0)
        }
    }

    var neededShopping: [ShoppingItem] { data.shopping.filter { $0.status == .needed } }

    /// Sum of target prices where they exist — the rest is reported as unknown.
    var shoppingEstimate: (known: Double, withPrice: Int, total: Int) {
        let needed = neededShopping
        let priced = needed.compactMap { item -> Double? in
            guard let target = item.targetPrice else { return nil }
            return target
        }
        return (priced.reduce(0, +), priced.count, needed.count)
    }

    // MARK: - Prices

    func priceEntries(for key: String) -> [PriceEntry] {
        data.prices.filter { $0.productKey == key }.sorted { $0.date > $1.date }
    }

    func bestRecentPrice(for key: String, within days: Int = 90) -> PriceEntry? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return priceEntries(for: key)
            .filter { $0.date >= cutoff && $0.pricePerBaseUnit != nil }
            .min { ($0.pricePerBaseUnit ?? .infinity) < ($1.pricePerBaseUnit ?? .infinity) }
    }

    // MARK: - Recalls

    func matches(for alertID: String) -> [RecallMatch] {
        data.recallMatches.filter { $0.alertID == alertID }
    }

    func matches(forBatch batchID: UUID) -> [RecallMatch] {
        data.recallMatches.filter { $0.batchID == batchID }
    }

    var unconfirmedRecallMatches: [RecallMatch] {
        data.recallMatches.filter { $0.decision == .unconfirmed && !isArchived(alertID: $0.alertID) }
    }

    func isArchived(alertID: String) -> Bool {
        data.archivedAlerts.contains { $0.alertID == alertID }
    }

    var visibleAlerts: [RecallAlert] {
        data.recallAlerts
            .filter { !isArchived(alertID: $0.id) }
            .sorted { ($0.reportedAt ?? .distantPast) > ($1.reportedAt ?? .distantPast) }
    }

    /// Stores a freshly fetched feed and re-runs local matching against user batches.
    func ingestAlerts(_ alerts: [RecallAlert]) {
        mutate { data in
            var merged = data.recallAlerts
            for alert in alerts {
                if let index = merged.firstIndex(where: { $0.id == alert.id }) { merged[index] = alert }
                else { merged.append(alert) }
            }
            data.recallAlerts = merged
            data.recallLastCheckedAt = Date()
        }
        rebuildRecallMatches()
        let needsCheck = unconfirmedRecallMatches.count
        mutate { data in
            data.activity.insert(ActivityEntry(
                kind: .recallChecked,
                summary: "Checked official recall notices",
                detail: "\(alerts.count) notice(s) received · \(needsCheck) need your check"
            ), at: 0)
        }
    }

    func rebuildRecallMatches() {
        var produced: [RecallMatch] = []
        for alert in data.recallAlerts where !isArchived(alertID: alert.id) {
            for batch in data.batches where !batch.archived {
                guard let reason = matchReason(alert: alert, batch: batch) else { continue }
                if let existing = data.recallMatches.first(where: { $0.alertID == alert.id && $0.batchID == batch.id }) {
                    produced.append(existing)
                } else {
                    produced.append(RecallMatch(alertID: alert.id, batchID: batch.id, reason: reason))
                }
            }
        }
        // Keep decisions the user already made, even if the batch stopped matching.
        let decided = data.recallMatches.filter { $0.decision != .unconfirmed }
        var result = produced
        for match in decided where !result.contains(where: { $0.alertID == match.alertID && $0.batchID == match.batchID }) {
            result.append(match)
        }
        mutate { data in data.recallMatches = result }
    }

    /// Local, explainable matching. The app never claims a match — it only
    /// explains why a notice might involve one of the user's batches.
    private func matchReason(alert: RecallAlert, batch: Batch) -> String? {
        let haystack = (alert.productDescription + " " + (alert.firmName ?? "") + " " + alert.title + " " + alert.codes.joined(separator: " "))
            .lowercased()

        if let barcode = batch.barcode?.trimmingCharacters(in: .whitespaces), barcode.count >= 8,
           haystack.contains(barcode.lowercased()) {
            return "Barcode \(barcode) appears in the notice"
        }
        if let code = batch.batchCode?.trimmingCharacters(in: .whitespaces), code.count >= 3,
           haystack.contains(code.lowercased()) {
            return "Batch code \(code) appears in the notice"
        }
        if let brand = batch.brand?.trimmingCharacters(in: .whitespaces), brand.count >= 3,
           haystack.contains(brand.lowercased()) {
            return "Brand “\(brand)” appears in the notice"
        }
        let words = batch.productName.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
        if let word = words.first(where: { haystack.contains($0) }) {
            return "Product word “\(word)” appears in the notice"
        }
        return nil
    }

    func setRecallDecision(alertID: String, batchID: UUID, decision: RecallMatch.Decision) {
        guard let index = data.recallMatches.firstIndex(where: { $0.alertID == alertID && $0.batchID == batchID }) else { return }
        let name = batch(batchID)?.productName ?? "item"
        mutate { data in
            data.recallMatches[index].decision = decision
            data.recallMatches[index].decidedAt = Date()
            data.activity.insert(ActivityEntry(
                kind: .recallDecision,
                summary: "\(decision.title) · \(name)",
                detail: "Notice \(alertID)",
                batchID: batchID,
                alertID: alertID
            ), at: 0)
        }
    }

    func archiveAlert(alertID: String, reason: String) throws {
        let clean = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw AppError.validation("Choose a reason before archiving this alert.") }
        mutate { data in
            data.archivedAlerts.append(ArchivedAlert(alertID: alertID, reason: clean))
            data.activity.insert(ActivityEntry(kind: .recallArchived,
                                               summary: "Archived recall notice",
                                               detail: "\(alertID) — \(clean)",
                                               alertID: alertID), at: 0)
        }
    }

    func restoreAlert(alertID: String) {
        mutate { data in
            Self.tombstone("archived-alerts", [alertID], into: &data)
            data.archivedAlerts.removeAll { $0.alertID == alertID }
        }
        rebuildRecallMatches()
    }

    // MARK: - Home summary

    var nextAction: NextAction? {
        if !hasHousehold {
            return NextAction(title: "Create your household",
                              detail: "Storage zones and currency come from it.",
                              symbol: "house.fill", route: .householdSetup)
        }
        if data.batches.isEmpty {
            return NextAction(title: "Add your first product",
                              detail: "Scan a barcode or type it in — everything else builds on real batches.",
                              symbol: "barcode.viewfinder", route: .addProduct)
        }
        if let match = unconfirmedRecallMatches.first, let batch = batch(match.batchID) {
            return NextAction(title: "Check a recall notice",
                              detail: "A notice may involve your \(batch.productName). Only you can confirm the batch.",
                              symbol: "exclamationmark.shield.fill", route: .recalls)
        }
        let overdue = expiringSoon.filter {
            if case .expired = expiryState($0) { return true }
            return false
        }
        if let first = overdue.first {
            return NextAction(title: "Review \(overdue.count) item(s) past your date",
                              detail: "\(first.productName) — dated \(first.bestBefore.map(DateFormat.day) ?? "unknown").",
                              symbol: "clock.badge.exclamationmark.fill", route: .expiryReview)
        }
        if let soon = expiringSoon.first {
            return NextAction(title: "Use \(soon.productName) soon",
                              detail: "Your date is \(DateFormat.relativeDays(soon.bestBefore ?? Date())).",
                              symbol: "timer", route: .expiryReview)
        }
        let plannedSoon = data.meals.filter {
            $0.status == .planned && ($0.date.map { DateFormat.daysBetween(Date(), $0) <= 2 } ?? false)
        }
        for meal in plannedSoon {
            let lines = stockCheck(for: meal, ignoringReservationsOf: meal.id)
            if lines.contains(where: { !$0.isCovered }) {
                return NextAction(title: "“\(meal.name)” is missing ingredients",
                                  detail: "Check stock and confirm what to buy.",
                                  symbol: "fork.knife", route: .meal(meal.id))
            }
        }
        if !neededShopping.isEmpty {
            return NextAction(title: "\(neededShopping.count) item(s) to buy",
                              detail: "Mark them purchased to add them to Inventory.",
                              symbol: "cart.fill", route: .shopping)
        }
        if data.meals.filter({ $0.status == .planned }).isEmpty {
            return NextAction(title: "Plan a meal from what you have",
                              detail: "Reserving ingredients keeps Available honest.",
                              symbol: "sparkles", route: .mealBuilder)
        }
        return nil
    }

    var plannedMeals: [Meal] {
        data.meals.filter { $0.status == .planned && !$0.archived }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    var recipes: [Meal] {
        data.meals.filter { !$0.archived }
    }

    // MARK: - History

    func history(batchID: UUID) -> [ActivityEntry] {
        data.activity.filter { $0.batchID == batchID }.sorted { $0.date > $1.date }
    }

    func history(mealID: UUID) -> [ActivityEntry] {
        data.activity.filter { $0.mealID == mealID }.sorted { $0.date > $1.date }
    }

    var firstRecordDate: Date? {
        data.activity.map(\.date).min()
    }

    var recordedDays: Int {
        guard let first = firstRecordDate else { return 0 }
        return max(0, DateFormat.daysBetween(first, Date()))
    }

    // MARK: - Data management

    func replaceAll(with imported: AppData) {
        persistence.snapshotBeforeImport()
        var incoming = imported
        incoming.activity.insert(ActivityEntry(kind: .dataImported,
                                               summary: "Backup imported",
                                               detail: "\(imported.batches.count) batch(es) · \(imported.meals.count) meal(s) · \(imported.shopping.count) shopping line(s)"), at: 0)
        data = incoming
        saveNow()
    }

    func deleteHousehold() {
        let counts = "\(data.batches.count) batch(es), \(data.meals.count) meal(s), \(data.shopping.count) shopping line(s)"
        persistence.eraseEverything()
        data = AppData()
        data.onboardingCompleted = true
        data.activity = [ActivityEntry(kind: .householdEdited,
                                       summary: "Household deleted",
                                       detail: "Removed \(counts)")]
        saveNow()
    }

    func eraseEverything() {
        persistence.eraseEverything()
        data = AppData()
        saveNow()
    }

    func completeOnboarding() {
        mutate { data in data.onboardingCompleted = true }
        saveNow()
    }
}
