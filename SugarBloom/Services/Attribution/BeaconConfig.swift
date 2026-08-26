//
//  BeaconConfig.swift
//  Ocean Cast
//
//  App-specific names for the device-attribution layer. These are deliberately
//  unique to this app (routes, JSON keys, local-storage keys) so the client does
//  not look like a template; the server maps them onto its fixed columns, and the
//  external analytics service is fed its own fixed vocabulary server-side.
//

import Foundation

enum BeaconConfig {
    // Endpoints (relative to APIClient.baseURL).
    static let collectPath = "/v1/beacon"
    static let resolvePath = "/v1/beacon/resolve"
    static let linkPath = "/v1/beacon/link"

    // Outgoing body keys (app -> our API).
    enum Wire {
        static let envelope = "sealed"     // encrypted payload wrapper
        static let ref = "ref"             // device key (AppsFlyer UID / fallback)
        static let os = "sys"
        static let bundle = "pkg"
        static let firebaseProject = "proj"
        static let store = "listing"
        static let push = "pushId"
        static let locale = "locale"
        static let idfa = "adTag"
        static let conversion = "attr"
    }

    // Local storage keys (UserDefaults). Named per-app on purpose.
    enum Store {
        static let fallbackRef = "oc.install.ref"
        static let installSeeded = "oc.install.seeded"
        static let attState = "oc.att.state"
        static let pushToken = "oc.push.token"
        static let pushSynced = "oc.push.synced"
        static let offerSettled = "oc.offer.settled"
        static let offerSnoozedAt = "oc.offer.snoozedAt"
    }

    // Info.plist key holding the 64-hex AES-256-GCM key (must match the server).
    static let cryptoKeyInfoPlistKey = "OCBeaconKey"

    // The App Store id, sent as `listing`.
    static let storeID = "id6802835318"

    // Response header that carries the offer URL when the gate opens.
    static let analyticsServiceHeader = "analytics-service"

    // Splash pipeline timing.
    static let conversionTimeout: TimeInterval = 25
    static let pipelineTimeout: TimeInterval = 30
    static let minimumSplash: TimeInterval = 1.2

    // Days before a once-skipped notification offer is shown a second time.
    static let offerSnoozeDays: TimeInterval = 3
}
