//
//  InstallState.swift
//  Ocean Cast
//
//  Fallback device key and install flags. The real device key is the AppsFlyer
//  UID; this fallback is used only when the SDK is not linked, so the pipeline
//  still has a stable per-install id to work with.
//

import Foundation

enum InstallState {
    private static var defaults: UserDefaults { .standard }

    /// A stable per-install id, created once. A reinstall produces a new one,
    /// which matches how the AppsFlyer UID behaves.
    static var fallbackRef: String {
        if let existing = defaults.string(forKey: BeaconConfig.Store.fallbackRef) {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: BeaconConfig.Store.fallbackRef)
        return generated
    }

    static var isSeeded: Bool {
        get { defaults.bool(forKey: BeaconConfig.Store.installSeeded) }
        set { defaults.set(newValue, forKey: BeaconConfig.Store.installSeeded) }
    }

    // MARK: - ATT

    static var trackingState: String? {
        get { defaults.string(forKey: BeaconConfig.Store.attState) }
        set { defaults.set(newValue, forKey: BeaconConfig.Store.attState) }
    }

    // MARK: - Push token

    static var pushToken: String? {
        get { defaults.string(forKey: BeaconConfig.Store.pushToken) }
        set { defaults.set(newValue, forKey: BeaconConfig.Store.pushToken) }
    }

    /// The last push token successfully mirrored to the server, so the same one
    /// is never sent twice.
    static var pushSynced: String? {
        get { defaults.string(forKey: BeaconConfig.Store.pushSynced) }
        set { defaults.set(newValue, forKey: BeaconConfig.Store.pushSynced) }
    }
}
