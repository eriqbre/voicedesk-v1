import Foundation
import Observation
import UIKit
import VoiceDeskLogic

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

enum GoogleSignInError: LocalizedError {
    case missingClientID
    case noPresenter
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return GoogleAuthSnapshot.missingClientIDCopy
        case .noPresenter:
            return "Couldn’t present Google Sign-In. Try again from the conversation screen."
        case .cancelled:
            return "Google Sign-In was cancelled."
        case .failed(let detail):
            return detail
        }
    }
}

@MainActor
protocol GoogleAuthBackend: AnyObject {
    func signIn() async throws -> (email: String, token: String)
    func signOut()
    func restore() async -> (email: String, token: String)?
    func handleURL(_ url: URL) -> Bool
}

/// Observable Google session. Missing client ID stays signed-out and says so — never fakes connected.
@MainActor
@Observable
final class GoogleSession {
    private(set) var snapshot: GoogleAuthSnapshot
    private(set) var accessToken: String?
    private let backend: (any GoogleAuthBackend)?

    var isConnected: Bool { snapshot.isConnected }
    var setupNeeded: Bool { snapshot.setupNeeded }

    init(backend: (any GoogleAuthBackend)?, clientIDConfigured: Bool) {
        self.backend = backend
        if clientIDConfigured {
            self.snapshot = .signedOut
        } else {
            self.snapshot = GoogleAuthSnapshot.reduce(.signedOut, .clientIDMissing)
        }
    }

    static func makeForLaunch() -> GoogleSession {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            return GoogleSession(backend: MockGoogleAuthBackend(), clientIDConfigured: true)
        }
        guard let clientID = VoiceDeskSecrets.googleClientID else {
            return GoogleSession(backend: nil, clientIDConfigured: false)
        }
        return GoogleSession(backend: GIDGoogleAuthBackend(clientID: clientID), clientIDConfigured: true)
    }

    static func mock(
        connected: Bool = false,
        email: String = "ada@example.com",
        token: String = "mock-token"
    ) -> GoogleSession {
        let backend = MockGoogleAuthBackend(email: email, token: token)
        let session = GoogleSession(backend: backend, clientIDConfigured: true)
        if connected {
            session.accessToken = token
            session.snapshot = GoogleAuthSnapshot.reduce(.signedOut, .connectSucceeded(email: email))
        }
        return session
    }

    static func missingClientID() -> GoogleSession {
        GoogleSession(backend: nil, clientIDConfigured: false)
    }

    func restoreSession() async {
        guard let backend, !snapshot.setupNeeded else { return }
        if let restored = await backend.restore() {
            accessToken = restored.token
            snapshot = GoogleAuthSnapshot.reduce(snapshot, .connectSucceeded(email: restored.email))
        }
    }

    func connect() async {
        if snapshot.setupNeeded || backend == nil {
            snapshot = GoogleAuthSnapshot.reduce(snapshot, .clientIDMissing)
            return
        }
        snapshot = GoogleAuthSnapshot.reduce(snapshot, .connectStarted)
        do {
            let result = try await backend!.signIn()
            accessToken = result.token
            snapshot = GoogleAuthSnapshot.reduce(snapshot, .connectSucceeded(email: result.email))
        } catch {
            accessToken = nil
            snapshot = GoogleAuthSnapshot.reduce(snapshot, .connectFailed(error.localizedDescription))
        }
    }

    func disconnect() {
        backend?.signOut()
        accessToken = nil
        snapshot = GoogleAuthSnapshot.reduce(snapshot, .disconnect)
    }

    func handleURL(_ url: URL) -> Bool {
        backend?.handleURL(url) ?? false
    }
}

@MainActor
final class MockGoogleAuthBackend: GoogleAuthBackend {
    var email: String
    var token: String
    var failWith: String?
    var restoreOnLaunch = false
    private(set) var signedIn = false

    init(email: String = "ada@example.com", token: String = "mock-token") {
        self.email = email
        self.token = token
    }

    func signIn() async throws -> (email: String, token: String) {
        if let failWith {
            throw GoogleSignInError.failed(failWith)
        }
        signedIn = true
        return (email, token)
    }

    func signOut() {
        signedIn = false
    }

    func restore() async -> (email: String, token: String)? {
        restoreOnLaunch ? (email, token) : nil
    }

    func handleURL(_ url: URL) -> Bool {
        url.scheme?.hasPrefix("com.googleusercontent.apps") == true
    }
}

#if canImport(GoogleSignIn)
@MainActor
final class GIDGoogleAuthBackend: GoogleAuthBackend {
    init(clientID: String) {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    func signIn() async throws -> (email: String, token: String) {
        guard let presenter = Self.presenter() else {
            throw GoogleSignInError.noPresenter
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: GoogleScopes.readScopes
            )
            return try Self.credentials(from: result.user)
        } catch {
            let ns = error as NSError
            if ns.domain == "com.google.GIDSignIn", ns.code == -5 {
                throw GoogleSignInError.cancelled
            }
            throw GoogleSignInError.failed(error.localizedDescription)
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        GIDSignIn.sharedInstance.disconnect { _ in }
    }

    func restore() async -> (email: String, token: String)? {
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            return try Self.credentials(from: user)
        } catch {
            return nil
        }
    }

    func handleURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private static func credentials(from user: GIDGoogleUser) throws -> (email: String, token: String) {
        let email = user.profile?.email ?? ""
        let token = user.accessToken.tokenString
        guard !email.isEmpty, !token.isEmpty else {
            throw GoogleSignInError.failed("Google returned an empty account or token.")
        }
        return (email, token)
    }

    private static func presenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
#else
@MainActor
final class GIDGoogleAuthBackend: GoogleAuthBackend {
    init(clientID: String) {
        _ = clientID
    }

    func signIn() async throws -> (email: String, token: String) {
        throw GoogleSignInError.failed("Google Sign-In SDK is not linked in this build.")
    }

    func signOut() {}

    func restore() async -> (email: String, token: String)? { nil }

    func handleURL(_ url: URL) -> Bool { false }
}
#endif
