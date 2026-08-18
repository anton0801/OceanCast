//
//  Contract test: compiles the app's real models and coders and talks to the
//  live API, so the Swift ↔ PHP wire format is verified rather than assumed.
//

import Foundation

let base = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "http://127.0.0.1:8791"
var passed = 0
var failed = 0

func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        passed += 1
        print("  ok    \(label)")
    } else {
        failed += 1
        print("  FAIL  \(label)\(detail.isEmpty ? "" : "  (\(detail))")")
    }
}

struct HTTPResult {
    var status: Int
    var data: Data
    var text: String { String(data: data, encoding: .utf8) ?? "" }
}

func call(_ method: String, _ path: String, body: Data? = nil, token: String? = nil) -> HTTPResult {
    var request = URLRequest(url: URL(string: base + path)!)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
    }
    if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    request.setValue("Contract Test", forHTTPHeaderField: "X-Device-Name")
    request.setValue("ios", forHTTPHeaderField: "X-Platform")

    let semaphore = DispatchSemaphore(value: 0)
    var result = HTTPResult(status: 0, data: Data())
    URLSession.shared.dataTask(with: request) { data, response, _ in
        result = HTTPResult(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data ?? Data())
        semaphore.signal()
    }.resume()
    _ = semaphore.wait(timeout: .now() + 30)
    return result
}

func encode<T: Encodable>(_ value: T) -> Data {
    try! APICoder.encoder.encode(value)
}

let suffix = UUID().uuidString.prefix(8).lowercased()
let email = "contract-\(suffix)@example.test"
let password = "Str0ngPassphrase!\(suffix)"

print("Swift client ↔ PHP API contract test → \(base)\n")

// ---------------------------------------------------------------- register
struct RegisterBody: Encodable { let email: String; let password: String; let displayName: String }
var result = call("POST", "/v1/auth/register",
                  body: encode(RegisterBody(email: email, password: password, displayName: "Contract")))
check("register", result.status == 201, "status \(result.status) \(result.text.prefix(120))")

guard let auth = try? APICoder.decoder.decode(APIAuthResponse.self, from: result.data) else {
    print("  FAIL  decode APIAuthResponse — \(result.text.prefix(200))")
    exit(1)
}
check("APIAuthResponse decodes with the app's own coder", !auth.auth.accessToken.isEmpty)
check("user decodes", auth.user.email == email)
let token = auth.auth.accessToken

// --------------------------------------------------------------- household
let householdID = UUID()
struct HouseholdBody: Encodable {
    let id: String
    let name: String
    let currencyCode: String
    let preferences: ShoppingPreferences
}
var preferences = ShoppingPreferences()
preferences.defaultStore = "Corner Market"
preferences.expiryWindowDays = 3
preferences.defaultLowStockThreshold = 2

result = call("PUT", "/v1/household",
              body: encode(HouseholdBody(id: householdID.uuidString, name: "Contract Kitchen",
                                         currencyCode: "USD", preferences: preferences)),
              token: token)
check("household upsert", result.status == 200, "status \(result.status) \(result.text.prefix(160))")

// ----------------------------------------------------- push the real models
let zone = StorageZone(name: "Fridge", kind: .fridge)
var batch = Batch(productName: "Greek Yoghurt",
                  brand: "Meadow",
                  barcode: "5901234123457",
                  quantity: 4,
                  remaining: 3,
                  unit: .piece,
                  purchaseDate: Date(),
                  bestBefore: Calendar.current.date(byAdding: .day, value: 2, to: Date()),
                  zoneID: zone.id,
                  price: 5.6,
                  store: "Corner Market",
                  origin: .scan,
                  notes: "Quoted 'name' with \"escapes\" & symbols — ünïcode ✅")
batch.reference = ReferenceHint(sourceName: "Open Food Facts",
                                sourceURL: "https://world.openfoodfacts.org/product/5901234123457",
                                fetchedAt: Date(),
                                shelfLifeDaysHint: nil,
                                categories: "Dairies",
                                quantityText: "4 x 150 g")

let ingredient = MealIngredient(name: "Spaghetti", quantityPerServing: 0.12, unit: .kilogram)
let meal = Meal(name: "Tomato Pasta", servings: 2, date: Date(), prepMinutes: 25,
                notes: nil, ingredients: [ingredient], status: .planned)
let reservation = Reservation(mealID: meal.id, ingredientID: ingredient.id,
                              batchID: batch.id, quantity: 0.24)
var shopping = ShoppingItem(name: "Basil", quantity: 1, unit: .pack, store: "Corner Market",
                            targetPrice: 2.5)
shopping.source = .mealShortfall(mealID: meal.id, mealName: meal.name)
let price = PriceEntry(productName: "Greek Yoghurt", brand: "Meadow", store: "Corner Market",
                       price: 5.6, quantity: 4, unit: .piece, date: Date(),
                       origin: .userPurchase, batchID: batch.id)
let activity = ActivityEntry(kind: .batchCreated, summary: "Added 4 pcs of Greek Yoghurt",
                             detail: "Added by barcode scan", batchID: batch.id,
                             quantityDelta: 4, unit: .piece, amount: 5.6)
let alert = RecallAlert(id: "F-1234-2026", title: "Contract test notice",
                        firmName: "Example Foods", productDescription: "Yoghurt 150 g cups",
                        reason: "Undeclared allergen", classification: "Class I",
                        status: "Ongoing", distribution: "Nationwide",
                        codes: ["LOT123", "5901234123457"], reportedAt: Date(),
                        sourceName: "openFDA", sourceURL: "https://www.fda.gov/", fetchedAt: Date())
let match = RecallMatch(alertID: alert.id, batchID: batch.id,
                        reason: "Barcode 5901234123457 appears in the notice")
let archived = ArchivedAlert(alertID: "F-9999-2026", reason: "Checked — none of my items match")

struct SyncBody: Encodable {
    let since: String?
    let settings: AppSettings
    let changes: [String: [AnyEncodableRecord]]
}

var settings = AppSettings()
settings.expiryWindowDays = 3
settings.hiddenHomeWidgets = ["lowStock"]

let changes: [String: [AnyEncodableRecord]] = [
    "zones": [AnyEncodableRecord(zone)],
    "members": [AnyEncodableRecord(Member(name: "Anton", email: "anton@example.test", role: .owner))],
    "batches": [AnyEncodableRecord(batch)],
    "meals": [AnyEncodableRecord(meal)],
    "reservations": [AnyEncodableRecord(reservation)],
    "shopping-items": [AnyEncodableRecord(APIShoppingItem(shopping))],
    "prices": [AnyEncodableRecord(price)],
    "activity": [AnyEncodableRecord(activity)],
    "recall-alerts": [AnyEncodableRecord(alert)],
    "recall-matches": [AnyEncodableRecord(match)],
    "archived-alerts": [AnyEncodableRecord(archived)],
    "thresholds": [AnyEncodableRecord(APIThreshold(productKey: "greek yoghurt", threshold: 2))],
]

result = call("POST", "/v1/sync",
              body: encode(SyncBody(since: nil, settings: settings, changes: changes)),
              token: token)
check("sync push accepted", result.status == 200, "status \(result.status) \(result.text.prefix(200))")

guard let sync = try? APICoder.decoder.decode(SyncResponse.self, from: result.data) else {
    print("  FAIL  decode SyncResponse — \(result.text.prefix(300))")
    exit(1)
}
check("SyncResponse decodes", !sync.serverTime.isEmpty)
check("nothing rejected", sync.rejected.isEmpty,
      sync.rejected.map { "\($0.resource): \($0.reason) \($0.fields ?? [:])" }.joined(separator: " | "))

for resource in ["zones", "members", "batches", "meals", "reservations",
                 "shopping-items", "prices", "activity", "recall-alerts",
                 "recall-matches", "archived-alerts", "thresholds"] {
    check("applied \(resource)", (sync.applied[resource] ?? 0) == 1, "applied \(sync.applied[resource] ?? 0)")
}

// ------------------------------------------------------- pull and round-trip
result = call("POST", "/v1/sync", body: encode(SyncBody(since: nil, settings: settings, changes: [:])), token: token)
let pull: SyncResponse
do {
    pull = try APICoder.decoder.decode(SyncResponse.self, from: result.data)
} catch {
    print("  FAIL  decode pull — \(error)")
    print("  body: \(result.text.prefix(600))")
    exit(1)
}

func decodeOne<T: Decodable>(_ resource: String, _ type: T.Type) -> T? {
    guard let element = pull.changes[resource]?.first,
          let record = try? APICoder.decoder.decode(PulledRecord<T>.self, from: element.json) else { return nil }
    return record.model
}

if let pulled: Batch = decodeOne("batches", Batch.self) {
    check("Batch survives the round trip", pulled.id == batch.id)
    check("  · name and unicode notes", pulled.productName == batch.productName && pulled.notes == batch.notes)
    check("  · decimals keep their value", pulled.remaining == 3 && pulled.price == 5.6)
    check("  · unit enum", pulled.unit == .piece)
    check("  · origin enum", pulled.origin == .scan)
    check("  · zone link", pulled.zoneID == zone.id)
    check("  · catalogue hint stays separate", pulled.reference?.sourceName == "Open Food Facts")
    let sameDay = Calendar.current.isDate(pulled.bestBefore ?? .distantPast,
                                          inSameDayAs: batch.bestBefore ?? .distantFuture)
    check("  · user date keeps its day", sameDay)
} else {
    check("Batch survives the round trip", false, "not returned")
}

if let pulled: Meal = decodeOne("meals", Meal.self) {
    check("Meal survives the round trip", pulled.id == meal.id && pulled.servings == 2)
    check("  · ingredients keep ids and units",
          pulled.ingredients.first?.id == ingredient.id && pulled.ingredients.first?.unit == .kilogram)
    check("  · fractional quantity", pulled.ingredients.first?.quantityPerServing == 0.12)
} else {
    check("Meal survives the round trip", false, "not returned")
}

if let pulled: APIShoppingItem = decodeOne("shopping-items", APIShoppingItem.self) {
    let local = pulled.local
    check("ShoppingItem survives the round trip", local.id == shopping.id)
    if case .mealShortfall(let mealID, let name) = local.source {
        check("  · meal shortfall source is preserved", mealID == meal.id && name == meal.name)
    } else {
        check("  · meal shortfall source is preserved", false, "came back as manual")
    }
} else {
    check("ShoppingItem survives the round trip", false, "not returned")
}

if let pulled: ActivityEntry = decodeOne("activity", ActivityEntry.self) {
    check("ActivityEntry survives the round trip", pulled.id == activity.id && pulled.kind == .batchCreated)
} else {
    check("ActivityEntry survives the round trip", false, "not returned")
}

if let pulled: RecallAlert = decodeOne("recall-alerts", RecallAlert.self) {
    check("RecallAlert survives the round trip", pulled.id == alert.id && pulled.codes.count == 2)
    check("  · classification kept", pulled.isCritical)
} else {
    check("RecallAlert survives the round trip", false, "not returned")
}

if let pulled: ArchivedAlert = decodeOne("archived-alerts", ArchivedAlert.self) {
    check("ArchivedAlert survives the round trip", pulled.alertID == archived.alertID)
} else {
    check("ArchivedAlert survives the round trip", false, "not returned")
}

check("household comes back", pull.household?.name == "Contract Kitchen")
check("preferences round-trip", pull.household?.preferences?.defaultLowStockThreshold == 2)
check("settings round-trip", pull.settings?.hiddenHomeWidgets == ["lowStock"])

// ------------------------------------------------------------- tombstones
let tombstone = AnyEncodableRecord(tombstoneID: batch.id.uuidString, field: "id", deletedAt: Date())
result = call("POST", "/v1/sync",
              body: encode(SyncBody(since: pull.serverTime, settings: settings,
                                    changes: ["batches": [tombstone]])),
              token: token)
if let afterDelete = try? APICoder.decoder.decode(SyncResponse.self, from: result.data) {
    let deleted = afterDelete.changes["batches"]?.compactMap {
        try? APICoder.decoder.decode(PulledRecord<Batch>.self, from: $0.json)
    }.filter { $0.deletedAt != nil } ?? []
    check("local delete replicates as a tombstone", deleted.count == 1)
    check("  · tombstone carries the id", deleted.first?.identity.uppercased() == batch.id.uuidString.uppercased())
} else {
    check("local delete replicates as a tombstone", false, "no response")
}

// ------------------------------------------------------------ error shape
result = call("POST", "/v1/batches",
              body: "{\"id\":\"\(UUID().uuidString)\",\"productName\":\"Bad\",\"quantity\":-1,\"remaining\":1,\"unit\":\"piece\"}".data(using: .utf8),
              token: token)
let apiError = APIError.decode(status: result.status, data: result.data)
check("validation errors decode into APIError", apiError.status == 422 && apiError.fields["quantity"] != nil,
      "\(apiError.code) \(apiError.fields)")

result = call("GET", "/v1/profile", token: "sb_at_" + String(repeating: "0", count: 64))
let authError = APIError.decode(status: result.status, data: result.data)
check("invalid token maps to a sign-in error", authError.requiresSignIn, authError.code)

// ---------------------------------------------------------------- clean up
struct DeleteBody: Encodable { let password: String; let confirm: String }
result = call("DELETE", "/v1/profile", body: encode(DeleteBody(password: password, confirm: "DELETE")), token: token)
check("account deleted", result.status == 200)

print("\n" + String(repeating: "-", count: 52))
print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
