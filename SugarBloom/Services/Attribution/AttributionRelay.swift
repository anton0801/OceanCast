//
//  AttributionRelay.swift
//  Ocean Cast
//
//  A direct, thread-safe channel from the conversion collector to the startup
//  pipeline. The collector delivers the final conversion here; the pipeline
//  awaits it (with a timeout) and forwards it to /v1/beacon/resolve. No
//  NotificationCenter is involved.
//

import Foundation

actor AttributionRelay {
    static let shared = AttributionRelay()

    private var payload: Data?
    private var delivered = false
    private var waiters: [UUID: CheckedContinuation<Data?, Never>] = [:]

    /// Called once by the collector with the merged conversion.
    func deliver(_ conversion: [AnyHashable: Any]) {
        guard !delivered else { return }
        delivered = true
        payload = Self.encode(conversion)

        let pending = waiters
        waiters.removeAll()
        for (_, continuation) in pending {
            continuation.resume(returning: payload)
        }
    }

    /// The conversion as JSON, or nil if none arrived within the timeout.
    func waitForConversion(timeout: TimeInterval) async -> Data? {
        if delivered { return payload }

        let id = UUID()
        return await withCheckedContinuation { continuation in
            waiters[id] = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                await self?.expire(id)
            }
        }
    }

    private func expire(_ id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        continuation.resume(returning: payload)
    }

    private static func encode(_ conversion: [AnyHashable: Any]) -> Data? {
        var object: [String: Any] = [:]
        for (key, value) in conversion {
            object[String(describing: key)] = value
        }
        if JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object) {
            return data
        }
        // Fall back to a flat string map when a value is not JSON-native.
        var flat: [String: String] = [:]
        for (key, value) in object where !(value is NSNull) {
            flat[key] = String(describing: value)
        }
        return try? JSONSerialization.data(withJSONObject: flat)
    }
}
