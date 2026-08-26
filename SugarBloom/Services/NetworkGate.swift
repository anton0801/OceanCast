//
//  NetworkGate.swift
//  Ocean Cast
//
//  A hard connectivity gate. The first time the path is not satisfied it latches
//  "no network", stops reacting to further updates, and the blocking screen it
//  drives can only be cleared by relaunching the app.
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkGate {
    private(set) var isBlocked = false

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "OceanCast.networkgate")
    @ObservationIgnored private var latched = false

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self, !self.latched, !satisfied else { return }
                self.latched = true
                self.isBlocked = true
                self.monitor.cancel()
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
