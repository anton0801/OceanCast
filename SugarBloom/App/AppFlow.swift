//
//  AppFlow.swift
//  Ocean Cast
//
//  Decides what the root shows after the splash. The gate result (from
//  AppBootstrap) picks the branch once, when the pipeline has finished and the
//  minimum splash time has passed. A route is never recomputed from auth
//  changes, so the special flow is not interrupted mid-way.
//

import Foundation
import Observation

enum AppFlowRoute: Equatable {
    case splash
    case specialOfferForAccount
    case specialOfferForAccountAccepted
    case normal
}

@MainActor
@Observable
final class AppFlow {
    private(set) var route: AppFlowRoute = .splash
    private(set) var analyticsURL: URL? {
        didSet {
            if let a = analyticsURL {
                UserDefaults.standard.set(a.absoluteString, forKey: Tide.routeURL)
            }
        }
    }

    @ObservationIgnored let splashStart = Date()

    func leaveSplash(with result: BeaconGate) {
        guard route == .splash else { return }
        if let url = result.analyticsURL {
            analyticsURL = url
            route = NotificationOffer.shouldShow ? .specialOfferForAccount : .specialOfferForAccountAccepted
        } else {
            route = .normal
        }
    }

    func advanceToAccepted() {
        guard route == .specialOfferForAccount else { return }
        route = .specialOfferForAccountAccepted
    }
}
