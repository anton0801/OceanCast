//
//  NotificationService.swift
//  Ocean Cast
//
//  Local reminders for the user's own dates. Reminders are rebuilt from the
//  saved batches, so a notification can never outlive the record behind it.
//

import Foundation
import UserNotifications
import Observation

@MainActor
@Observable
final class NotificationService {
    enum Permission: Equatable {
        case unknown, granted, denied, notRequested
    }

    private(set) var permission: Permission = .unknown
    private(set) var scheduledCount: Int = 0
    private(set) var lastError: String?

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: permission = .granted
        case .denied: permission = .denied
        case .notDetermined: permission = .notRequested
        @unknown default: permission = .unknown
        }
        scheduledCount = await UNUserNotificationCenter.current().pendingNotificationRequests().count
    }

    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            permission = granted ? .granted : .denied
            lastError = nil
            return granted
        } catch {
            lastError = error.localizedDescription
            permission = .denied
            return false
        }
    }

    /// Rebuilds every reminder from the current batches.
    func reschedule(batches: [Batch], daysBefore: Int, enabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard enabled, permission == .granted else {
            scheduledCount = 0
            return
        }

        var count = 0
        for batch in batches where !batch.archived && !batch.isDepleted {
            guard let bestBefore = batch.bestBefore,
                  let fireDate = Calendar.current.date(byAdding: .day, value: -max(0, daysBefore), to: bestBefore),
                  fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Check \(batch.productName)"
            content.body = "Your date for this batch is \(DateFormat.day(bestBefore)). The app cannot confirm food safety — check the product yourself."
            content.sound = .default

            var components = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
            components.hour = 9
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: "expiry-\(batch.id.uuidString)",
                                                content: content, trigger: trigger)
            do {
                try await center.add(request)
                count += 1
            } catch {
                lastError = error.localizedDescription
            }
            if count >= 60 { break }   // stay well inside the system limit
        }
        scheduledCount = count
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        scheduledCount = 0
    }
}
