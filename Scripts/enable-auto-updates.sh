#!/usr/bin/env bash
# enable-auto-updates.sh — one command to make Sparkle auto-updates work
# from CI. Run it ONCE on the Mac that ran Scripts/setup-sparkle.sh (the one
# whose Keychain holds the LocalTube EdDSA private key).
#
#   ./Scripts/enable-auto-updates.sh
#
# What it does:
#   1. exports the Sparkle private key from your Keychain
#   2. stores it as the SPARKLE_PRIVATE_KEY secret of the GitHub repository
#      (the value never touches disk unencrypted for longer than the export)
#   3. kicks off the Release workflow so a *signed* release is published
#   4. when that run finishes, mirrors the fresh appcast to the legacy Gist
#      so installs older than 1.0.34 (which still read the Gist) get it too
#
# Requirements: gh (logged in: `gh auth login`), git, curl. Nothing else.
#
# Flags:
#   --no-release   only store the secret (steps 1–2)
#   --gist-only    only refresh the Gist from the current master appcast

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPO_SLUG=${REPO_SLUG:-chattedomestique/LocalTube}
SPARKLE_VERSION="2.6.4"
SPARKLE_TOOLS_DIR="$ROOT_DIR/.build/sparkle-tools"
GENERATE_KEYS="$SPARKLE_TOOLS_DIR/bin/generate_keys"

DO_SECRET=1
DO_RELEASE=1
DO_GIST=1
for arg in "$@"; do
  case "$arg" in
    --no-release) DO_RELEASE=0; DO_GIST=0 ;;
    --gist-only)  DO_SECRET=0; DO_RELEASE=0 ;;
    -h|--help)    sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is required: brew install gh && gh auth login"
gh auth status >/dev/null 2>&1 || die "gh is not logged in. Run: gh auth login"

# shellcheck disable=SC1091
[[ -f version.env ]] && source version.env
GIST_ID=${GIST_ID:-}

# ── 1–2. Export the private key and store it as a repository secret ──────────
if [[ "$DO_SECRET" == "1" ]]; then
  if [[ ! -x "$GENERATE_KEYS" ]]; then
    log "Downloading Sparkle $SPARKLE_VERSION tools..."
    mkdir -p "$SPARKLE_TOOLS_DIR"
    curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
      -o "$SPARKLE_TOOLS_DIR/sparkle.tar.xz"
    tar -xf "$SPARKLE_TOOLS_DIR/sparkle.tar.xz" -C "$SPARKLE_TOOLS_DIR" 2>/dev/null || true
    rm -f "$SPARKLE_TOOLS_DIR/sparkle.tar.xz"
  fi
  [[ -x "$GENERATE_KEYS" ]] || die "generate_keys not found after download."

  KEY_FILE=$(mktemp -t sparkle-key)
  chmod 600 "$KEY_FILE"
  trap 'rm -f "$KEY_FILE"' EXIT

  log "Exporting the Sparkle private key from your Keychain (macOS may ask you to allow access)..."
  rm -f "$KEY_FILE"
  if ! "$GENERATE_KEYS" -x "$KEY_FILE"; then
    die "Could not export the key. Is this the Mac that ran Scripts/setup-sparkle.sh? (The public key in version.env is ${SPARKLE_PUBLIC_KEY:-unset}.)"
  fi
  [[ -s "$KEY_FILE" ]] || die "Exported key file is empty."

  # Sanity check: the Keychain key must match the public key builds are verified against (sign_update can't print a public key).
  if [[ -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
    DERIVED=$("$GENERATE_KEYS" -p 2>/dev/null | tr -d '[:space:]' || true)
    if [[ "$DERIVED" != "$SPARKLE_PUBLIC_KEY" ]]; then
      die "The Keychain key's public half (${DERIVED:-none}) does not match SPARKLE_PUBLIC_KEY in version.env. Shipping updates signed with it would break every existing install. Aborting."
    fi
  fi

  log "Storing SPARKLE_PRIVATE_KEY secret on $REPO_SLUG..."
  gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO_SLUG" < "$KEY_FILE"
  rm -f "$KEY_FILE"
  log "Secret stored."
fi

# ── 3. Cut a signed release now ──────────────────────────────────────────────
if [[ "$DO_RELEASE" == "1" ]]; then
  log "Starting the Release workflow..."
  gh workflow run release.yml --repo "$REPO_SLUG" -f bump=patch -f notes="Enable Sparkle auto-updates"
  sleep 8
  RUN_ID=$(gh run list --repo "$REPO_SLUG" --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')
  [[ -n "$RUN_ID" ]] || die "Could not find the workflow run."
  log "Waiting for run $RUN_ID (about 4 minutes)..."
  gh run watch "$RUN_ID" --repo "$REPO_SLUG" --exit-status || die "Release run failed — see: gh run view $RUN_ID --repo $REPO_SLUG --log"
  log "Signed release published."
fi

# ── 4. Refresh the legacy Gist feed ──────────────────────────────────────────
if [[ "$DO_GIST" == "1" ]]; then
  [[ -n "$GIST_ID" ]] || die "GIST_ID not set in version.env."
  log "Fetching the current appcast from master..."
  TMP_APPCAST=$(mktemp -t appcast)
  curl -fsSL "https://raw.githubusercontent.com/${REPO_SLUG}/master/appcast.xml" -o "$TMP_APPCAST"
  grep -q "<item>" "$TMP_APPCAST" || die "Downloaded appcast looks empty."
  cp "$TMP_APPCAST" "$ROOT_DIR/appcast.xml"
  log "Updating Gist $GIST_ID (installs older than 1.0.34 read this)..."
  gh gist edit "$GIST_ID" -f appcast.xml "$ROOT_DIR/appcast.xml"
  rm -f "$TMP_APPCAST"
  log "Gist updated."
fi

echo ""
echo "✅ Done. Installed copies will pick up the new version from Check for Updates… (or automatically within a day)."
