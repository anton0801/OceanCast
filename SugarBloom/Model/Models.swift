//
//  Models.swift
//  Ocean Cast
//
//  The domain. Every screen reads and writes these records — there are no
//  parallel copies of the same number anywhere in the app.
//

import Foundation

// MARK: - Keys

enum ProductKey {
    /// Normalised product identity used to group batches, prices and shortfalls.
    static func make(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

// MARK: - Household

struct StorageZone: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case pantry, fridge, freezer, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .pantry: return "Pantry"
            case .fridge: return "Fridge"
            case .freezer: return "Freezer"
            case .other: return "Other"
            }
        }
        var symbol: String {
            switch self {
            case .pantry: return "cabinet.fill"
            case .fridge: return "refrigerator.fill"
            case .freezer: return "snowflake"
            case .other: return "shippingbox.fill"
            }
        }
    }

    var id: UUID = UUID()
    var name: String
    var kind: Kind
    var archived: Bool = false
    var createdAt: Date = Date()
}

struct Member: Codable, Identifiable, Hashable {
    enum Role: String, Codable, CaseIterable, Identifiable {
        case owner, adult, helper
        var id: String { rawValue }
        var title: String {
            switch self {
            case .owner: return "Owner"
            case .adult: return "Adult"
            case .helper: return "Helper"
            }
        }
    }

    var id: UUID = UUID()
    var name: String
    var email: String?
    var role: Role = .adult
    /// Removed members keep their history; the record is only marked inactive.
    var removed: Bool = false
    var joinedAt: Date = Date()
}

struct ShoppingPreferences: Codable, Hashable {
    var defaultStore: String = ""
    var groupByStore: Bool = true
    /// nil means the user has not set a threshold — low stock stays uncomputed
    /// rather than being reported as zero.
    var defaultLowStockThreshold: Double?
    var expiryWindowDays: Int = 3
}

struct Household: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var currencyCode: String = "USD"
    var members: [Member] = []
    var zones: [StorageZone] = []
    var preferences: ShoppingPreferences = ShoppingPreferences()
    var createdAt: Date = Date()

    var activeMembers: [Member] { members.filter { !$0.removed } }
    var activeZones: [StorageZone] { zones.filter { !$0.archived } }
}

// MARK: - Inventory

enum BatchOrigin: String, Codable {
    case manual, scan, receipt, shopping

    var title: String {
        switch self {
        case .manual: return "Added manually"
        case .scan: return "Added by barcode scan"
        case .receipt: return "Imported from receipt"
        case .shopping: return "Confirmed purchase"
        }
    }

    var symbol: String {
        switch self {
        case .manual: return "square.and.pencil"
        case .scan: return "barcode.viewfinder"
        case .receipt: return "doc.text.viewfinder"
        case .shopping: return "cart.fill"
        }
    }
}

/// A reference hint from an external catalogue. Kept strictly separate from the
/// user's own dates so a suggestion is never presented as a fact.
struct ReferenceHint: Codable, Hashable {
    var sourceName: String
    var sourceURL: String?
    var fetchedAt: Date
    var shelfLifeDaysHint: Int?
    var categories: String?
    var quantityText: String?
}

struct Batch: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var productName: String
    var brand: String?
    var barcode: String?
    var batchCode: String?

    var quantity: Double          // as purchased
    var remaining: Double         // on hand
    var unit: MeasureUnit

    var purchaseDate: Date?
    /// User-entered date. The app never invents this.
    var bestBefore: Date?
    var reference: ReferenceHint?

    var zoneID: UUID?
    var price: Double?            // total paid for `quantity`
    var store: String?

    var opened: Bool = false
    var openedAt: Date?
    var archived: Bool = false
    var origin: BatchOrigin = .manual
    var photoFilename: String?
    var notes: String?
    var createdAt: Date = Date()

    var productKey: String { ProductKey.make(productName) }

    var isDepleted: Bool { remaining <= 0.0001 }

    var displayTitle: String {
        if let brand, !brand.isEmpty { return "\(productName) · \(brand)" }
        return productName
    }
}

enum AdjustReason: String, Codable, CaseIterable, Identifiable {
    case used, spilled, corrected, discarded
    var id: String { rawValue }
    var title: String {
        switch self {
        case .used: return "Used"
        case .spilled: return "Spilled"
        case .corrected: return "Corrected"
        case .discarded: return "Discarded"
        }
    }
    var symbol: String {
        switch self {
        case .used: return "fork.knife"
        case .spilled: return "drop.fill"
        case .corrected: return "pencil.and.outline"
        case .discarded: return "trash.fill"
        }
    }
    /// Counted as waste in Insights.
    var isWaste: Bool { self == .spilled || self == .discarded }
}

// MARK: - Meals

struct MealIngredient: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var quantityPerServing: Double
    var unit: MeasureUnit

    var productKey: String { ProductKey.make(name) }
}

struct Meal: Codable, Identifiable, Hashable {
    enum Status: String, Codable {
        case recipe     // saved idea, no date, never reserves stock
        case planned
        case cooked
        case cancelled

        var title: String {
            switch self {
            case .recipe: return "Saved recipe"
            case .planned: return "Planned"
            case .cooked: return "Cooked"
            case .cancelled: return "Cancelled"
            }
        }
    }

    var id: UUID = UUID()
    var name: String
    var servings: Int = 2
    var date: Date?
    var prepMinutes: Int?
    var notes: String?
    var ingredients: [MealIngredient] = []
    var status: Status = .planned
    var archived: Bool = false
    var createdAt: Date = Date()
    var cookedAt: Date?

    func need(for ingredient: MealIngredient) -> Double {
        ingredient.quantityPerServing * Double(max(servings, 0))
    }
}

struct Reservation: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var mealID: UUID
    var ingredientID: UUID
    var batchID: UUID
    var quantity: Double        // in the batch's own unit
    var createdAt: Date = Date()
}

/// What `Check Stock` produced for one ingredient.
struct StockCheckLine: Identifiable, Hashable {
    var id: UUID { ingredient.id }
    var ingredient: MealIngredient
    var need: Double
    var covered: Double
    var incompatibleUnits: Bool
    var allocations: [(batchID: UUID, quantity: Double)]

    var missing: Double { max(0, need - covered) }
    var isCovered: Bool { !incompatibleUnits && missing <= 0.0001 }

    static func == (lhs: StockCheckLine, rhs: StockCheckLine) -> Bool {
        lhs.ingredient == rhs.ingredient && lhs.need == rhs.need &&
        lhs.covered == rhs.covered && lhs.incompatibleUnits == rhs.incompatibleUnits
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ingredient)
        hasher.combine(need)
        hasher.combine(covered)
    }
}

// MARK: - Shopping

struct ShoppingItem: Codable, Identifiable, Hashable {
    enum Status: String, Codable {
        case needed, purchased, excluded
        var title: String {
            switch self {
            case .needed: return "Needed"
            case .purchased: return "Purchased"
            case .excluded: return "Excluded"
            }
        }
    }

    enum Source: Codable, Hashable {
        case manual
        case mealShortfall(mealID: UUID, mealName: String)

        var title: String {
            switch self {
            case .manual: return "Added manually"
            case .mealShortfall(_, let name): return "Missing for \(name)"
            }
        }
    }

    var id: UUID = UUID()
    var name: String
    var quantity: Double
    var unit: MeasureUnit
    var store: String?
    var targetPrice: Double?
    var assigneeID: UUID?
    var status: Status = .needed
    var source: Source = .manual
    var createdAt: Date = Date()

    var purchasedAt: Date?
    var actualQuantity: Double?
    var actualPrice: Double?
    /// Set once a purchase created a batch — makes "Mark Purchased" idempotent.
    var createdBatchID: UUID?
    var excludeReason: String?

    var productKey: String { ProductKey.make(name) }
}

// MARK: - Prices

struct PriceEntry: Codable, Identifiable, Hashable {
    enum Origin: String, Codable {
        case userPurchase
        case externalCatalogue

        var title: String {
            switch self {
            case .userPurchase: return "Your purchase"
            case .externalCatalogue: return "External catalogue"
            }
        }
    }

    var id: UUID = UUID()
    var productName: String
    var brand: String?
    var store: String?
    var price: Double
    var quantity: Double
    var unit: MeasureUnit
    var date: Date
    var origin: Origin = .userPurchase
    var sourceName: String?
    var sourceURL: String?
    var batchID: UUID?

    var productKey: String { ProductKey.make(productName) }

    /// Price for one base unit (g / ml / piece / pack). Nil when quantity is unusable.
    var pricePerBaseUnit: Double? {
        let base = MeasureUnit.toBase(quantity, unit: unit)
        guard base > 0 else { return nil }
        return price / base
    }
}

// MARK: - Recalls

struct RecallAlert: Codable, Identifiable, Hashable {
    var id: String                  // recall number from the source
    var title: String
    var firmName: String?
    var productDescription: String
    var reason: String?
    var classification: String?
    var status: String?
    var distribution: String?
    var codes: [String] = []        // lot / UPC codes quoted by the notice
    var reportedAt: Date?
    var sourceName: String
    var sourceURL: String?
    var fetchedAt: Date

    var isCritical: Bool {
        (classification ?? "").localizedCaseInsensitiveContains("class i")
    }
}

struct RecallMatch: Codable, Identifiable, Hashable {
    enum Decision: String, Codable {
        case unconfirmed, confirmed, notAMatch
        var title: String {
            switch self {
            case .unconfirmed: return "Needs your check"
            case .confirmed: return "You confirmed a match"
            case .notAMatch: return "Marked not a match"
            }
        }
    }

    var id: UUID = UUID()
    var alertID: String
    var batchID: UUID
    /// Why the app surfaced this pair — shown to the user, never hidden.
    var reason: String
    var decision: Decision = .unconfirmed
    var decidedAt: Date?
}

struct ArchivedAlert: Codable, Identifiable, Hashable {
    var id: String { alertID }
    var alertID: String
    var reason: String
    var archivedAt: Date = Date()
}

// MARK: - Activity

struct ActivityEntry: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case householdCreated, householdEdited, memberAdded, memberRemoved, zoneAdded, zoneEdited, zoneArchived
        case batchCreated, batchAdjusted, batchOpened, batchMoved, batchEdited, batchArchived, batchRestored, batchDeleted
        case mealCreated, mealEdited, mealReserved, mealReleased, mealCooked, mealCancelled, mealDeleted
        case shoppingAdded, shoppingPurchased, shoppingUndone, shoppingExcluded, shoppingDeleted
        case receiptImported
        case recallChecked, recallDecision, recallArchived
        case dataImported, dataExported

        var symbol: String {
            switch self {
            case .batchCreated, .receiptImported: return "plus.circle.fill"
            case .batchAdjusted: return "slider.horizontal.3"
            case .batchOpened: return "seal.fill"
            case .batchMoved: return "arrow.left.arrow.right.circle.fill"
            case .batchArchived, .batchDeleted, .mealDeleted, .shoppingDeleted: return "archivebox.fill"
            case .batchRestored: return "arrow.uturn.backward.circle.fill"
            case .mealReserved: return "lock.fill"
            case .mealReleased: return "lock.open.fill"
            case .mealCooked: return "fork.knife.circle.fill"
            case .shoppingPurchased: return "cart.fill"
            case .recallDecision, .recallChecked, .recallArchived: return "exclamationmark.shield.fill"
            case .dataImported, .dataExported: return "externaldrive.fill"
            default: return "circle.fill"
            }
        }
    }

    var id: UUID = UUID()
    var date: Date = Date()
    var kind: Kind
    var summary: String
    var detail: String?
    var batchID: UUID?
    var mealID: UUID?
    var shoppingItemID: UUID?
    var alertID: String?
    var quantityDelta: Double?
    var unit: MeasureUnit?
    var reason: AdjustReason?
    var amount: Double?
}

// MARK: - Settings & container

struct AppSettings: Codable, Hashable {
    var expiryWindowDays: Int = 3
    var notificationsEnabled: Bool = false
    var notifyDaysBefore: Int = 2
    var preferredUnitForMass: MeasureUnit = .gram
    var preferredUnitForVolume: MeasureUnit = .milliliter
    var hiddenHomeWidgets: Set<String> = []
    var recallSearchTermsAccepted: Bool = false

    init() {}

    /// Missing keys fall back to the default instead of failing the whole file.
    /// A settings blob written by an older build must still open.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings()
        expiryWindowDays = try container.decodeIfPresent(Int.self, forKey: .expiryWindowDays) ?? fallback.expiryWindowDays
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? fallback.notificationsEnabled
        notifyDaysBefore = try container.decodeIfPresent(Int.self, forKey: .notifyDaysBefore) ?? fallback.notifyDaysBefore
        preferredUnitForMass = try container.decodeIfPresent(MeasureUnit.self, forKey: .preferredUnitForMass) ?? fallback.preferredUnitForMass
        preferredUnitForVolume = try container.decodeIfPresent(MeasureUnit.self, forKey: .preferredUnitForVolume) ?? fallback.preferredUnitForVolume
        hiddenHomeWidgets = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenHomeWidgets) ?? fallback.hiddenHomeWidgets
        recallSearchTermsAccepted = try container.decodeIfPresent(Bool.self, forKey: .recallSearchTermsAccepted) ?? fallback.recallSearchTermsAccepted
    }
}

/// Records a local delete so it can be replicated to the server. Without this a
/// deletion would look like "never existed" and come back on the next pull.
struct Tombstone: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var resource: String
    var recordID: String
    var deletedAt: Date = Date()
}

struct AppData: Codable {
    var schemaVersion: Int = 1
    var onboardingCompleted: Bool = false
    var household: Household?
    var batches: [Batch] = []
    var meals: [Meal] = []
    var reservations: [Reservation] = []
    var shopping: [ShoppingItem] = []
    var prices: [PriceEntry] = []
    var activity: [ActivityEntry] = []
    var recallAlerts: [RecallAlert] = []
    var recallMatches: [RecallMatch] = []
    var archivedAlerts: [ArchivedAlert] = []
    var restockThresholds: [String: Double] = [:]
    var settings: AppSettings = AppSettings()
    var recallLastCheckedAt: Date?
    var savedAt: Date?

    // Sync bookkeeping. Empty on a device that has never signed in.
    var tombstones: [Tombstone] = []
    /// Opaque cursor from the server; echoed back on the next sync.
    var syncCursor: String?
    var lastSyncedAt: Date?

    init() {}

    /// Every field is optional on the way in. A file written by an older build —
    /// one that never heard of tombstones or sync cursors — must still open, and
    /// a single unreadable section must not cost the user the whole kitchen.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        household = try container.decodeIfPresent(Household.self, forKey: .household)
        batches = try container.decodeIfPresent([Batch].self, forKey: .batches) ?? []
        meals = try container.decodeIfPresent([Meal].self, forKey: .meals) ?? []
        reservations = try container.decodeIfPresent([Reservation].self, forKey: .reservations) ?? []
        shopping = try container.decodeIfPresent([ShoppingItem].self, forKey: .shopping) ?? []
        prices = try container.decodeIfPresent([PriceEntry].self, forKey: .prices) ?? []
        activity = try container.decodeIfPresent([ActivityEntry].self, forKey: .activity) ?? []
        recallAlerts = try container.decodeIfPresent([RecallAlert].self, forKey: .recallAlerts) ?? []
        recallMatches = try container.decodeIfPresent([RecallMatch].self, forKey: .recallMatches) ?? []
        archivedAlerts = try container.decodeIfPresent([ArchivedAlert].self, forKey: .archivedAlerts) ?? []
        restockThresholds = try container.decodeIfPresent([String: Double].self, forKey: .restockThresholds) ?? [:]
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        recallLastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .recallLastCheckedAt)
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt)
        tombstones = try container.decodeIfPresent([Tombstone].self, forKey: .tombstones) ?? []
        syncCursor = try container.decodeIfPresent(String.self, forKey: .syncCursor)
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
    }
}
