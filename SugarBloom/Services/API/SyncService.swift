//
//  SyncService.swift
//  Ocean Cast
//
//  Push local records, pull whatever changed elsewhere, merge.
//  The local store stays the working copy: sync never blocks the UI and never
//  silently drops a record — anything the server refuses is reported back.
//

import Foundation
import Observation

@MainActor
@Observable
final class SyncService {
    enum Status: Equatable {
        case idle
        case syncing
        case success(Date)
        case failed(String)
        case offline
        case signedOut
    }

    private(set) var status: Status = .idle
    private(set) var rejections: [SyncResponse.Rejection] = []
    /// Records another device had already changed; the server copy won and was
    /// pulled back in the same round trip.
    private(set) var conflicts: [SyncResponse.Rejection] = []
    private(set) var lastPulledCounts: [String: Int] = [:]

    @ObservationIgnored private let client = APIClient.shared
    @ObservationIgnored private var isRunning = false

    var isSyncing: Bool { status == .syncing }

    // MARK: - Entry point

    @discardableResult
    func syncNow(store: AppStore, auth: AuthStore) async -> Bool {
        guard !isRunning else { return false }
        guard auth.isSignedIn else {
            status = .signedOut
            return false
        }
        guard client.isConfigured else {
            status = .failed("No server address is set.")
            return false
        }
        guard let household = store.household else {
            status = .failed("Create a household first — it is what everything else belongs to.")
            return false
        }

        isRunning = true
        status = .syncing
        rejections = []
        conflicts = []
        defer { isRunning = false }

        do {
            let payload = buildPayload(store: store, household: household)
            let response: SyncResponse = try await client.send(.post, "/v1/sync", body: payload)

            apply(response, to: store)
            rejections = response.rejected
            conflicts = response.conflicts
            store.mutate { data in
                data.syncCursor = response.serverTime
                data.lastSyncedAt = Date()
                data.tombstones.removeAll()
            }
            store.saveNow()

            status = .success(Date())
            if !response.rejected.isEmpty {
                status = .failed("\(response.rejected.count) record(s) were not accepted. Open Sync details.")
            }
            return true
        } catch let error as APIError {
            if error.code == "offline" {
                status = .offline
            } else if error.requiresSignIn {
                status = .signedOut
            } else {
                status = .failed(error.message)
            }
            return false
        } catch {
            status = .failed(error.localizedDescription)
            return false
        }
    }

    // MARK: - Push

    private func buildPayload(store: AppStore, household: Household) -> SyncPushPayload {
        var changes: [String: [AnyEncodableRecord]] = [:]

        changes[APIResource.zones.rawValue] = household.zones.map { AnyEncodableRecord($0) }
        changes[APIResource.members.rawValue] = household.members.map { AnyEncodableRecord($0) }
        changes[APIResource.batches.rawValue] = store.data.batches.map { AnyEncodableRecord($0) }
        changes[APIResource.meals.rawValue] = store.data.meals.map { AnyEncodableRecord($0) }
        changes[APIResource.reservations.rawValue] = store.data.reservations.map { AnyEncodableRecord($0) }
        changes[APIResource.shoppingItems.rawValue] = store.data.shopping.map { AnyEncodableRecord(APIShoppingItem($0)) }
        changes[APIResource.prices.rawValue] = store.data.prices.map { AnyEncodableRecord($0) }
        changes[APIResource.activity.rawValue] = store.data.activity.prefix(500).map { AnyEncodableRecord($0) }
        changes[APIResource.recallAlerts.rawValue] = store.data.recallAlerts.prefix(200).map { AnyEncodableRecord($0) }
        changes[APIResource.recallMatches.rawValue] = store.data.recallMatches.map { AnyEncodableRecord($0) }
        changes[APIResource.archivedAlerts.rawValue] = store.data.archivedAlerts.map { AnyEncodableRecord($0) }
        changes[APIResource.thresholds.rawValue] = store.data.restockThresholds.map {
            AnyEncodableRecord(APIThreshold(productKey: $0.key, threshold: $0.value))
        }

        // Deletes travel as identity + deletedAt.
        for tombstone in store.data.tombstones {
            let field: String
            switch tombstone.resource {
            case APIResource.archivedAlerts.rawValue: field = "alertID"
            case APIResource.thresholds.rawValue: field = "productKey"
            default: field = "id"
            }
            changes[tombstone.resource, default: []].append(
                AnyEncodableRecord(tombstoneID: tombstone.recordID, field: field, deletedAt: tombstone.deletedAt)
            )
        }

        // Stay inside the server's per-resource limit; the rest goes next round.
        for (resource, records) in changes where records.count > 500 {
            changes[resource] = Array(records.prefix(500))
        }

        return SyncPushPayload(
            since: store.data.syncCursor,
            household: APIHousehold(id: household.id.uuidString,
                                    name: household.name,
                                    currencyCode: household.currencyCode,
                                    preferences: household.preferences,
                                    createdAt: household.createdAt),
            settings: store.data.settings,
            changes: changes
        )
    }

    // MARK: - Pull

    private func apply(_ response: SyncResponse, to store: AppStore) {
        var counts: [String: Int] = [:]

        store.mutate { data in
            for (name, elements) in response.changes {
                guard let resource = APIResource(rawValue: name), !elements.isEmpty else { continue }
                counts[name] = elements.count

                switch resource {
                case .zones:
                    self.merge(elements, into: &data.household, keyPath: \.zones, id: { $0.id.uuidString })
                case .members:
                    self.merge(elements, into: &data.household, keyPath: \.members, id: { $0.id.uuidString })
                case .batches:
                    self.merge(elements, into: &data.batches, id: { $0.id.uuidString })
                case .meals:
                    self.merge(elements, into: &data.meals, id: { $0.id.uuidString })
                case .reservations:
                    self.merge(elements, into: &data.reservations, id: { $0.id.uuidString })
                case .prices:
                    self.merge(elements, into: &data.prices, id: { $0.id.uuidString })
                case .activity:
                    self.merge(elements, into: &data.activity, id: { $0.id.uuidString })
                case .recallAlerts:
                    self.merge(elements, into: &data.recallAlerts, id: { $0.id })
                case .recallMatches:
                    self.merge(elements, into: &data.recallMatches, id: { $0.id.uuidString })
                case .archivedAlerts:
                    self.merge(elements, into: &data.archivedAlerts, id: { $0.alertID })
                case .shoppingItems:
                    self.mergeShopping(elements, into: &data.shopping)
                case .thresholds:
                    self.mergeThresholds(elements, into: &data.restockThresholds)
                }
            }

            if let household = response.household, data.household != nil {
                data.household?.name = household.name
                data.household?.currencyCode = household.currencyCode
                if let preferences = household.preferences {
                    data.household?.preferences = preferences
                }
            }
            if let settings = response.settings {
                data.settings = settings
            }
            data.activity.sort { $0.date > $1.date }
        }

        lastPulledCounts = counts
    }

    /// Upserts pulled records into a local array and applies tombstones.
    private func merge<T: Decodable>(
        _ elements: [AnyDecodableArrayElement],
        into array: inout [T],
        id: (T) -> String
    ) {
        for element in elements {
            guard let pulled = try? APICoder.decoder.decode(PulledRecord<T>.self, from: element.json) else { continue }
            if pulled.deletedAt != nil {
                array.removeAll { id($0).caseInsensitiveCompare(pulled.identity) == .orderedSame }
                continue
            }
            guard let model = pulled.model else { continue }
            if let index = array.firstIndex(where: { id($0).caseInsensitiveCompare(id(model)) == .orderedSame }) {
                array[index] = model
            } else {
                array.append(model)
            }
        }
    }

    /// Same, for arrays that live inside the household record.
    private func merge<T: Decodable>(
        _ elements: [AnyDecodableArrayElement],
        into household: inout Household?,
        keyPath: WritableKeyPath<Household, [T]>,
        id: (T) -> String
    ) {
        guard var current = household else { return }
        var array = current[keyPath: keyPath]
        merge(elements, into: &array, id: id)
        current[keyPath: keyPath] = array
        household = current
    }

    private func mergeShopping(_ elements: [AnyDecodableArrayElement], into array: inout [ShoppingItem]) {
        for element in elements {
            guard let pulled = try? APICoder.decoder.decode(PulledRecord<APIShoppingItem>.self, from: element.json)
            else { continue }
            if pulled.deletedAt != nil {
                array.removeAll { $0.id.uuidString.caseInsensitiveCompare(pulled.identity) == .orderedSame }
                continue
            }
            guard let model = pulled.model?.local else { continue }
            if let index = array.firstIndex(where: { $0.id == model.id }) {
                array[index] = model
            } else {
                array.append(model)
            }
        }
    }

    private func mergeThresholds(_ elements: [AnyDecodableArrayElement], into dictionary: inout [String: Double]) {
        for element in elements {
            guard let pulled = try? APICoder.decoder.decode(PulledRecord<APIThreshold>.self, from: element.json)
            else { continue }
            if pulled.deletedAt != nil {
                dictionary.removeValue(forKey: pulled.identity)
                continue
            }
            if let model = pulled.model {
                dictionary[model.productKey] = model.threshold
            }
        }
    }
}
