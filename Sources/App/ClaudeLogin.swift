import AppKit

/// Runs Claude Code's own `claude auth login` in a Terminal window.
///
/// The widget reads the token Claude Code keeps, and that token lasts about eight hours
/// unless Claude Code is running to renew it. Rather than implement an OAuth flow of its
/// own — which would mean posing as Claude Code's OAuth client — the app hands the login to
/// Claude Code, which writes a fresh token where the widget already looks for it.
///
/// The command goes through a `.command` file, which Terminal opens and runs by itself;
/// driving Terminal over AppleScript instead would cost an Automation permission prompt.
/// When the login succeeds the script opens `claudeusage://refresh`, so the widget picks
/// the new token up right away instead of on the next poll.
enum ClaudeLogin {
    static func open() {
        let script = """
        #!/bin/zsh -l
        # Abierto por Claude Usage. Se puede cerrar esta ventana al terminar.
        clear
        echo "Iniciando sesión en Claude Code…"
        echo
        if \(shellQuoted(claudeExecutable)) auth login; then
          open -g "claudeusage://refresh"
          echo
          echo "Listo. El widget ya tiene la sesión nueva; puedes cerrar esta ventana."
        else
          echo
          echo "El login no se completó. Vuelve a intentarlo desde el menú de Claude Usage."
        fi

        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-usage-login.command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            Refresher.log("no pude preparar el login: \(error.localizedDescription)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// The installer puts `claude` in `~/.local/bin`, which a login shell started from a
    /// `.command` file does not always have on its PATH; the other paths cover Homebrew
    /// and the older npm-local install.
    private static var claudeExecutable: String {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "claude"
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
