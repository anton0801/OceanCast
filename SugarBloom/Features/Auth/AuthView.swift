//
//  AuthView.swift
//  Ocean Cast
//
//  Sign in or create an account. Signing in is optional — it only turns on sync
//  between devices, and the app says so instead of pretending it is required.
//

import SwiftUI

struct AuthView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn, register
        var id: String { rawValue }
        var title: String { self == .signIn ? "Sign in" : "Create account" }
    }

    @Environment(AuthStore.self) private var auth
    @Environment(AppStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var serverURL = APIClient.shared.baseURLString
    @State private var errors: [String: String] = [:]
    @State private var generalError: String?
    @State private var toast: ToastMessage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenHeader(eyebrow: "Account",
                                 title: mode == .signIn ? "Sign in to sync" : "Create your account",
                                 subtitle: "Your kitchen already works on this device. An account adds a second device and a server backup — nothing more.",
                                 tint: Ocean.tide)

                    HStack(spacing: 8) {
                        ForEach(Mode.allCases) { option in
                            OceanChip(title: option.title, tint: Ocean.tide, isOn: mode == option) {
                                mode = option
                                errors = [:]
                                generalError = nil
                            }
                        }
                    }

                    serverCard

                    WaveCard(tint: Ocean.tide) {
                        VStack(alignment: .leading, spacing: 14) {
                            if mode == .register {
                                OceanTextField(label: "Your name", placeholder: "Alex",
                                               required: true, error: errors["displayName"],
                                               text: $displayName)
                            }
                            OceanTextField(label: "Email", placeholder: "you@example.com",
                                           required: true, error: errors["email"],
                                           keyboard: .email, text: $email)

                            VStack(alignment: .leading, spacing: 6) {
                                FieldLabel(text: "Password", required: true)
                                SecureField("at least 10 characters", text: $password)
                                    .font(OceanFont.body(15.5))
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 14).padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: OceanRadius.chip, style: .continuous)
                                            .fill(Ocean.foam.opacity(0.8))
                                            .overlay(RoundedRectangle(cornerRadius: OceanRadius.chip, style: .continuous)
                                                .strokeBorder(errors["password"] == nil
                                                              ? Ocean.tide.opacity(0.25) : Ocean.coral,
                                                              lineWidth: 1.4))
                                    )
                                if let error = errors["password"] {
                                    Label(error, systemImage: "exclamationmark.circle.fill")
                                        .font(OceanFont.caption(11.5)).foregroundStyle(Ocean.coral)
                                }
                                if mode == .register {
                                    Text("Use at least 10 characters with a letter and a digit. It is hashed with Argon2id on the server and never stored anywhere in plain text.")
                                        .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
                                }
                            }
                        }
                    }

                    if let generalError {
                        ErrorCard(title: "Not signed in", message: generalError,
                                  onDismiss: { self.generalError = nil })
                    }

                    OceanButton(title: mode.title,
                                symbol: mode == .signIn ? "arrow.right" : "sparkles",
                                isBusy: auth.isBusy) {
                        Task { await submit() }
                    }

                    InfoNote(text: "Tokens are kept in the device Keychain, every request is authorised with them, and you can end any session from Profile.",
                             symbol: "lock.shield.fill", tint: Ocean.turquoise)
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(OceanBackground(tint: Ocean.tide))
            .toastHost($toast)
            .navigationTitle("Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private var serverCard: some View {
        WaveCard(tint: Ocean.turquoise) {
            VStack(alignment: .leading, spacing: 10) {
                OceanTextField(label: "Server address", placeholder: "https://api.example.com",
                               error: errors["server"], text: $serverURL)
                Text("This app talks only to the address you set here. HTTPS is required outside a local network.")
                    .font(OceanFont.caption(11)).foregroundStyle(Ocean.inkSoft)
            }
        }
    }

    private func submit() async {
        errors = [:]
        generalError = nil

        let cleanURL = serverURL.trimmingCharacters(in: .whitespaces)
        guard !cleanURL.isEmpty, URL(string: cleanURL) != nil else {
            errors["server"] = "Enter the server address first."
            return
        }
        APIClient.shared.baseURLString = cleanURL

        if email.trimmingCharacters(in: .whitespaces).isEmpty { errors["email"] = "Email is required." }
        if password.isEmpty { errors["password"] = "Password is required." }
        if mode == .register, displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            errors["displayName"] = "Your name is required."
        }
        guard errors.isEmpty else {
            Haptics.warning()
            return
        }

        do {
            if mode == .signIn {
                try await auth.signIn(email: email, password: password)
            } else {
                try await auth.register(email: email, password: password, displayName: displayName)
            }
            password = ""
            Haptics.success()
            await sync.syncNow(store: store, auth: auth)
            dismiss()
        } catch let error as APIError {
            if error.fields.isEmpty {
                generalError = error.message
            } else {
                errors = error.fields
                generalError = error.message
            }
            Haptics.warning()
        } catch {
            generalError = error.localizedDescription
            Haptics.warning()
        }
    }
}
