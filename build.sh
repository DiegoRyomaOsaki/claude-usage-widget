#!/bin/bash
# Builds "Claude Usage.app" with an embedded WidgetKit extension, without Xcode.
# swiftc from the Command Line Tools, manual bundle assembly, ad-hoc signing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/build"
APP_NAME="Claude Usage"
APP="$BUILD/$APP_NAME.app"
APPEX="$APP/Contents/PlugIns/ClaudeUsageWidget.appex"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

DEPLOY_TARGET="arm64-apple-macos14.0"
SDK="$(xcrun --show-sdk-path)"
SWIFTC=(xcrun swiftc -target "$DEPLOY_TARGET" -sdk "$SDK" -swift-version 5 -O)

SHARED=("$ROOT"/Sources/Shared/*.swift)
APP_SRC=("$ROOT"/Sources/App/*.swift)
WIDGET_SRC=("$ROOT"/Sources/Widget/*.swift)

echo "==> Limpiando"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"

echo "==> Compilando extensión de widget (WidgetKit)"
# An app extension must enter through Foundation's NSExtensionMain, which sets up the
# NSExtension bootstrap from Info.plist. Without it WidgetKit reaches ExtensionFoundation
# with no extension identity and traps with "Unrecognized extension type"; chronod's
# descriptor query then dies and purges the extension, so the widget is silently absent
# from the gallery. Xcode passes this flag for extension targets.
"${SWIFTC[@]}" -parse-as-library \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$APPEX/Contents/MacOS/ClaudeUsageWidget" \
  "${SHARED[@]}" "${WIDGET_SRC[@]}"

echo "==> Compilando app contenedora"
"${SWIFTC[@]}" \
  -o "$APP/Contents/MacOS/ClaudeUsage" \
  "${SHARED[@]}" "${APP_SRC[@]}"

echo "==> Ensamblando bundles"
cp "$ROOT/Resources/App-Info.plist"    "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Widget-Info.plist" "$APPEX/Contents/Info.plist"

# Xcode stamps these build-provenance keys automatically; LaunchServices and chronod
# expect them on a widget extension, so reproduce them from the toolchain in use.
SDK_VERSION="$(xcrun --show-sdk-version)"
SDK_BUILD="$(xcrun --show-sdk-build-version 2>/dev/null || echo unknown)"
OS_BUILD="$(sw_vers -buildVersion)"
stamp_provenance() {
  /usr/libexec/PlistBuddy \
    -c "Add :DTPlatformName string macosx" \
    -c "Add :DTPlatformVersion string $SDK_VERSION" \
    -c "Add :DTSDKName string macosx$SDK_VERSION" \
    -c "Add :DTSDKBuild string $SDK_BUILD" \
    -c "Add :DTPlatformBuild string $SDK_BUILD" \
    -c "Add :DTCompiler string com.apple.compilers.llvm.clang.1_0" \
    -c "Add :BuildMachineOSBuild string $OS_BUILD" \
    "$1" >/dev/null
}
stamp_provenance "$APP/Contents/Info.plist"
stamp_provenance "$APPEX/Contents/Info.plist"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

echo "==> Firmando (ad-hoc)"
# The extension is signed first: the app's signature covers its nested bundles.
codesign --force --sign - \
  --entitlements "$ROOT/Resources/Widget.entitlements" \
  --timestamp=none "$APPEX"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Instalando en $INSTALL_DIR"
# A running copy holds its bundle open; stop it before replacing the app.
pkill -x ClaudeUsage 2>/dev/null || true
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP" "$INSTALL_DIR/$APP_NAME.app"

# LaunchServices has to see the app before WidgetKit will offer its extension.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$INSTALL_DIR/$APP_NAME.app"

echo "==> Listo: $INSTALL_DIR/$APP_NAME.app"
echo "    Abre la app una vez para que el sistema registre el widget."
