//
//  APIModels.swift
//  Ocean Cast
//
//  Wire types and the coders that bridge them to the local models.
//

import Foundation

// MARK: - Coders

enum APICoder {
    /// The API sends plain dates ("2026-08-12"), second-precision timestamps and
    /// microsecond timestamps. One decoder handles all three.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = parse(raw) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unrecognised date: \(raw)")
            )
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFormatter.string(from: date))
        }
        return encoder
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func parse(_ raw: String) -> Date? {
        if let date = fractionalFormatter.date(from: raw) { return date }
        if let date = isoFormatter.date(from: raw) { return date }
        if let date = dayFormatter.date(from: raw) { return date }
        return nil
    }

    static func string(from date: Date) -> String {
        isoFormatter.string(from: date)
    }
}

// MARK: - Errors

struct APIError: LocalizedError, Equatable {
    var status: Int
    var code: String
    var message: String
    var fields: [String: String]

    var errorDescription: String? { message }

    /// The access token expired but the session may still be refreshable.
    var isExpiredAccessToken: Bool { code == "token_expired" }

    /// The session is over for good — the user must sign in again.
    var requiresSignIn: Bool {
        ["invalid_token", "token_revoked", "token_reuse_detected",
         "refresh_expired", "account_inactive", "missing_token"].contains(code)
    }

    var needsHousehold: Bool { code == "household_required" }

    static func offline(_ message: String) -> APIError {
        APIError(status: 0, code: "offline", message: message, fields: [:])
    }

    static func decoding(_ message: String) -> APIError {
        APIError(status: 0, code: "invalid_response", message: message, fields: [:])
    }

    static func notConfigured() -> APIError {
        APIError(status: 0, code: "not_configured",
                 message: "No server address is set. Add one in Settings to enable sync.",
                 fields: [:])
    }
}

private struct APIErrorEnvelope: Decodable {
    struct Body: Decodable {
        var code: String
        var message: String
        var fields: [String: String]?
    }
    var error: Body
}

// MARK: - Auth payloads

struct APIUser: Codable, Equatable {
    var id: String
    var email: String
    var displayName: String
    var createdAt: Date?
}

struct APISession: Codable, Identifiable, Equatable {
    var id: String
    var deviceName: String
    var platform: String
    var createdAt: Date?
    var lastUsedAt: Date?
    var expiresAt: Date?
    var current: Bool
}

struct APITokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var tokenType: String
    var expiresIn: Int
    var refreshExpiresIn: Int
}

struct APIAuthResponse: Decodable {
    var user: APIUser
    var auth: APITokens
}

struct APIProfileResponse: Decodable {
    var user: APIUser
    var household: APIHousehold?
    var records: [String: Int]?
    var sessionCount: Int?
}

struct APISessionsResponse: Decodable {
    var sessions: [APISession]
}

struct APIHousehold: Codable, Equatable {
    var id: String
    var name: String
    var currencyCode: String
    var preferences: ShoppingPreferences?
    var createdAt: Date?
}

// MARK: - Resources

enum APIResource: String, CaseIterable {
    case zones
    case members
    case batches
    case meals
    case reservations
    case shoppingItems = "shopping-items"
    case prices
    case activity
    case recallAlerts = "recall-alerts"
    case recallMatches = "recall-matches"
    case archivedAlerts = "archived-alerts"
    case thresholds
}

/// A pulled record: the model itself plus the tombstone marker. `model` is nil
/// when the server sent a delete for something this device never had.
struct PulledRecord<T: Decodable>: Decodable {
    var model: T?
    var identity: String
    var deletedAt: Date?

    private enum Keys: String, CodingKey {
        case id, alertID, productKey, deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        identity = (try? container.decode(String.self, forKey: .id))
            ?? (try? container.decode(String.self, forKey: .alertID))
            ?? (try? container.decode(String.self, forKey: .productKey))
            ?? ""
        deletedAt = try? container.decodeIfPresent(Date.self, forKey: .deletedAt)
        model = deletedAt == nil ? try? T(from: decoder) : nil
    }
}

/// Shopping items travel with a flat source, because an enum with associated
/// values has no natural column layout.
struct APIShoppingItem: Codable {
    var id: UUID
    var name: String
    var quantity: Double
    var unit: MeasureUnit
    var store: String?
    var targetPrice: Double?
    var assigneeID: UUID?
    var status: ShoppingItem.Status
    var sourceType: String
    var sourceMealID: UUID?
    var sourceMealName: String?
    var purchasedAt: Date?
    var actualQuantity: Double?
    var actualPrice: Double?
    var createdBatchID: UUID?
    var excludeReason: String?
    var createdAt: Date

    init(_ item: ShoppingItem) {
        id = item.id
        name = item.name
        quantity = item.quantity
        unit = item.unit
        store = item.store
        targetPrice = item.targetPrice
        assigneeID = item.assigneeID
        status = item.status
        switch item.source {
        case .manual:
            sourceType = "manual"
            sourceMealID = nil
            sourceMealName = nil
        case .mealShortfall(let mealID, let mealName):
            sourceType = "mealShortfall"
            sourceMealID = mealID
            sourceMealName = mealName
        }
        purchasedAt = item.purchasedAt
        actualQuantity = item.actualQuantity
        actualPrice = item.actualPrice
        createdBatchID = item.createdBatchID
        excludeReason = item.excludeReason
        createdAt = item.createdAt
    }

    var local: ShoppingItem {
        var item = ShoppingItem(name: name, quantity: quantity, unit: unit)
        item.id = id
        item.store = store
        item.targetPrice = targetPrice
        item.assigneeID = assigneeID
        item.status = status
        if sourceType == "mealShortfall", let mealID = sourceMealID {
            item.source = .mealShortfall(mealID: mealID, mealName: sourceMealName ?? "meal")
        } else {
            item.source = .manual
        }
        item.purchasedAt = purchasedAt
        item.actualQuantity = actualQuantity
        item.actualPrice = actualPrice
        item.createdBatchID = createdBatchID
        item.excludeReason = excludeReason
        item.createdAt = createdAt
        return item
    }
}

/// Thresholds are a dictionary locally and a row per product on the wire.
struct APIThreshold: Codable {
    var productKey: String
    var threshold: Double
}

// MARK: - Sync envelope

struct SyncPushPayload: Encodable {
    var since: String?
    var household: APIHousehold?
    var settings: AppSettings?
    var changes: [String: [AnyEncodableRecord]]
}

/// Type-erased record so one payload can carry every resource.
struct AnyEncodableRecord: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        encodeClosure = { encoder in try value.encode(to: encoder) }
    }

    /// A tombstone: identity plus the delete marker, nothing else.
    init(tombstoneID: String, field: String, deletedAt: Date) {
        encodeClosure = { encoder in
            var container = encoder.container(keyedBy: DynamicKey.self)
            try container.encode(tombstoneID, forKey: DynamicKey(stringValue: field))
            try container.encode(APICoder.string(from: deletedAt), forKey: DynamicKey(stringValue: "deletedAt"))
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

struct SyncResponse: Decodable {
    var serverTime: String
    var household: APIHousehold?
    var settings: AppSettings?
    var applied: [String: Int]
    var rejected: [Rejection]
    /// Records the server kept because another device edited them first.
    var conflicts: [Rejection]
    var hasMore: Bool

    /// Raw pulled records, decoded per resource on demand.
    var changes: [String: [AnyDecodableArrayElement]]

    struct Rejection: Decodable {
        var resource: String
        var id: String?
        var reason: String
        var fields: [String: String]?
    }

    private enum Keys: String, CodingKey {
        case serverTime, household, settings, applied, rejected, conflicts, hasMore, changes
    }

    /// Tolerates an empty map arriving as `[]`, which some JSON encoders emit.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        serverTime = try container.decode(String.self, forKey: .serverTime)
        household = try container.decodeIfPresent(APIHousehold.self, forKey: .household)
        settings = try? container.decodeIfPresent(AppSettings.self, forKey: .settings)
        applied = (try? container.decode([String: Int].self, forKey: .applied)) ?? [:]
        rejected = (try? container.decode([Rejection].self, forKey: .rejected)) ?? []
        conflicts = (try? container.decode([Rejection].self, forKey: .conflicts)) ?? []
        hasMore = (try? container.decode(Bool.self, forKey: .hasMore)) ?? false
        changes = (try? container.decode([String: [AnyDecodableArrayElement]].self, forKey: .changes)) ?? [:]
    }
}

/// Keeps a pulled record as raw JSON until the caller knows its concrete type.
struct AnyDecodableArrayElement: Decodable {
    let json: Data

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(JSONValue.self)
        json = try JSONEncoder().encode(value)
    }
}

/// Minimal JSON tree used only to round-trip an unknown record.
indirect enum JSONValue: Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([JSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Error decoding

extension APIError {
    static func decode(status: Int, data: Data) -> APIError {
        if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            return APIError(status: status,
                            code: envelope.error.code,
                            message: envelope.error.message,
                            fields: envelope.error.fields ?? [:])
        }
        return APIError(status: status,
                        code: "http_\(status)",
                        message: "The server replied with status \(status).",
                        fields: [:])
    }
}
