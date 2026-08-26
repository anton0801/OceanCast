//
//  AppTracking.swift
//  Ocean Cast
//
//  ATT prompt and IDFA. A single shared request is made, so the several callers
//  (the AppDelegate and the startup pipeline) all await the same answer instead
//  of racing two prompts. The identifier is read only when tracking is
//  authorized; the all-zero value is treated as absent and never sent.
//

import Foundation
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif
#if canImport(AdSupport)
import AdSupport
#endif

enum AppTracking {
    private static let coordinator = TrackingCoordinator()

    /// Requests authorization once and returns the resolved status name. Every
    /// caller awaits the same in-flight request.
    @discardableResult
    static func resolve() async -> String {
        let status = await coordinator.resolve()
        InstallState.trackingState = status
        return status
    }

    /// The advertising identifier, or nil when tracking is not authorized.
    static var advertisingIdentifier: String? {
        #if canImport(AppTrackingTransparency) && canImport(AdSupport)
        guard ATTrackingManager.trackingAuthorizationStatus == .authorized else { return nil }
        let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
        return idfa == "00000000-0000-0000-0000-000000000000" ? nil : idfa
        #else
        return nil
        #endif
    }
}

private actor TrackingCoordinator {
    private var resolved: String?
    private var inFlight: Task<String, Never>?

    func resolve() async -> String {
        if let resolved { return resolved }
        if let inFlight { return await inFlight.value }

        let task = Task { await Self.request() }
        inFlight = task
        let result = await task.value
        resolved = result
        inFlight = nil
        return result
    }

    private static func request() async -> String {
        #if canImport(AppTrackingTransparency)
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<ATTrackingManager.AuthorizationStatus, Never>) in
            ATTrackingManager.requestTrackingAuthorization { continuation.resume(returning: $0) }
        }
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
        #else
        return "unavailable"
        #endif
    }
}
