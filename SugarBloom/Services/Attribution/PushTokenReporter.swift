//
//  PushTokenReporter.swift
//  Ocean Cast
//
//  The push token usually arrives after the startup requests. When it does, it
//  is sent on its own to the collect endpoint (upsert; an empty value never
//  overwrites). The same token is never sent twice.
//

import Foundation

enum PushTokenReporter {
    static func report(_ token: String) async {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        InstallState.pushToken = token
        guard InstallState.pushSynced != token else { return }

        let ref = LiveAttributionProvider().deviceRef()
        let ok = await BeaconClient().reportPush(ref: ref, token: token)
        if ok {
            InstallState.pushSynced = token
        }
    }
}
