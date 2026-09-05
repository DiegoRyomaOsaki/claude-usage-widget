import Foundation

/// File locations shared by the container app and the widget extension.
///
/// The extension is sandboxed, so its `Application Support` resolves inside
/// `~/Library/Containers/io.diegopuerto.claudeusage.widget/Data`. The container app is
/// not sandboxed, so it writes the payload to *both* locations and the extension reads
/// whichever it can see. That avoids an App Group, which would require a paid signing
/// identity — the same trick the Scrybe deploy widget uses.
enum Paths {
    static let widgetBundleID = "io.diegopuerto.claudeusage.widget"
    static let folderName = "ClaudeUsageWidget"

    /// Application Support of whichever process is asking (container-relative when sandboxed).
    static var localSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    static var statusFile: URL { localSupport.appendingPathComponent("status.json") }
    static var logFile: URL { localSupport.appendingPathComponent("refresh.log") }

    /// The extension's sandbox container, as seen from the unsandboxed app.
    static var widgetContainerSupport: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers/\(widgetBundleID)/Data/Library/Application Support")
            .appendingPathComponent(folderName, isDirectory: true)
    }

    static var statusWriteTargets: [URL] {
        [statusFile, widgetContainerSupport.appendingPathComponent("status.json")]
    }

    /// Every place the payload might be, most specific first. Inside the sandbox the
    /// first entry is the container copy; the second is the app's own, unreachable there
    /// but correct when this code runs in the container app.
    static var statusReadCandidates: [URL] {
        var urls = [statusFile]
        let unsandboxed = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/\(folderName)/status.json")
        if unsandboxed != statusFile { urls.append(unsandboxed) }
        return urls
    }

    /// Claude Code's transcript root. Every conversation is one JSONL file under a
    /// directory named after the project path.
    static var claudeProjects: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects", isDirectory: true)
    }
}

enum StatusStore {
    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func read() -> UsagePayload? {
        for url in Paths.statusReadCandidates {
            guard let data = try? Data(contentsOf: url),
                  let payload = try? decoder.decode(UsagePayload.self, from: data) else { continue }
            return payload
        }
        return nil
    }

    static func write(_ payload: UsagePayload) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try enc.encode(payload)

        var lastError: Error?
        var wroteAny = false
        for url in Paths.statusWriteTargets {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                wroteAny = true
            } catch {
                // The extension's container only exists once it has run once. Not fatal.
                lastError = error
            }
        }
        if !wroteAny, let lastError { throw lastError }
    }
}
