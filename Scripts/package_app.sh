#!/usr/bin/env bash
set -euo pipefail

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME=${APP_NAME:-LocalTube}
BUNDLE_ID=${BUNDLE_ID:-com.local.localtube}
MACOS_MIN_VERSION=${MACOS_MIN_VERSION:-14.0}
SIGNING_MODE=${SIGNING_MODE:-adhoc}
APP_IDENTITY=${APP_IDENTITY:-}

# Sparkle — set these in version.env or the environment before releasing.
# APPCAST_URL: public URL of your appcast.xml (e.g. a GitHub Gist raw URL)
# SPARKLE_PUBLIC_KEY: base64 EdDSA public key printed by Scripts/setup-sparkle.sh
APPCAST_URL=${APPCAST_URL:-}
SPARKLE_PUBLIC_KEY=${SPARKLE_PUBLIC_KEY:-}

if [[ -f "$ROOT/version.env" ]]; then
  source "$ROOT/version.env"
else
  MARKETING_VERSION=${MARKETING_VERSION:-1.0.0}
  BUILD_NUMBER=${BUILD_NUMBER:-1}
fi

ARCH_LIST=( ${ARCHES:-} )
if [[ ${#ARCH_LIST[@]} -eq 0 ]]; then
  HOST_ARCH=$(uname -m)
  ARCH_LIST=("$HOST_ARCH")
fi

for ARCH in "${ARCH_LIST[@]}"; do
  swift build -c "$CONF" --arch "$ARCH"
done

APP="$ROOT/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>${MACOS_MIN_VERSION}</string>
    <key>LSUIElement</key><false/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSRequiresAquaSystemAppearance</key><false/>
    <key>BuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    <key>GitCommit</key><string>${GIT_COMMIT}</string>
    <key>SUFeedURL</key><string>${APPCAST_URL}</string>
    <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>
    <key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
PLIST

build_product_path() {
  local name="$1"
  local arch="$2"
  case "$arch" in
    arm64|x86_64) echo ".build/${arch}-apple-macosx/$CONF/$name" ;;
    *) echo ".build/$CONF/$name" ;;
  esac
}

install_binary() {
  local name="$1"
  local dest="$2"
  local binaries=()
  for arch in "${ARCH_LIST[@]}"; do
    local src
    src=$(build_product_path "$name" "$arch")
    if [[ ! -f "$src" ]]; then
      echo "ERROR: Missing ${name} build for ${arch} at ${src}" >&2
      exit 1
    fi
    binaries+=("$src")
  done
  if [[ ${#ARCH_LIST[@]} -gt 1 ]]; then
    lipo -create "${binaries[@]}" -output "$dest"
  else
    cp "${binaries[0]}" "$dest"
  fi
  chmod +x "$dest"
}

install_binary "$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# Add @executable_path/../Frameworks to rpath so dyld finds Sparkle.framework
# at runtime. SwiftPM sets @rpath when linking but doesn't add this search path
# for non-Xcode bundles — we patch it here after copying the binary.
install_name_tool -add_rpath "@executable_path/../Frameworks" \
  "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true

# Bundle app resources
APP_RESOURCES_DIR="$ROOT/Sources/$APP_NAME/Resources"
if [[ -d "$APP_RESOURCES_DIR" ]]; then
  cp -R "$APP_RESOURCES_DIR/." "$APP/Contents/Resources/"
fi

# SwiftPM resource bundles
PREFERRED_BUILD_DIR="$(dirname "$(build_product_path "$APP_NAME" "${ARCH_LIST[0]}")")"
shopt -s nullglob
SWIFTPM_BUNDLES=("${PREFERRED_BUILD_DIR}/"*.bundle)
shopt -u nullglob
if [[ ${#SWIFTPM_BUNDLES[@]} -gt 0 ]]; then
  for bundle in "${SWIFTPM_BUNDLES[@]}"; do
    cp -R "$bundle" "$APP/Contents/Resources/"
  done
fi

# Copy WebUI directly into Contents/Resources/WebUI so the app can find it
# at both Resources/WebUI/index.html and Resources/Resources/WebUI/index.html.
WEBUI_SRC="${PREFERRED_BUILD_DIR}/${APP_NAME}_${APP_NAME}.bundle/Resources/WebUI"
if [[ -d "$WEBUI_SRC" ]]; then
  rm -rf "$APP/Contents/Resources/WebUI"
  cp -R "$WEBUI_SRC" "$APP/Contents/Resources/WebUI"
  echo "   Copied WebUI from ${WEBUI_SRC}"
else
  echo "WARN: WebUI not found at ${WEBUI_SRC} — skipping WebUI copy" >&2
fi

# ── Sparkle.framework ────────────────────────────────────────────────────────
# Locate the framework in the SwiftPM build artifacts and copy it into the
# app bundle. Sparkle is a dynamic framework and must be embedded.
SPARKLE_FW=$(find "$ROOT/.build" -name "Sparkle.framework" -type d 2>/dev/null | head -1)
if [[ -n "$SPARKLE_FW" ]]; then
  cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"
  echo "   Bundled $(basename "$SPARKLE_FW")"
else
  echo "WARN: Sparkle.framework not found in .build — update checks will not work" >&2
fi

chmod -R u+w "$APP"
# Strip extended attributes recursively (macOS xattr has no -r flag; use find)
find "$APP" -exec xattr -c {} + 2>/dev/null || true
find "$APP" -name '._*' -delete

ENTITLEMENTS_DIR="$ROOT/.build/entitlements"
DEFAULT_ENTITLEMENTS="$ENTITLEMENTS_DIR/${APP_NAME}.entitlements"
mkdir -p "$ENTITLEMENTS_DIR"

APP_ENTITLEMENTS=${APP_ENTITLEMENTS:-$DEFAULT_ENTITLEMENTS}
if [[ ! -f "$APP_ENTITLEMENTS" ]]; then
  cat > "$APP_ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
PLIST
fi

if [[ "$SIGNING_MODE" == "adhoc" || -z "$APP_IDENTITY" ]]; then
  CODESIGN_ARGS=(--force --sign "-")
else
  CODESIGN_ARGS=(--force --timestamp --options runtime --sign "$APP_IDENTITY")
fi

# Sign Sparkle internals first (inside-out signing requirement)
if [[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]]; then
  # Sign XPC services and helpers inside the framework
  find "$APP/Contents/Frameworks/Sparkle.framework" \
    \( -name "*.xpc" -o -name "Autoupdater" -o -name "Updater" \) \
    -type d -o -type f | sort -r | while read -r item; do
    codesign "${CODESIGN_ARGS[@]}" "$item" 2>/dev/null || true
  done
  codesign "${CODESIGN_ARGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
fi

# Sign the main app bundle
codesign "${CODESIGN_ARGS[@]}" \
  --entitlements "$APP_ENTITLEMENTS" \
  "$APP"

echo "✅ Created $APP"
