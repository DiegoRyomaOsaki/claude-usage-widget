import Foundation
import Security

/// Reads Claude Code's own OAuth token out of the login Keychain.
///
/// This is what lets the widget work with zero setup: no cookie to paste, no token to
/// create. Claude Code stores its credentials in a generic-password item named
/// `Claude Code-credentials`, refreshing the access token as it goes, so reading the item
/// on every poll yields a token that is fresh for as long as Claude Code is in use.
///
/// Nothing is ever written back. Rotating the refresh token ourselves would invalidate
/// the copy Claude Code holds and sign the user out of their own CLI, so an expired token
/// surfaces as a message telling them to open Claude Code instead.
enum Credentials {
    static let service = "Claude Code-credentials"

    struct OAuth {
        var accessToken: String
        var expiresAt: Date?
        var subscriptionType: String?
        var rateLimitTier: String?

        var isExpired: Bool {
            guard let expiresAt else { return false }
            return expiresAt <= Date()
        }
    }

    enum Failure: LocalizedError {
        case notFound
        case needsAuthorization
        case unreadable

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "No encontré las credenciales de Claude Code. Inicia sesión con `claude` y vuelve a actualizar."
            case .needsAuthorization:
                return "Falta autorizar el acceso al llavero. Abre el menú de Claude Usage y pulsa Actualizar ahora."
            case .unreadable:
                return "El llavero devolvió un formato inesperado. Vuelve a iniciar sesión en Claude Code."
            }
        }
    }

    /// - Parameter allowInteraction: whether macOS may put an authorization dialog on
    ///   screen. The item belongs to Claude Code, so the first read from this app prompts
    ///   for permission. That is fine when the user just clicked Refresh, and a hang when
    ///   `launchd` runs `--refresh` in a session with nobody watching — the process would
    ///   sit on the dialog forever, once every five minutes. Background refreshes
    ///   therefore ask for no interaction and fail fast instead.
    static func load(allowInteraction: Bool = true) throws -> OAuth {
        if !allowInteraction { SecKeychainSetUserInteractionAllowed(false) }
        defer { if !allowInteraction { SecKeychainSetUserInteractionAllowed(true) } }

        guard let raw = rawItem(allowInteraction: allowInteraction) else {
            throw allowInteraction ? Failure.notFound : Failure.needsAuthorization
        }
        guard let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw Failure.unreadable
        }
        // `expiresAt` is milliseconds since the epoch.
        var expiry: Date?
        if let ms = oauth["expiresAt"] as? Double { expiry = Date(timeIntervalSince1970: ms / 1000) }

        return OAuth(accessToken: token,
                     expiresAt: expiry,
                     subscriptionType: oauth["subscriptionType"] as? String,
                     rateLimitTier: oauth["rateLimitTier"] as? String)
    }

    /// Keychain Services first; the `security` tool as a fallback.
    ///
    /// The item's ACL names the binaries allowed to read it silently. A freshly built,
    /// ad-hoc-signed app is not among them, so `SecItemCopyMatching` can come back with
    /// `errSecInteractionNotAllowed` in a background refresh with no UI to prompt in.
    /// `/usr/bin/security` is a system binary the user has usually already granted, so
    /// trying it second turns that failure into a working read often enough to matter.
    private static func rawItem(allowInteraction: Bool) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, !data.isEmpty {
            return data
        }

        // Some versions store the item under the user's account name; retry unscoped.
        query[kSecAttrService as String] = service
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        result = nil
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, !data.isEmpty {
            return data
        }

        return securityTool(allowInteraction: allowInteraction)
    }

    /// The `security` tool can raise the same dialog, so a background read caps how long
    /// it may take before being killed.
    private static func securityTool(allowInteraction: Bool) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        if !allowInteraction {
            let deadline = DispatchTime.now() + .seconds(10)
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            if finished.wait(timeout: deadline) == .timedOut {
                process.terminate()
                return nil
            }
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }
}
