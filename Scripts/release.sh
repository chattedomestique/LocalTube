#!/usr/bin/env bash
# release.sh — Build, sign, publish a GitHub Release, and update the appcast.
#
# Usage:
#   ./Scripts/release.sh [patch|minor|major]   (default: patch)
#
# First-time setup:
#   1. Run Scripts/setup-sparkle.sh once to generate signing keys
#   2. Create a public GitHub Gist and note its ID:
#        gh gist create --public appcast.xml --desc "LocalTube appcast"
#   3. Add to version.env:
#        APPCAST_URL=https://gist.githubusercontent.com/<user>/<gistId>/raw/appcast.xml
#        SPARKLE_PUBLIC_KEY=<key printed by setup-sparkle.sh>
#        GIST_ID=<gist id>

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUMP=${1:-patch}
APP_NAME=${APP_NAME:-LocalTube}
BUNDLE_ID=${BUNDLE_ID:-com.local.localtube}
VERSION_ENV="$ROOT_DIR/version.env"
SPARKLE_VERSION="2.6.4"
SPARKLE_TOOLS_DIR="$ROOT_DIR/.build/sparkle-tools"

# ── Load version + Sparkle config ────────────────────────────────────────────
if [[ -f "$VERSION_ENV" ]]; then source "$VERSION_ENV"; fi
MARKETING_VERSION=${MARKETING_VERSION:-1.0.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}
APPCAST_URL=${APPCAST_URL:-}
SPARKLE_PUBLIC_KEY=${SPARKLE_PUBLIC_KEY:-}
GIST_ID=${GIST_ID:-}

if [[ -z "$APPCAST_URL" || -z "$SPARKLE_PUBLIC_KEY" ]]; then
  echo "ERROR: APPCAST_URL and SPARKLE_PUBLIC_KEY must be set in version.env"
  echo "       Run Scripts/setup-sparkle.sh first, then re-run this script."
  exit 1
fi

# ── Ensure Sparkle tools are available ───────────────────────────────────────
SIGN_UPDATE="$SPARKLE_TOOLS_DIR/bin/sign_update"
if [[ ! -f "$SIGN_UPDATE" ]]; then
  echo "==> Downloading Sparkle $SPARKLE_VERSION tools…"
  mkdir -p "$SPARKLE_TOOLS_DIR"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    -o "$SPARKLE_TOOLS_DIR/sparkle.tar.xz"
  tar -xf "$SPARKLE_TOOLS_DIR/sparkle.tar.xz" -C "$SPARKLE_TOOLS_DIR" --strip-components=0 ./bin 2>/dev/null || \
  tar -xf "$SPARKLE_TOOLS_DIR/sparkle.tar.xz" -C "$SPARKLE_TOOLS_DIR" 2>/dev/null || true
  rm -f "$SPARKLE_TOOLS_DIR/sparkle.tar.xz"
fi

if [[ ! -f "$SIGN_UPDATE" ]]; then
  echo "ERROR: Could not find sign_update tool. Re-run setup-sparkle.sh."
  exit 1
fi

# ── Bump version ──────────────────────────────────────────────────────────────
IFS='.' read -r MAJ MIN PAT <<< "$MARKETING_VERSION"
case "$BUMP" in
  major) MAJ=$((MAJ+1)); MIN=0; PAT=0 ;;
  minor) MIN=$((MIN+1)); PAT=0 ;;
  patch) PAT=$((PAT+1)) ;;
  *) echo "ERROR: bump must be patch, minor, or major" >&2; exit 1 ;;
esac
MARKETING_VERSION="${MAJ}.${MIN}.${PAT}"
BUILD_NUMBER=$((BUILD_NUMBER+1))
echo "==> Version: $MARKETING_VERSION (build $BUILD_NUMBER)"

# Write back
cat > "$VERSION_ENV" <<ENV
MARKETING_VERSION=${MARKETING_VERSION}
BUILD_NUMBER=${BUILD_NUMBER}
APPCAST_URL=${APPCAST_URL}
SPARKLE_PUBLIC_KEY=${SPARKLE_PUBLIC_KEY}
GIST_ID=${GIST_ID}
ENV

# ── Build and package ─────────────────────────────────────────────────────────
echo "==> Building $APP_NAME…"
MARKETING_VERSION="$MARKETING_VERSION" BUILD_NUMBER="$BUILD_NUMBER" \
  APPCAST_URL="$APPCAST_URL" SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY" \
  APP_NAME="$APP_NAME" BUNDLE_ID="$BUNDLE_ID" SIGNING_MODE=adhoc \
  "$ROOT_DIR/Scripts/package_app.sh" release

# ── Create release zip ────────────────────────────────────────────────────────
ZIP_NAME="${APP_NAME}-${MARKETING_VERSION}.zip"
ZIP_PATH="$ROOT_DIR/$ZIP_NAME"
echo "==> Creating $ZIP_NAME…"
ditto -ck --keepParent "${APP_NAME}.app" "$ZIP_PATH"

# ── Sign with Sparkle EdDSA ───────────────────────────────────────────────────
echo "==> Signing with EdDSA…"
ED_SIGNATURE=$("$SIGN_UPDATE" "$ZIP_PATH" 2>/dev/null | grep -oE '[A-Za-z0-9+/=]{80,}' | head -1)
ZIP_LENGTH=$(wc -c < "$ZIP_PATH" | tr -d ' ')
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

if [[ -z "$ED_SIGNATURE" ]]; then
  echo "ERROR: sign_update failed — is the private key in your Keychain?"
  echo "       Re-run Scripts/setup-sparkle.sh to regenerate keys."
  rm -f "$ZIP_PATH"
  exit 1
fi

# ── Commit version bump ───────────────────────────────────────────────────────
echo "==> Committing version bump…"
git add version.env
git commit -m "Release $MARKETING_VERSION (build $BUILD_NUMBER)"
TAG="v${MARKETING_VERSION}"
git tag "$TAG"
git push origin HEAD
git push origin "$TAG"

# ── GitHub Release + upload zip ───────────────────────────────────────────────
echo "==> Creating GitHub Release $TAG…"
DOWNLOAD_URL="https://github.com/chattedomestique/LocalTube/releases/download/${TAG}/${ZIP_NAME}"
gh release create "$TAG" "$ZIP_PATH" \
  --title "$APP_NAME $MARKETING_VERSION" \
  --notes "Build $BUILD_NUMBER" \
  --latest

# ── Update appcast.xml ────────────────────────────────────────────────────────
echo "==> Updating appcast.xml…"

# Preserve existing <item> entries so clients on old versions can still update.
# Use Python to reliably extract complete <item>...</item> blocks — awk range
# patterns break when any item is missing its closing tag.
EXISTING_ITEMS=""
if [[ -f "$ROOT_DIR/appcast.xml" ]]; then
  EXISTING_ITEMS=$(python3 -c "
import re, sys
content = open('${ROOT_DIR}/appcast.xml').read()
items = re.findall(r'[ \t]*<item>.*?</item>', content, re.DOTALL)
print(''.join(items))
" 2>/dev/null || true)
fi

cat > "$ROOT_DIR/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatranga.com/sparkle/ns#"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>LocalTube</title>
        <link>https://github.com/chattedomestique/LocalTube</link>
        <description>LocalTube changelog</description>
        <language>en</language>
        <item>
            <title>${APP_NAME} ${MARKETING_VERSION}</title>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${MARKETING_VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <pubDate>${PUB_DATE}</pubDate>
            <enclosure
                url="${DOWNLOAD_URL}"
                length="${ZIP_LENGTH}"
                type="application/octet-stream"
                sparkle:edSignature="${ED_SIGNATURE}" />
        </item>
${EXISTING_ITEMS}
    </channel>
</rss>
XML

# ── Push appcast to Gist ──────────────────────────────────────────────────────
if [[ -n "$GIST_ID" ]]; then
  echo "==> Pushing appcast to Gist $GIST_ID…"
  gh gist edit "$GIST_ID" "$ROOT_DIR/appcast.xml"
  echo "✅ Appcast updated."
else
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo " GIST_ID not set — add it to version.env so future releases"
  echo " automatically push the appcast. Create one with:"
  echo "   gh gist create --public appcast.xml --desc 'LocalTube appcast'"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

rm -f "$ZIP_PATH"
echo ""
echo "✅ Released $APP_NAME $MARKETING_VERSION (build $BUILD_NUMBER)"
