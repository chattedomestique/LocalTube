#!/usr/bin/env bash
# release.sh — Build, sign, publish a GitHub Release, and update the appcast.
#
# Works both on a developer Mac and inside GitHub Actions
# (.github/workflows/release.yml). Every step is non-interactive.
#
# Usage:
#   ./Scripts/release.sh [patch|minor|major]   (default: patch)
#
# Inputs (environment, all optional):
#   SPARKLE_PRIVATE_KEY  base64 EdDSA private key (CI secret). When unset the
#                        key is read from the macOS Keychain (developer Mac).
#   GH_TOKEN             token used by `gh` for the GitHub Release (CI passes
#                        GITHUB_TOKEN; locally `gh auth login` suffices).
#   GIST_TOKEN           token with the `gist` scope, used to mirror the
#                        appcast to the legacy Gist feed that builds <= 1.0.33
#                        check. Optional — newer builds read the appcast from
#                        the repository itself (see APPCAST_URL).
#   RELEASE_NOTES        text for the GitHub Release body (default: build no.).
#   SKIP_PUSH=1          don't push the commit/tag (dry runs).
#
# First-time setup on a developer Mac:
#   1. Run Scripts/setup-sparkle.sh once to generate signing keys
#   2. Make sure version.env carries APPCAST_URL and SPARKLE_PUBLIC_KEY
#
# What happens without a Sparkle key: the app is still built and published as
# a GitHub Release (downloadable), but NO appcast entry is written, because
# Sparkle refuses unsigned updates and existing installs would see a broken
# update. Add the key (see RELEASING.md) and run again to ship an update.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUMP=${1:-patch}
APP_NAME=${APP_NAME:-LocalTube}
BUNDLE_ID=${BUNDLE_ID:-com.local.localtube}
VERSION_ENV="$ROOT_DIR/version.env"
SPARKLE_VERSION="2.6.4"
SPARKLE_TOOLS_DIR="$ROOT_DIR/.build/sparkle-tools"
REPO_SLUG=${REPO_SLUG:-chattedomestique/LocalTube}

log()  { printf '==> %s\n' "$*"; }
warn() { printf '::warning::%s\n' "$*" >&2; printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ── Load version + Sparkle config ────────────────────────────────────────────
if [[ -f "$VERSION_ENV" ]]; then source "$VERSION_ENV"; fi
MARKETING_VERSION=${MARKETING_VERSION:-1.0.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}
APPCAST_URL=${APPCAST_URL:-}
SPARKLE_PUBLIC_KEY=${SPARKLE_PUBLIC_KEY:-}
GIST_ID=${GIST_ID:-}

[[ -n "$APPCAST_URL" && -n "$SPARKLE_PUBLIC_KEY" ]] \
  || die "APPCAST_URL and SPARKLE_PUBLIC_KEY must be set in version.env (run Scripts/setup-sparkle.sh first)."

command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is required."
command -v python3 >/dev/null 2>&1 || die "python3 is required."

# ── Ensure Sparkle tools are available ───────────────────────────────────────
SIGN_UPDATE="$SPARKLE_TOOLS_DIR/bin/sign_update"
if [[ ! -f "$SIGN_UPDATE" ]]; then
  log "Downloading Sparkle $SPARKLE_VERSION tools..."
  mkdir -p "$SPARKLE_TOOLS_DIR"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    -o "$SPARKLE_TOOLS_DIR/sparkle.tar.xz"
  tar -xf "$SPARKLE_TOOLS_DIR/sparkle.tar.xz" -C "$SPARKLE_TOOLS_DIR" 2>/dev/null || true
  rm -f "$SPARKLE_TOOLS_DIR/sparkle.tar.xz"
fi
[[ -f "$SIGN_UPDATE" ]] || die "Could not find sign_update tool after download."

# ── Bump version ──────────────────────────────────────────────────────────────
IFS='.' read -r MAJ MIN PAT <<< "$MARKETING_VERSION"
case "$BUMP" in
  major) MAJ=$((MAJ+1)); MIN=0; PAT=0 ;;
  minor) MIN=$((MIN+1)); PAT=0 ;;
  patch) PAT=$((PAT+1)) ;;
  *) die "bump must be patch, minor, or major" ;;
esac
MARKETING_VERSION="${MAJ}.${MIN}.${PAT}"
BUILD_NUMBER=$((BUILD_NUMBER+1))
TAG="v${MARKETING_VERSION}"
log "Version: $MARKETING_VERSION (build $BUILD_NUMBER)"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  die "Tag $TAG already exists locally. Bump version.env or delete the tag."
fi

# Write back
cat > "$VERSION_ENV" <<ENV
MARKETING_VERSION=${MARKETING_VERSION}
BUILD_NUMBER=${BUILD_NUMBER}
APPCAST_URL=${APPCAST_URL}
SPARKLE_PUBLIC_KEY=${SPARKLE_PUBLIC_KEY}
GIST_ID=${GIST_ID}
ENV

# ── Build and package ─────────────────────────────────────────────────────────
log "Building $APP_NAME..."
MARKETING_VERSION="$MARKETING_VERSION" BUILD_NUMBER="$BUILD_NUMBER" \
  APPCAST_URL="$APPCAST_URL" SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY" \
  APP_NAME="$APP_NAME" BUNDLE_ID="$BUNDLE_ID" SIGNING_MODE=${SIGNING_MODE:-adhoc} \
  "$ROOT_DIR/Scripts/package_app.sh" release

codesign --verify --deep --strict "${APP_NAME}.app"

# ── Create release zip ────────────────────────────────────────────────────────
ZIP_NAME="${APP_NAME}-${MARKETING_VERSION}.zip"
ZIP_PATH="$ROOT_DIR/$ZIP_NAME"
log "Creating $ZIP_NAME..."
rm -f "$ZIP_PATH"
ditto -ck --keepParent "${APP_NAME}.app" "$ZIP_PATH"
ZIP_LENGTH=$(wc -c < "$ZIP_PATH" | tr -d ' ')

# ── Sign with Sparkle EdDSA ───────────────────────────────────────────────────
ED_SIGNATURE=""
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  log "Signing with EdDSA (key from environment)..."
  KEY_FILE=$(mktemp -t sparkle-key)
  chmod 600 "$KEY_FILE"
  printf '%s' "$SPARKLE_PRIVATE_KEY" | tr -d '[:space:]' > "$KEY_FILE"
  ED_SIGNATURE=$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$ZIP_PATH" 2>/dev/null | grep -oE '[A-Za-z0-9+/=]{80,}' | head -1 || true)
  rm -f "$KEY_FILE"
  [[ -n "$ED_SIGNATURE" ]] || die "sign_update failed with the provided SPARKLE_PRIVATE_KEY."
else
  log "Signing with EdDSA (key from Keychain)..."
  ED_SIGNATURE=$("$SIGN_UPDATE" "$ZIP_PATH" 2>/dev/null | grep -oE '[A-Za-z0-9+/=]{80,}' | head -1 || true)
  if [[ -z "$ED_SIGNATURE" ]]; then
    warn "No Sparkle private key available (not in Keychain, SPARKLE_PRIVATE_KEY unset). The release will be published WITHOUT an appcast entry, so existing installs will not auto-update to it. See RELEASING.md."
  fi
fi

# ── Update appcast.xml ────────────────────────────────────────────────────────
# Base the new appcast on whatever the live feed currently serves so no
# existing <item> is lost even if the committed file lagged behind; fall back
# to the committed file when the feed is unreachable.
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/${REPO_SLUG}/releases/download/${TAG}/${ZIP_NAME}"
APPCAST_BASE=$(mktemp -t appcast-base)
if ! curl -fsSL --max-time 20 "$APPCAST_URL" -o "$APPCAST_BASE" 2>/dev/null || ! grep -q "<item>" "$APPCAST_BASE"; then
  if [[ -f "$ROOT_DIR/appcast.xml" ]]; then cp "$ROOT_DIR/appcast.xml" "$APPCAST_BASE"; else : > "$APPCAST_BASE"; fi
fi

if [[ -n "$ED_SIGNATURE" ]]; then
  log "Updating appcast.xml..."
  python3 - "$APPCAST_BASE" "$ROOT_DIR/appcast.xml" <<PY
import re, sys, html
base_path, out_path = sys.argv[1], sys.argv[2]
try:
    content = open(base_path, encoding="utf-8").read()
except OSError:
    content = ""
items = re.findall(r'[ \t]*<item>.*?</item>', content, re.DOTALL)
# Drop any previous entry for this exact version (re-run safety).
items = [i for i in items if "<sparkle:shortVersionString>${MARKETING_VERSION}</sparkle:shortVersionString>" not in i]
new_item = """        <item>
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
        </item>"""
doc = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatranga.com/sparkle/ns#"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>${APP_NAME}</title>
        <link>https://github.com/${REPO_SLUG}</link>
        <description>${APP_NAME} changelog</description>
        <language>en</language>
""" + new_item + "\n" + "".join(i if i.startswith("\n") else "\n" + i for i in items) + """
    </channel>
</rss>
"""
open(out_path, "w", encoding="utf-8").write(doc)
PY
  python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1])" "$ROOT_DIR/appcast.xml" \
    || die "Generated appcast.xml is not well-formed XML."
else
  log "Skipping appcast update (no signature)."
fi
rm -f "$APPCAST_BASE"

# ── Commit version bump (+ appcast, + rebuilt WebUI bundle) ──────────────────
log "Committing release..."
git add version.env
[[ -n "$ED_SIGNATURE" ]] && git add appcast.xml
git add -A Sources/LocalTube/Resources/WebUI 2>/dev/null || true
git commit -q -m "Release $MARKETING_VERSION (build $BUILD_NUMBER)"
git tag "$TAG"

if [[ "${SKIP_PUSH:-0}" != "1" ]]; then
  git push origin HEAD
  git push origin "$TAG"
else
  warn "SKIP_PUSH=1 — commit and tag were not pushed."
fi

# ── GitHub Release + upload zip ───────────────────────────────────────────────
log "Creating GitHub Release $TAG..."
NOTES=${RELEASE_NOTES:-"Build $BUILD_NUMBER"}
if [[ -z "$ED_SIGNATURE" ]]; then
  NOTES="$NOTES

> Not signed for Sparkle auto-update (no signing key was available when this release was built). Download and install manually; this version will not be offered by Check for Updates…"
fi
if [[ "${SKIP_PUSH:-0}" != "1" ]]; then
  gh release create "$TAG" "$ZIP_PATH" \
    --repo "$REPO_SLUG" \
    --title "$APP_NAME $MARKETING_VERSION" \
    --notes "$NOTES" \
    --latest
fi

# ── Mirror appcast to the legacy Gist feed (best effort) ─────────────────────
# Builds up to 1.0.33 read their feed from the Gist. Newer builds read
# APPCAST_URL (the committed appcast.xml served raw from the repository).
if [[ -n "$ED_SIGNATURE" && -n "$GIST_ID" && "${SKIP_PUSH:-0}" != "1" ]]; then
  if [[ -n "${GIST_TOKEN:-}" ]]; then
    log "Mirroring appcast to Gist $GIST_ID..."
    if GH_TOKEN="$GIST_TOKEN" gh gist edit "$GIST_ID" "$ROOT_DIR/appcast.xml"; then
      log "Gist updated."
    else
      warn "Gist update failed — installs older than 1.0.34 will not see this update until the Gist is refreshed (gh gist edit $GIST_ID appcast.xml)."
    fi
  elif gh gist edit "$GIST_ID" "$ROOT_DIR/appcast.xml" 2>/dev/null; then
    log "Gist updated with the local gh login."
  else
    warn "GIST_TOKEN not set — the legacy Gist feed was not updated. Installs older than 1.0.34 need one refresh: gh gist edit $GIST_ID appcast.xml"
  fi
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version=$MARKETING_VERSION"
    echo "build=$BUILD_NUMBER"
    echo "tag=$TAG"
    echo "zip=$ZIP_PATH"
    echo "signed=$([[ -n "$ED_SIGNATURE" ]] && echo true || echo false)"
  } >> "$GITHUB_OUTPUT"
fi

echo ""
echo "✅ Released $APP_NAME $MARKETING_VERSION (build $BUILD_NUMBER) — $DOWNLOAD_URL"
