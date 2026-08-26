//
//  AppBootstrap.swift
//  Ocean Cast
//
//  The blocking start pipeline. It sends the collect request, waits for the
//  conversion (with a timeout) and the advertising id, then sends the final
//  resolve request whose response is the gate. The result is published for the
//  root view. A hard overall timeout guarantees the splash never hangs — even
//  if the pipeline is stuck (for example on an unanswered ATT prompt).
//

import Foundation
import Observation

@MainActor
@Observable
final class AppBootstrap {
    private(set) var isFinished = false
    private(set) var result = BeaconGate()

    @ObservationIgnored private var started = false
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private let provider: AttributionProviding = LiveAttributionProvider()
    @ObservationIgnored private let client = BeaconClient()

    /// Kicks off the pipeline and the hard-timeout backstop. Returns at once;
    /// callers await `waitUntilFinished()` to know when the gate is ready.
    func run() {
        guard !started else { return }
        started = true

        Task { await pipeline() }
        Task {
            try? await Task.sleep(for: .seconds(BeaconConfig.pipelineTimeout))
            finish(result)
        }
    }

    func waitUntilFinished() async {
        if isFinished { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    private func pipeline() async {
        let ref = provider.deviceRef()

        var fields = BeaconFields(
            ref: ref,
            os: DeviceFacts.osVersion,
            bundle: DeviceFacts.bundleID,
            firebaseProject: provider.firebaseProjectID(),
            store: BeaconConfig.storeID,
            push: provider.pushToken(),
            locale: DeviceFacts.locale,
            idfa: provider.advertisingIdentifier()
        )

        // 1. Facts available immediately.
        await client.collect(fields)

        // 2. Resolve tracking (the prompt) before reading the advertising id.
        _ = await AppTracking.resolve()

        // 3. Wait for the conversion — but only when an SDK can deliver one.
        var conversion: Data?
        if provider.attributionAvailable {
            conversion = await AttributionRelay.shared.waitForConversion(timeout: BeaconConfig.conversionTimeout)
        }

        // 4. Final request: its response is the gate.
        fields.idfa = provider.advertisingIdentifier()
        fields.push = provider.pushToken()
        fields.conversion = conversion
        let gate = await client.resolve(fields)

        finish(gate)
    }

    private func finish(_ gate: BeaconGate) {
        guard !isFinished else { return }
        result = gate
        isFinished = true

        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}
