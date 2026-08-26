//
//  BeaconClient.swift
//  Ocean Cast
//
//  Talks to the beacon endpoints. The body carries app-specific keys and is
//  AES-256-GCM sealed when a key is configured; otherwise it is sent in the
//  clear (the server accepts that outside production). The resolve response
//  carries the gate: an `analytics-service` header plus an authorized flag.
//

import Foundation

struct BeaconFields {
    var ref: String
    var os: String?
    var bundle: String?
    var firebaseProject: String?
    var store: String?
    var push: String?
    var locale: String?
    var idfa: String?
    var conversion: Data?
}

struct BeaconGate {
    var authorized: Bool = false
    var account: String?
    var analyticsURL: URL?
}

struct BeaconClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    private var baseURL: URL? { APIClient.resolveBaseURL() }

    // MARK: - Public calls

    /// The first, "collect" request — facts available the moment the app opens.
    func collect(_ fields: BeaconFields) async {
        _ = try? await post(BeaconConfig.collectPath, fields: fields)
    }

    /// The final, gate request. Its response opens the splash.
    func resolve(_ fields: BeaconFields) async -> BeaconGate {
        guard let (data, response) = try? await post(BeaconConfig.resolvePath, fields: fields) else {
            return BeaconGate()
        }

        var gate = BeaconGate()
        if let header = response.value(forHTTPHeaderField: BeaconConfig.analyticsServiceHeader),
           let url = URL(string: header.trimmingCharacters(in: .whitespaces)),
           !header.isEmpty {
            gate.analyticsURL = url
        }
        if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            gate.authorized = (body["authorized"] as? Bool) ?? false
            gate.account = body["account"] as? String
        }
        return gate
    }

    /// A stand-alone push-token update, sent through the collect endpoint.
    func reportPush(ref: String, token: String) async -> Bool {
        let fields = BeaconFields(ref: ref, push: token)
        let result = try? await post(BeaconConfig.collectPath, fields: fields)
        guard let response = result?.1 else { return false }
        return (200..<300).contains(response.statusCode)
    }

    /// Ties the signed-in account to the device key. Authenticated, so it goes
    /// through the shared client (token + refresh handling included).
    @MainActor
    func link(ref: String) async {
        _ = try? await APIClient.shared.send(.post, BeaconConfig.linkPath,
                                             body: ["ref": ref], as: EmptyResponse.self)
    }

    // MARK: - Transport

    private func post(_ path: String, fields: BeaconFields) async throws -> (Data, HTTPURLResponse)? {
        guard let baseURL, let url = URL(string: baseURL.absoluteString + path),
              let body = body(from: fields) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        return (data, http)
    }

    private func body(from fields: BeaconFields) -> Data? {
        var inner: [String: Any] = [BeaconConfig.Wire.ref: fields.ref]
        put(&inner, BeaconConfig.Wire.os, fields.os)
        put(&inner, BeaconConfig.Wire.bundle, fields.bundle)
        put(&inner, BeaconConfig.Wire.firebaseProject, fields.firebaseProject)
        put(&inner, BeaconConfig.Wire.store, fields.store)
        put(&inner, BeaconConfig.Wire.push, fields.push)
        put(&inner, BeaconConfig.Wire.locale, fields.locale)
        put(&inner, BeaconConfig.Wire.idfa, fields.idfa)
        if let conversion = fields.conversion,
           let object = try? JSONSerialization.jsonObject(with: conversion),
           JSONSerialization.isValidJSONObject(object) {
            inner[BeaconConfig.Wire.conversion] = object
        }

        guard let plain = try? JSONSerialization.data(withJSONObject: inner) else { return nil }

        if PayloadCrypto.isConfigured, let sealed = PayloadCrypto.seal(plain) {
            return try? JSONSerialization.data(withJSONObject: [BeaconConfig.Wire.envelope: sealed])
        }
        return plain
    }

    private func put(_ dict: inout [String: Any], _ key: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        dict[key] = value
    }
}
