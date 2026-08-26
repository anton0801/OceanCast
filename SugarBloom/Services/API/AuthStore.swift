import Foundation
import Observation

@MainActor
@Observable
final class AuthStore {
    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(APIUser)

        var user: APIUser? {
            if case .signedIn(let user) = self { return user }
            return nil
        }
    }

    private(set) var state: State = .unknown
    private(set) var sessions: [APISession] = []
    private(set) var records: [String: Int] = [:]
    private(set) var serverHousehold: APIHousehold?
    var isBusy = false
    var lastError: APIError?

    @ObservationIgnored private let client = APIClient.shared

    var isSignedIn: Bool { state.user != nil }

    init() {
        client.onSessionLost = { [weak self] in
            guard let self else { return }
            self.state = .signedOut
            self.sessions = []
            self.lastError = APIError(status: 401, code: "token_revoked",
                                      message: "Your session ended. Sign in again to keep syncing.",
                                      fields: [:])
        }
    }

    // MARK: - Session lifecycle

    func restore() async {
        guard client.isConfigured, client.hasSession else {
            state = .signedOut
            return
        }
        do {
            let profile: APIProfileResponse = try await client.send(.get, "/v1/profile")
            apply(profile)
        } catch let error as APIError {
            if error.requiresSignIn {
                client.clearTokens()
                state = .signedOut
            } else {
                // Offline at launch is not a sign-out; keep the session.
                state = client.hasSession ? state : .signedOut
                if case .unknown = state { state = .signedOut }
                lastError = error
            }
        } catch {
            state = .signedOut
        }
    }

    func register(email: String, password: String, displayName: String) async throws {
        try await run {
            let response: APIAuthResponse = try await self.client.send(
                .post, "/v1/auth/register",
                body: ["email": email, "password": password, "displayName": displayName],
                authenticated: false
            )
            self.client.store(response.auth)
            self.state = .signedIn(response.user)
            self.linkDeviceIfPossible()
        }
    }

    func signIn(email: String, password: String) async throws {
        try await run {
            let response: APIAuthResponse = try await self.client.send(
                .post, "/v1/auth/login",
                body: ["email": email, "password": password],
                authenticated: false
            )
            self.client.store(response.auth)
            self.state = .signedIn(response.user)
            self.linkDeviceIfPossible()
        }
    }

    func signOut() async {
        isBusy = true
        defer { isBusy = false }
        // Best effort: even if the call fails, the local session must end.
        _ = try? await client.send(.post, "/v1/auth/logout", as: EmptyResponse.self)
        client.clearTokens()
        state = .signedOut
        sessions = []
        records = [:]
        serverHousehold = nil
    }

    func signOutEverywhere() async throws {
        try await run {
            _ = try await self.client.send(.post, "/v1/auth/logout-all", as: EmptyResponse.self)
            self.client.clearTokens()
            self.state = .signedOut
            self.sessions = []
        }
    }

    // MARK: - Profile

    func loadProfile() async {
        guard isSignedIn else { return }
        do {
            let profile: APIProfileResponse = try await client.send(.get, "/v1/profile")
            apply(profile)
        } catch let error as APIError {
            lastError = error
        } catch {}
    }

    func loadSessions() async {
        guard isSignedIn else { return }
        do {
            let response: APISessionsResponse = try await client.send(.get, "/v1/auth/sessions")
            sessions = response.sessions
        } catch let error as APIError {
            lastError = error
        } catch {}
    }

    func revokeSession(id: String) async throws {
        try await run {
            _ = try await self.client.send(.delete, "/v1/auth/sessions/\(id)", as: EmptyResponse.self)
            self.sessions.removeAll { $0.id == id }
        }
    }

    func updateDisplayName(_ name: String) async throws {
        try await run {
            struct Envelope: Decodable { var user: APIUser }
            let response: Envelope = try await self.client.send(
                .patch, "/v1/profile", body: ["displayName": name]
            )
            self.state = .signedIn(response.user)
        }
    }

    func changeEmail(_ email: String, password: String) async throws {
        try await run {
            struct Envelope: Decodable { var user: APIUser }
            let response: Envelope = try await self.client.send(
                .patch, "/v1/profile",
                body: ["email": email, "currentPassword": password]
            )
            self.state = .signedIn(response.user)
        }
    }

    func changePassword(current: String, new: String) async throws -> Int {
        var revoked = 0
        try await run {
            struct Envelope: Decodable { var revokedSessions: Int }
            let response: Envelope = try await self.client.send(
                .post, "/v1/profile/password",
                body: ["currentPassword": current, "newPassword": new]
            )
            revoked = response.revokedSessions
        }
        return revoked
    }

    /// Deletes the account on the server. Local data is handled separately, so
    /// the user is asked explicitly what should happen to it.
    func deleteAccount(password: String) async throws -> [String: Int] {
        var removed: [String: Int] = [:]
        try await run {
            struct Envelope: Decodable {
                var status: String
                var deletedRecords: [String: Int]?
            }
            let response: Envelope = try await self.client.send(
                .delete, "/v1/profile",
                body: ["password": password, "confirm": "DELETE"]
            )
            removed = response.deletedRecords ?? [:]
            self.client.clearTokens()
            self.state = .signedOut
            self.sessions = []
            self.records = [:]
            self.serverHousehold = nil
        }
        return removed
    }

    // MARK: - Helpers

    private func apply(_ profile: APIProfileResponse) {
        state = .signedIn(profile.user)
        records = profile.records ?? [:]
        serverHousehold = profile.household
        linkDeviceIfPossible()
    }

    /// Best-effort: tie this device key to the signed-in account so the server
    /// knows which accounts were seen on which install.
    private func linkDeviceIfPossible() {
        let ref = LiveAttributionProvider().deviceRef()
        Task { await BeaconClient().link(ref: ref) }
    }

    private func run(_ work: @escaping () async throws -> Void) async throws {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch let error as APIError {
            lastError = error
            throw error
        } catch {
            let wrapped = APIError.offline(error.localizedDescription)
            lastError = wrapped
            throw wrapped
        }
    }
}
