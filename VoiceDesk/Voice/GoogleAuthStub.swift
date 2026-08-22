import Foundation
import Observation

/// Google sign-in for Gmail / Calendar / Tasks. Slice 2 wires real OAuth.
@MainActor
protocol GoogleAuthServicing: AnyObject {
    var isConnected: Bool { get }
    func connect() async
    func disconnect()
}

@MainActor
@Observable
final class StubGoogleAuth: GoogleAuthServicing {
    private(set) var isConnected = false

    func connect() async {
        // TODO: Google OAuth (openid email + Gmail + Calendar + Tasks). Store tokens in Keychain.
        try? await Task.sleep(for: .milliseconds(450))
        isConnected = true
    }

    func disconnect() {
        isConnected = false
    }
}
