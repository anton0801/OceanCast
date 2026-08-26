//
//  NotificationOffer.swift
//  Ocean Cast
//
//  When the offer screen should be shown. Yes (any system answer) or a second
//  Skip settles it for good; the first Skip snoozes it for a few days.
//

import Foundation

enum NotificationOffer {
    static var shouldShow: Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: BeaconConfig.Store.offerSettled) { return false }
        if let firstSkip = defaults.object(forKey: BeaconConfig.Store.offerSnoozedAt) as? Date {
            return Date() >= firstSkip.addingTimeInterval(BeaconConfig.offerSnoozeDays * 86_400)
        }
        return true
    }

    static func markSettled() {
        UserDefaults.standard.set(true, forKey: BeaconConfig.Store.offerSettled)
    }

    static func registerSkip() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: BeaconConfig.Store.offerSnoozedAt) is Date {
            // A skip after the snooze window has already passed → never again.
            markSettled()
        } else {
            defaults.set(Date(), forKey: BeaconConfig.Store.offerSnoozedAt)
        }
    }
}
