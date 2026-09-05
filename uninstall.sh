#!/bin/bash
# Removes everything install.sh/build.sh put on this Mac.
set -euo pipefail

LABEL="io.diegopuerto.claudeusage.refresh"
APP_NAME="Claude Usage"
SUPPORT="$HOME/Library/Application Support/ClaudeUsageWidget"
CONTAINER="$HOME/Library/Containers/io.diegopuerto.claudeusage.widget"

echo "==> Deteniendo la app"
pkill -x ClaudeUsage 2>/dev/null || true

echo "==> Quitando el LaunchAgent"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"

echo "==> Borrando la app"
rm -rf "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"

echo "==> Borrando datos locales"
# Sólo el caché de estado que escribe la app. No toca ~/.claude ni el llavero: esas son
# credenciales y transcripts de Claude Code, que este widget únicamente lee.
rm -rf "$SUPPORT" "$CONTAINER"

echo "==> Listo. Quita el widget del escritorio a mano si seguía puesto."
