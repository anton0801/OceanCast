//
//  SettingsView.swift
//  Ocean Cast
//
//  SCREEN 14 — Units, notifications, export, backup and deletion.
//  Everything destructive states its consequences first.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(NotificationService.self) private var notifications
    @Environment(NetworkMonitor.self) private var network
    @Environment(AuthStore.self) private var auth
    @Environment(SyncService.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @State private var showProfile = false
    @State private var serverURL = APIClient.shared.baseURLString

    @State private var toast: ToastMessage?
    @State private var exportJSONURL: URL?
    @State private var exportCSVURL: URL?
    @State private var showImporter = false
    @State private var pendingImport: AppData?
    @State private var importError: String?
    @State private var deleteHouseholdStage = 0
    @State private var deleteAccountStage = 0
    @State private var expiryWindow = 3
    @State private var notifyDays = 2
    @State private var notificationsOn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(eyebrow: "Settings & Data",
                                 title: "Your data stays here",
                                 subtitle: "Ocean Cast keeps everything on this device. There is no sync in this version, so nothing is uploaded.",
                                 tint: Ocean.tide)

                    accountCard
                    storageCard
                    notificationsCard
                    unitsCard
                    exportCard
                    importCard
                    dangerCard
                    aboutCard
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(OceanBackground(tint: Ocean.tide))
            .toastHost($toast)
            .navigationTitle("Settings & Data")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $showProfile) { ProfileView() }
            .onAppear {
                serverURL = APIClient.shared.baseURLString
                expiryWindow = store.data.settings.expiryWindowDays
                notifyDays = store.data.settings.notifyDaysBefore
                notificationsOn = store.data.settings.notificationsEnabled
            }
            .task { await notifications.refreshStatus() }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .alert("Replace everything with this backup?",
                   isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
                Button("Cancel", role: .cancel) { pendingImport = nil }
                Button("Replace local data", role: .destructive) { applyImport() }
            } message: {
                if let pendingImport {
                    Text("The backup holds \(pendingImport.batches.count) batch(es), \(pendingImport.meals.count) meal(s), \(pendingImport.shopping.count) shopping line(s) and \(pendingImport.activity.count) history record(s).\n\nYour current data (\(store.data.batches.count) batch(es)) is copied aside first, but the app will show the imported data from then on.")
                }
            }
        }
    }

    // MARK: - Cards

    private var accountCard: some View {
        SectionCard(title: "Account & Sync", symbol: "person.crop.circle.fill", tint: Ocean.tide) {
            VStack(alignment: .leading, spacing: 14) {
                if let user = auth.state.user {
                    row("Signed in as", user.email)
                    row("Last sync", store.data.lastSyncedAt.map(DateFormat.stamp) ?? "never")
                    row("Pending deletes to send", "\(store.data.tombstones.count)")
                    HStack(spacing: 10) {
                        OceanButton(title: "Sync now", symbol: "arrow.clockwise",
                                    kind: .secondary, tint: Ocean.turquoise,
                                    fullWidth: false, compact: true, isBusy: sync.isSyncing) {
                            Task {
                                await sync.syncNow(store: store, auth: auth)
                                if case .failed(let message) = sync.status {
                                    toast = ToastMessage(kind: .warning, title: "Sync problem", detail: message)
                                } else {
                                    toast = ToastMessage(title: "Sync complete")
                                }
                            }
                        }
                        OceanButton(title: "Profile", symbol: "person.fill",
                                    kind: .ghost, fullWidth: false, compact: true) {
                            showProfile = true
                        }
                    }
                } else {
                    Text("You are not signed in. Everything works locally; an account adds sync and a server-side backup.")
                        .font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    OceanButton(title: "Sign in or create an account", symbol: "person.crop.circle.badge.plus",
                                kind: .secondary, tint: Ocean.tide) {
                        showProfile = true
                    }
                }

                OceanTextField(label: "Server address", placeholder: "https://api.example.com", text: $serverURL)
                HStack(spacing: 10) {
                    OceanButton(title: "Save address", kind: .ghost, fullWidth: false, compact: true) {
                        APIClient.shared.baseURLString = serverURL
                        toast = ToastMessage(kind: .info, title: "Server address saved",
                                             detail: "Sign in again if you switched servers.")
                    }
                    Spacer()
                }
                Text("The app only ever talks to this address. HTTPS is required outside a local network; tokens are stored in the Keychain and sent on every request.")
                    .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var storageCard: some View {
        SectionCard(title: "Storage", symbol: "internaldrive.fill", tint: Ocean.turquoise) {
            VStack(alignment: .leading, spacing: 10) {
                row("Last saved", store.lastSavedAt.map(DateFormat.stamp) ?? "not saved yet")
                row("Batches", "\(store.data.batches.count)")
                row("Meals", "\(store.data.meals.count)")
                row("Shopping lines", "\(store.data.shopping.count)")
                row("History records", "\(store.data.activity.count)")
                row("Recall notices stored", "\(store.data.recallAlerts.count)")
                if let error = store.saveErrorMessage {
                    ErrorCard(title: "Saving failed", message: error, onRetry: { store.saveNow() })
                }
                OceanButton(title: "Save now", symbol: "arrow.down.doc.fill",
                            kind: .secondary, tint: Ocean.turquoise, compact: true) {
                    store.saveNow()
                    toast = ToastMessage(title: "Saved", detail: "Everything survives a restart.")
                }
            }
        }
    }

    private var notificationsCard: some View {
        SectionCard(title: "Notification Rules", symbol: "bell.fill", tint: Ocean.sky) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $notificationsOn) {
                    Text("Remind me before my dates")
                        .font(OceanFont.body(14.5)).foregroundStyle(Ocean.ink)
                }
                .tint(Ocean.sky)
                .onChange(of: notificationsOn) { _, newValue in
                    Task { await updateNotifications(enabled: newValue) }
                }

                OceanField(label: "Days before your date", tint: Ocean.sky) {
                    Stepper(value: $notifyDays, in: 0...14) {
                        Text("\(notifyDays) day(s) before")
                            .font(OceanFont.body(14.5)).foregroundStyle(Ocean.ink)
                    }
                }
                .onChange(of: notifyDays) { _, _ in
                    Task { await updateNotifications(enabled: notificationsOn) }
                }

                switch notifications.permission {
                case .denied:
                    InfoNote(text: "Notifications are turned off for Ocean Cast in iOS Settings. Reminders cannot be scheduled until that changes — the app will not pretend they were.",
                             symbol: "bell.slash.fill", tint: Ocean.coral)
                case .granted:
                    Text("\(notifications.scheduledCount) reminder(s) scheduled from batches that have a date.")
                        .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.turquoise)
                case .notRequested, .unknown:
                    Text("Turning this on asks iOS for permission first.")
                        .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.inkSoft)
                }

                if let error = notifications.lastError {
                    Text(error).font(OceanFont.caption(11)).foregroundStyle(Ocean.coral)
                }
            }
        }
    }

    private var unitsCard: some View {
        SectionCard(title: "Units & window", symbol: "ruler.fill", tint: Ocean.turquoise) {
            VStack(alignment: .leading, spacing: 14) {
                OceanField(label: "Expiry window (days)", tint: Ocean.turquoise) {
                    Stepper(value: $expiryWindow, in: 1...30) {
                        Text("\(expiryWindow) day(s)")
                            .font(OceanFont.body(14.5)).foregroundStyle(Ocean.ink)
                    }
                }
                .onChange(of: expiryWindow) { _, newValue in
                    store.mutate { $0.settings.expiryWindowDays = newValue }
                }
                Text("Home and Expiry Review use this window. Items without your date stay Unknown regardless of it.")
                    .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                row("Currency", store.currency)
                Text("Currency comes from the household and applies to new records.")
                    .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
            }
        }
    }

    private var exportCard: some View {
        SectionCard(title: "Export Data", symbol: "square.and.arrow.up.fill", tint: Ocean.tide) {
            VStack(alignment: .leading, spacing: 12) {
                Text("A JSON export is a complete backup that can be imported back. The CSV lists your batches for a spreadsheet.")
                    .font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)

                if let exportJSONURL {
                    ShareLink(item: exportJSONURL) {
                        Label("Share backup JSON", systemImage: "square.and.arrow.up").font(OceanFont.headline(15))
                    }
                    .buttonStyle(OceanButtonStyle(kind: .secondary, tint: Ocean.tide))
                }
                OceanButton(title: "Prepare JSON backup", symbol: "doc.badge.gearshape",
                            kind: .secondary, tint: Ocean.tide) { prepareJSON() }

                if let exportCSVURL {
                    ShareLink(item: exportCSVURL) {
                        Label("Share inventory CSV", systemImage: "tablecells").font(OceanFont.headline(15))
                    }
                    .buttonStyle(OceanButtonStyle(kind: .ghost))
                }
                OceanButton(title: "Prepare inventory CSV", symbol: "tablecells",
                            kind: .ghost) { prepareCSV() }
            }
        }
    }

    private var importCard: some View {
        SectionCard(title: "Import Backup", symbol: "square.and.arrow.down.fill", tint: Ocean.sky) {
            VStack(alignment: .leading, spacing: 12) {
                Text("A backup is validated before anything is replaced. If the file cannot be read, your current data stays exactly as it is.")
                    .font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                if let importError {
                    ErrorCard(title: "Backup rejected", message: importError,
                              onDismiss: { self.importError = nil })
                }
                OceanButton(title: "Choose backup file", symbol: "folder.fill",
                            kind: .secondary, tint: Ocean.sky) { showImporter = true }
            }
        }
    }

    private var dangerCard: some View {
        SectionCard(title: "Delete", symbol: "trash.fill", tint: Ocean.coral) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Delete Household").font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                    Text("This removes \(store.data.batches.count) batch(es), \(store.data.meals.count) meal(s), \(store.data.shopping.count) shopping line(s), \(store.data.prices.count) price record(s) and \(store.data.activity.count) history record(s) from this device.")
                        .font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if deleteHouseholdStage == 0 {
                        OceanButton(title: "Delete Household", symbol: "trash", kind: .danger) {
                            deleteHouseholdStage = 1
                        }
                    } else {
                        Text("Confirm once more. This cannot be undone without a backup.")
                            .font(OceanFont.caption(12)).foregroundStyle(Ocean.coral)
                        HStack(spacing: 10) {
                            OceanButton(title: "Yes, delete everything", kind: .danger, compact: true) {
                                store.deleteHousehold()
                                deleteHouseholdStage = 0
                                Haptics.warning()
                                toast = ToastMessage(kind: .warning, title: "Household deleted")
                            }
                            OceanButton(title: "Keep it", kind: .ghost, compact: true) {
                                deleteHouseholdStage = 0
                            }
                        }
                    }
                }

                Divider().overlay(Ocean.hairline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Erase this device").font(OceanFont.headline(15)).foregroundStyle(Ocean.ink)
                    Text(auth.isSignedIn
                         ? "This clears the local copy only, including photos. Your account and the server copy stay — delete those from Profile."
                         : "This clears everything stored locally, including photos. You are not signed in, so nothing exists on a server to delete.")
                        .font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if auth.isSignedIn {
                        OceanButton(title: "Delete account on the server", symbol: "person.crop.circle.badge.xmark",
                                    kind: .secondary, tint: Ocean.coral) {
                            showProfile = true
                        }
                    }
                    if deleteAccountStage == 0 {
                        OceanButton(title: "Erase All Local Data", symbol: "xmark.bin.fill", kind: .danger) {
                            deleteAccountStage = 1
                        }
                    } else {
                        HStack(spacing: 10) {
                            OceanButton(title: "Erase everything", kind: .danger, compact: true) {
                                store.eraseEverything()
                                deleteAccountStage = 0
                                Haptics.warning()
                                dismiss()
                            }
                            OceanButton(title: "Cancel", kind: .ghost, compact: true) {
                                deleteAccountStage = 0
                            }
                        }
                    }
                }
            }
        }
    }

    private var aboutCard: some View {
        SectionCard(title: "About", symbol: "info.circle.fill", tint: Ocean.inkFaint) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ocean Cast does not assess food safety. Dates, quantities and decisions are yours; the app keeps them consistent across screens.")
                    .font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                row("Barcode catalogue", ProductLookupService.sourceName)
                row("Recall notices", "openFDA (U.S. FDA)")
                row("Receipt reading", "on-device Vision")
                row("Network", network.isOnline ? "online" : "offline")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
            Spacer()
            Text(value).font(OceanFont.headline(13.5)).foregroundStyle(Ocean.ink)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Actions

    private func updateNotifications(enabled: Bool) async {
        if enabled && notifications.permission != .granted {
            let granted = await notifications.requestPermission()
            if !granted {
                notificationsOn = false
                store.mutate { $0.settings.notificationsEnabled = false }
                toast = ToastMessage(kind: .warning, title: "Permission not granted",
                                     detail: "Reminders stay off until iOS allows them.")
                return
            }
        }
        store.mutate {
            $0.settings.notificationsEnabled = enabled
            $0.settings.notifyDaysBefore = notifyDays
        }
        await notifications.reschedule(batches: store.activeBatches,
                                       daysBefore: notifyDays,
                                       enabled: enabled)
        if enabled {
            toast = ToastMessage(title: "\(notifications.scheduledCount) reminder(s) scheduled",
                                 detail: "Only batches with a date you entered can have one.")
        }
    }

    private func prepareJSON() {
        do {
            exportJSONURL = try PersistenceController.shared.exportJSON(store.data)
            store.mutate { data in
                data.activity.insert(ActivityEntry(kind: .dataExported,
                                                   summary: "Exported a JSON backup"), at: 0)
            }
            Haptics.success()
            toast = ToastMessage(title: "Backup ready", detail: "Use Share backup JSON to save it.")
        } catch {
            Haptics.warning()
            toast = ToastMessage(kind: .warning, title: "Export failed", detail: error.localizedDescription)
        }
    }

    private func prepareCSV() {
        var rows = ["product,brand,quantity,remaining,unit,zone,best_before,price,store,origin,archived"]
        for batch in store.data.batches {
            let fields = [
                csv(batch.productName),
                csv(batch.brand ?? ""),
                Format.quantity(batch.quantity),
                Format.quantity(batch.remaining),
                batch.unit.short,
                csv(store.zoneName(batch.zoneID) ?? ""),
                batch.bestBefore.map(DateFormat.day) ?? "unknown",
                batch.price.map { String(format: "%.2f", $0) } ?? "unknown",
                csv(batch.store ?? ""),
                batch.origin.rawValue,
                batch.archived ? "yes" : "no"
            ]
            rows.append(fields.joined(separator: ","))
        }
        do {
            exportCSVURL = try PersistenceController.shared.exportCSV(rows.joined(separator: "\n"), name: "inventory")
            Haptics.success()
            toast = ToastMessage(title: "CSV ready", detail: "Unknown values are written as “unknown”, never as 0.")
        } catch {
            Haptics.warning()
            toast = ToastMessage(kind: .warning, title: "Export failed", detail: error.localizedDescription)
        }
    }

    private func csv(_ value: String) -> String {
        value.replacingOccurrences(of: ",", with: " ")
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                pendingImport = try PersistenceController.shared.inspectBackup(at: url)
                importError = nil
            } catch {
                importError = error.localizedDescription
                Haptics.warning()
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func applyImport() {
        guard let pendingImport else { return }
        store.replaceAll(with: pendingImport)
        self.pendingImport = nil
        Haptics.success()
        toast = ToastMessage(title: "Backup imported",
                             detail: "A copy of your previous data was kept on this device.")
    }
}
