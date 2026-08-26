//
//  AttributionProvider.swift
//  Ocean Cast
//
//  The connection point for attribution data. `LiveAttributionProvider` reads
//  from the real SDKs when they are linked; everything is guarded by
//  `#if canImport(...)`, so with no SDK the app still builds and the Noop values
//  are used.
//

import Foundation
#if canImport(AppsFlyerLib)
import AppsFlyerLib
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif

protocol AttributionProviding {
    /// Whether a real attribution SDK is present. When false, the pipeline does
    /// not wait for a conversion that will never arrive.
    var attributionAvailable: Bool { get }

    /// The device key. The AppsFlyer UID when available, otherwise a stable
    /// per-install fallback.
    func deviceRef() -> String
    func firebaseProjectID() -> String?
    func pushToken() -> String?
    func advertisingIdentifier() -> String?
}

struct LiveAttributionProvider: AttributionProviding {
    var attributionAvailable: Bool {
        #if canImport(AppsFlyerLib)
        return true
        #else
        return false
        #endif
    }

    func deviceRef() -> String {
        #if canImport(AppsFlyerLib)
        let uid = AppsFlyerLib.shared().getAppsFlyerUID()
        if !uid.isEmpty { return uid }
        #endif
        return InstallState.fallbackRef
    }

    func firebaseProjectID() -> String? {
        #if canImport(FirebaseCore)
        return FirebaseApp.app()?.options.gcmSenderID
        #else
        return nil
        #endif
    }

    func pushToken() -> String? {
        InstallState.pushToken
    }

    func advertisingIdentifier() -> String? {
        AppTracking.advertisingIdentifier
    }
}

/// Used when attribution is deliberately disabled; keeps the pipeline working.
struct NoopAttributionProvider: AttributionProviding {
    var attributionAvailable: Bool { false }
    func deviceRef() -> String { InstallState.fallbackRef }
    func firebaseProjectID() -> String? { nil }
    func pushToken() -> String? { InstallState.pushToken }
    func advertisingIdentifier() -> String? { nil }
}
