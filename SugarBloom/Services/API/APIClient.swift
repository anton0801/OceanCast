//
//  APIClient.swift
//  Ocean Cast
//
//  Every call carries a bearer token. When the access token expires the client
//  refreshes once — serialised, so ten parallel calls cause one refresh, not ten
//  — and retries. Anything else is surfaced to the caller as a typed APIError.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Serialises token refreshes across concurrent requests.
actor RefreshCoordinator {
    private var inFlight: Task<APITokens, Error>?

    func refresh(using work: @escaping @Sendable () async throws -> APITokens) async throws -> APITokens {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { try await work() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}

@MainActor
final class APIClient {
    static let shared = APIClient()

    nonisolated static let defaultBaseURL = "https://ocean-cast.space"

    nonisolated static func resolveBaseURL() -> URL? {
        let stored = UserDefaults.standard.string(forKey: "api.baseURL")
        let raw = (stored ?? defaultBaseURL).trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw.hasSuffix("/") ? String(raw.dropLast()) : raw)
    }

    private let session: URLSession
    private let coordinator = RefreshCoordinator()

    var onSessionLost: (() -> Void)?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        // No credential storage, no cookies: the bearer token is the only state.
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    // MARK: - Configuration

    var baseURLString: String {
        get { UserDefaults.standard.string(forKey: "api.baseURL") ?? Self.defaultBaseURL }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespaces), forKey: "api.baseURL") }
    }

    var baseURL: URL? {
        let raw = baseURLString.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw.hasSuffix("/") ? String(raw.dropLast()) : raw)
    }

    var isConfigured: Bool { baseURL != nil }

    // MARK: - Tokens

    private(set) var accessToken: String? {
        get { KeychainStore.get(.accessToken) }
        set { KeychainStore.set(newValue, for: .accessToken) }
    }

    private(set) var refreshToken: String? {
        get { KeychainStore.get(.refreshToken) }
        set { KeychainStore.set(newValue, for: .refreshToken) }
    }

    var hasSession: Bool { refreshToken != nil }

    func store(_ tokens: APITokens) {
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
        KeychainStore.set(APICoder.string(from: Date().addingTimeInterval(TimeInterval(tokens.expiresIn))),
                          for: .accessExpiry)
        KeychainStore.set(APICoder.string(from: Date().addingTimeInterval(TimeInterval(tokens.refreshExpiresIn))),
                          for: .refreshExpiry)
    }

    func clearTokens() {
        KeychainStore.clearAll()
    }

    // MARK: - Requests

    enum Method: String {
        case get = "GET", post = "POST", patch = "PATCH", put = "PUT", delete = "DELETE"
    }

    @discardableResult
    func send<Response: Decodable>(
        _ method: Method,
        _ path: String,
        body: (any Encodable)? = nil,
        authenticated: Bool = true,
        idempotencyKey: String? = nil,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await perform(method, path, body: body, authenticated: authenticated,
                                     idempotencyKey: idempotencyKey, allowRefresh: true)
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        do {
            return try APICoder.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding("The server sent something this app could not read. (\(error))")
        }
    }

    private func perform(
        _ method: Method,
        _ path: String,
        body: (any Encodable)?,
        authenticated: Bool,
        idempotencyKey: String?,
        allowRefresh: Bool
    ) async throws -> Data {
        guard let baseURL else { throw APIError.notConfigured() }
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw APIError.decoding("Invalid request path.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(Self.deviceName, forHTTPHeaderField: "X-Device-Name")
        request.setValue(Self.platform, forHTTPHeaderField: "X-Platform")
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try APICoder.encoder.encode(AnyEncodableRecord(body))
        }
        if authenticated {
            guard let token = accessToken else {
                throw APIError(status: 401, code: "missing_token",
                               message: "You are not signed in.", fields: [:])
            }
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw Self.mapURLError(error)
        } catch {
            throw APIError.offline(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("The server sent an unexpected response.")
        }
        if (200..<300).contains(http.statusCode) {
            return data
        }

        let apiError = APIError.decode(status: http.statusCode, data: data)

        // One transparent refresh, then retry the original call.
        if apiError.isExpiredAccessToken, allowRefresh, authenticated, refreshToken != nil {
            _ = try await refreshSession()
            return try await perform(method, path, body: body, authenticated: authenticated,
                                     idempotencyKey: idempotencyKey, allowRefresh: false)
        }
        if apiError.requiresSignIn {
            clearTokens()
            onSessionLost?()
        }
        throw apiError
    }

    @discardableResult
    func refreshSession() async throws -> APITokens {
        guard let refresh = refreshToken else {
            throw APIError(status: 401, code: "missing_token", message: "You are not signed in.", fields: [:])
        }

        let tokens = try await coordinator.refresh { [weak self] in
            guard let self else { throw APIError.offline("The app is shutting down.") }
            let response: RefreshEnvelope = try await self.sendRefresh(refresh)
            return response.auth
        }
        store(tokens)
        return tokens
    }

    private func sendRefresh(_ refreshToken: String) async throws -> RefreshEnvelope {
        let data = try await perform(.post, "/v1/auth/refresh",
                                     body: ["refreshToken": refreshToken],
                                     authenticated: false,
                                     idempotencyKey: nil,
                                     allowRefresh: false)
        do {
            return try APICoder.decoder.decode(RefreshEnvelope.self, from: data)
        } catch {
            throw APIError.decoding("The refresh response could not be read.")
        }
    }

    private struct RefreshEnvelope: Decodable {
        var auth: APITokens
    }

    // MARK: - Helpers

    private static func mapURLError(_ error: URLError) -> APIError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .offline("No connection. Your data is safe on this device and will sync later.")
        case .timedOut:
            return .offline("The server did not answer in time. Nothing was changed.")
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return APIError(status: 0, code: "unreachable",
                            message: "That server address cannot be reached. Check it in Settings.",
                            fields: [:])
        case .appTransportSecurityRequiresSecureConnection, .secureConnectionFailed,
             .serverCertificateUntrusted, .serverCertificateHasBadDate:
            return APIError(status: 0, code: "insecure_connection",
                            message: "The connection is not secure, so it was refused. Use an HTTPS address.",
                            fields: [:])
        default:
            return .offline(error.localizedDescription)
        }
    }

    static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }

    static var platform: String {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipados" : "ios"
        #elseif os(macOS)
        return "macos"
        #else
        return "unknown"
        #endif
    }
}

struct EmptyResponse: Decodable {}
