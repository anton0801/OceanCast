//
//  NetworkMonitor.swift
//  Ocean Cast
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline: Bool = true
    private(set) var hasDeterminedPath: Bool = false

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "OceanCast.network")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = online
                self?.hasDeterminedPath = true
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
