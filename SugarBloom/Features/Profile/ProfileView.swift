//
//  ProfileView.swift
//  Ocean Cast
//
//  The account: who is signed in, which devices hold a session, sync state,
//  password, sign-out and deletion.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(AppStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.dismiss) private var dismiss

    @State private var showAuth = false
    @State private var displayName = ""
    @State private var newEmail = ""
    @State private var emailPassword = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var deletePassword = ""
    @State private var deleteStage = 0
    @State private var alsoEraseLocal = false
    @State private var toast: ToastMessage?
    @State private var showRejections = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let user = auth.state.user {
                        header(user)
                        syncCard
                        profileCard(user)
                        sessionsCard
                        passwordCard
                        dangerCard
                    } else {
                        signedOutState
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(OceanBackground(tint: Ocean.tide))
            .toastHost($toast)
            .navigationTitle("Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $showAuth) { AuthView() }
            .task {
                displayName = auth.state.user?.displayName ?? ""
                await auth.loadProfile()
                await auth.loadSessions()
            }
            // The session may still be restoring when this screen opens; fill the
            // field as soon as the user is known, without overwriting typing.
            .onChange(of: auth.state) { _, newState in
                if displayName.isEmpty { displayName = newState.user?.displayName ?? "" }
            }
        }
    }

    // MARK: - Signed out

    private var signedOutState: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(eyebrow: "Account",
                         title: "Working on this device only",
                         subtitle: "Everything you have recorded is stored locally and works without an account. Sign in to keep a second device in step.",
                         tint: Ocean.tide)

            WaveCard(tint: Ocean.turquoise) {
                VStack(alignment: .leading, spacing: 10) {
                    row("Records on this device", "\(store.data.batches.count) batch(es), \(store.data.meals.count) meal(s)")
                    row("Server", APIClient.shared.baseURLString.isEmpty ? "not set" : APIClient.shared.baseURLString)
                    row("Sync", "off")
                }
            }

            OceanButton(title: "Sign in or create an account", symbol: "person.crop.circle.badge.plus") {
                showAuth = true
            }

            InfoNote(text: "Nothing leaves this device until you sign in. After that, only your own household is sent, over HTTPS, authorised by a token stored in the Keychain.",
                     symbol: "lock.shield.fill", tint: Ocean.turquoise)
        }
    }

    // MARK: - Signed in

    private func header(_ user: APIUser) -> some View {
        WaveCard(tint: Ocean.tide, padding: 18) {
            HStack(spacing: 14) {
                FloatDisc(symbol: "person.fill", tint: Ocean.tide, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(user.displayName).font(OceanFont.title(20)).foregroundStyle(Ocean.ink)
                    Text(user.email).font(OceanFont.caption(12.5)).foregroundStyle(Ocean.inkSoft)
                    if let created = user.createdAt {
                        Text("Member since \(DateFormat.day(created))")
                            .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkFaint)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var syncCard: some View {
        SectionCard(title: "Sync", symbol: "arrow.triangle.2.circlepath", tint: Ocean.turquoise) {
            VStack(alignment: .leading, spacing: 12) {
                statusRow

                row("Last sync", store.data.lastSyncedAt.map(DateFormat.stamp) ?? "never")
                row("Server", APIClient.shared.baseURLString)
                row("Pending deletes", "\(store.data.tombstones.count)")
                if !auth.records.isEmpty {
                    let total = auth.records.values.reduce(0, +)
                    row("Records on the server", "\(total)")
                }

                if !network.isOnline {
                    OfflineBanner(lastUpdated: store.data.lastSyncedAt)
                }

                OceanButton(title: "Sync now", symbol: "arrow.clockwise",
                            kind: .secondary, tint: Ocean.turquoise, isBusy: sync.isSyncing) {
                    Task {
                        await sync.syncNow(store: store, auth: auth)
                        await auth.loadProfile()
                        if case .success = sync.status {
                            toast = ToastMessage(title: "Sync complete",
                                                 detail: "Pulled \(sync.lastPulledCounts.values.reduce(0, +)) record(s).")
                        }
                    }
                }

                if !sync.conflicts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("\(sync.conflicts.count) record(s) were changed on another device first",
                              systemImage: "arrow.triangle.branch")
                            .font(OceanFont.caption(12)).foregroundStyle(Ocean.tide)
                        Text("The other device's version was kept and is now on this one too. Nothing was merged silently.")
                            .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Ocean.tide.opacity(0.10)))
                }

                if !sync.rejections.isEmpty {
                    Button {
                        withAnimation(OceanMotion.pop) { showRejections.toggle() }
                    } label: {
                        Label("\(sync.rejections.count) record(s) were not accepted",
                              systemImage: showRejections ? "chevron.up" : "chevron.down")
                            .font(OceanFont.caption(12)).foregroundStyle(Ocean.coral)
                    }
                    .buttonStyle(.plain)

                    if showRejections {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(sync.rejections.enumerated()), id: \.offset) { _, rejection in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(rejection.resource) · \(rejection.id ?? "no id")")
                                        .font(OceanFont.caption(11)).foregroundStyle(Ocean.ink)
                                    Text(rejection.reason)
                                        .font(OceanFont.caption(10.5)).foregroundStyle(Ocean.inkSoft)
                                }
                            }
                            Text("These stay on this device and are retried on the next sync.")
                                .font(OceanFont.caption(10.5)).foregroundStyle(Ocean.inkFaint)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Ocean.coral.opacity(0.10)))
                    }
                }
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            let (symbol, tint, text) = statusPresentation
            FloatDisc(symbol: symbol, tint: tint, size: 30)
            Text(text).font(OceanFont.headline(14)).foregroundStyle(Ocean.ink)
            Spacer()
        }
    }

    private var statusPresentation: (String, Color, String) {
        switch sync.status {
        case .idle: return ("pause.circle.fill", Ocean.inkFaint, "Not synced yet in this session")
        case .syncing: return ("arrow.triangle.2.circlepath", Ocean.turquoise, "Syncing…")
        case .success(let date): return ("checkmark.circle.fill", Ocean.turquoise, "Synced at \(DateFormat.stamp(date))")
        case .failed(let message): return ("exclamationmark.triangle.fill", Ocean.coral, message)
        case .offline: return ("wifi.slash", Ocean.coral, "Offline — local records are unaffected")
        case .signedOut: return ("person.slash.fill", Ocean.coral, "Signed out")
        }
    }

    private func profileCard(_ user: APIUser) -> some View {
        SectionCard(title: "Profile", symbol: "person.text.rectangle.fill", tint: Ocean.tide) {
            VStack(alignment: .leading, spacing: 14) {
                OceanTextField(label: "Display name", text: $displayName)
                OceanButton(title: "Save name", kind: .secondary, tint: Ocean.tide,
                            fullWidth: false, compact: true) {
                    Task {
                        do {
                            try await auth.updateDisplayName(displayName)
                            toast = ToastMessage(title: "Name updated")
                        } catch let error as APIError {
                            toast = ToastMessage(kind: .warning, title: "Not saved", detail: error.message)
                        } catch {}
                    }
                }

                Divider().overlay(Ocean.hairline)

                OceanTextField(label: "New email", placeholder: user.email, keyboard: .email, text: $newEmail)
                SecureRow(label: "Current password", text: $emailPassword)
                OceanButton(title: "Change email", kind: .secondary, tint: Ocean.tide,
                            fullWidth: false, compact: true) {
                    Task {
                        do {
                            try await auth.changeEmail(newEmail, password: emailPassword)
                            newEmail = ""
                            emailPassword = ""
                            toast = ToastMessage(title: "Email updated")
                        } catch let error as APIError {
                            toast = ToastMessage(kind: .warning, title: "Not changed", detail: error.message)
                        } catch {}
                    }
                }
                Text("Changing the email needs your password — it is a credential, not a preference.")
                    .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
            }
        }
    }

    private var sessionsCard: some View {
        SectionCard(title: "Devices", symbol: "iphone.and.arrow.forward", tint: Ocean.turquoise,
                    accessory: {
            Button {
                Task { await auth.loadSessions() }
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Ocean.turquoise)
            }
            .buttonStyle(.plain)
        }, content: {
            VStack(alignment: .leading, spacing: 10) {
                if auth.sessions.isEmpty {
                    Text("No other active session.").font(OceanFont.body(14)).foregroundStyle(Ocean.inkSoft)
                } else {
                    ForEach(auth.sessions) { session in
                        HStack(spacing: 10) {
                            FloatDisc(symbol: session.current ? "checkmark.seal.fill" : "iphone",
                                      tint: session.current ? Ocean.turquoise : Ocean.tide, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.deviceName + (session.current ? " · this device" : ""))
                                    .font(OceanFont.headline(14)).foregroundStyle(Ocean.ink)
                                Text([session.platform,
                                      session.lastUsedAt.map { "last used \(DateFormat.stamp($0))" }]
                                        .compactMap { $0 }.joined(separator: " · "))
                                    .font(OceanFont.caption(10.5)).foregroundStyle(Ocean.inkSoft)
                            }
                            Spacer()
                            if !session.current {
                                Button("End") {
                                    Task {
                                        try? await auth.revokeSession(id: session.id)
                                        toast = ToastMessage(kind: .info, title: "Session ended")
                                    }
                                }
                                .font(OceanFont.caption(12)).foregroundStyle(Ocean.coral)
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    OceanButton(title: "Sign out", symbol: "rectangle.portrait.and.arrow.right",
                                kind: .secondary, tint: Ocean.coral, fullWidth: false, compact: true) {
                        Task {
                            await auth.signOut()
                            toast = ToastMessage(kind: .info, title: "Signed out",
                                                 detail: "Your records stay on this device.")
                        }
                    }
                    OceanButton(title: "Sign out everywhere", kind: .ghost, fullWidth: false, compact: true) {
                        Task {
                            try? await auth.signOutEverywhere()
                            toast = ToastMessage(kind: .info, title: "All sessions ended")
                        }
                    }
                }
            }
        })
    }

    private var passwordCard: some View {
        SectionCard(title: "Password", symbol: "key.fill", tint: Ocean.sky) {
            VStack(alignment: .leading, spacing: 12) {
                SecureRow(label: "Current password", text: $currentPassword)
                SecureRow(label: "New password", text: $newPassword)
                OceanButton(title: "Change password", kind: .secondary, tint: Ocean.sky) {
                    Task {
                        do {
                            let revoked = try await auth.changePassword(current: currentPassword, new: newPassword)
                            currentPassword = ""
                            newPassword = ""
                            toast = ToastMessage(title: "Password changed",
                                                 detail: "\(revoked) other session(s) were signed out.")
                            await auth.loadSessions()
                        } catch let error as APIError {
                            toast = ToastMessage(kind: .warning, title: "Not changed", detail: error.message)
                        } catch {}
                    }
                }
                Text("Changing the password signs out every other device. This one stays signed in.")
                    .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
            }
        }
    }

    private var dangerCard: some View {
        SectionCard(title: "Delete account", symbol: "trash.fill", tint: Ocean.coral) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Deleting removes your account and everything stored for it on the server: household, batches, meals, shopping, prices and history. It cannot be undone.")
                    .font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: $alsoEraseLocal) {
                    Text("Also erase the copy on this device")
                        .font(OceanFont.body(14)).foregroundStyle(Ocean.ink)
                }
                .tint(Ocean.coral)
                Text(alsoEraseLocal
                     ? "This device will be emptied too — the app starts from onboarding."
                     : "Your local records stay on this device and keep working offline.")
                    .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkFaint)

                SecureRow(label: "Password", text: $deletePassword)

                if deleteStage == 0 {
                    OceanButton(title: "Delete account", symbol: "trash", kind: .danger) {
                        deleteStage = 1
                    }
                } else {
                    Text("Confirm once more. This is permanent.")
                        .font(OceanFont.caption(12)).foregroundStyle(Ocean.coral)
                    HStack(spacing: 10) {
                        OceanButton(title: "Yes, delete", kind: .danger, compact: true) {
                            Task { await deleteAccount() }
                        }
                        OceanButton(title: "Keep account", kind: .ghost, compact: true) {
                            deleteStage = 0
                        }
                    }
                }
            }
        }
    }

    private func deleteAccount() async {
        do {
            let removed = try await auth.deleteAccount(password: deletePassword)
            deletePassword = ""
            deleteStage = 0
            let total = removed.values.reduce(0, +)
            if alsoEraseLocal {
                store.eraseEverything()
            } else {
                store.mutate { data in
                    data.syncCursor = nil
                    data.lastSyncedAt = nil
                    data.tombstones.removeAll()
                }
            }
            Haptics.warning()
            toast = ToastMessage(kind: .info, title: "Account deleted",
                                 detail: "\(total) server record(s) removed.")
            dismiss()
        } catch let error as APIError {
            toast = ToastMessage(kind: .warning, title: "Not deleted", detail: error.message)
            Haptics.warning()
        } catch {
            toast = ToastMessage(kind: .warning, title: "Not deleted", detail: error.localizedDescription)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(OceanFont.caption(12)).foregroundStyle(Ocean.inkSoft)
            Spacer()
            Text(value).font(OceanFont.headline(13.5)).foregroundStyle(Ocean.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

struct SecureRow: View {
    var label: String
    @Binding var text: String
    var tint: Color = Ocean.tide

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(text: label)
            SecureField("", text: $text)
                .font(OceanFont.body(15.5))
                .textFieldStyle(.plain)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: OceanRadius.chip, style: .continuous)
                        .fill(Ocean.foam.opacity(0.8))
                        .overlay(RoundedRectangle(cornerRadius: OceanRadius.chip, style: .continuous)
                            .strokeBorder(tint.opacity(0.25), lineWidth: 1.4))
                )
        }
    }
}
