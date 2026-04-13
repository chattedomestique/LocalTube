#!/usr/bin/env bash
# setup-sparkle.sh — One-time Sparkle key generation.
#
# Run this ONCE on your development machine before your first release.
# It generates an EdDSA key pair:
#   • Private key → stored securely in your macOS Keychain (never leaves this Mac)
#   • Public key  → printed here; paste it into version.env as SPARKLE_PUBLIC_KEY
#
# Usage:
#   ./Scripts/setup-sparkle.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SPARKLE_VERSION="2.6.4"
SPARKLE_TOOLS_DIR="$ROOT_DIR/.build/sparkle-tools"
GENERATE_KEYS="$SPARKLE_TOOLS_DIR/bin/generate_keys"

# ── Download Sparkle tools if needed ─────────────────────────────────────────
if [[ ! -f "$GENERATE_KEYS" ]]; then
  echo "==> Downloading Sparkle $SPARKLE_VERSION tools…"
  mkdir -p "$SPARKLE_TOOLS_DIR"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    -o "$SPARKLE_TOOLS_DIR/sparkle.tar.xz"
  tar -xf "$SPARKLE_TOOLS_DIR/sparkle.tar.xz" -C "$SPARKLE_TOOLS_DIR" 2>/dev/null || true
  rm -f "$SPARKLE_TOOLS_DIR/sparkle.tar.xz"
fi

if [[ ! -f "$GENERATE_KEYS" ]]; then
  echo "ERROR: generate_keys not found after download. Check the Sparkle release archive." >&2
  exit 1
fi

# ── Generate keys ─────────────────────────────────────────────────────────────
echo ""
echo "Generating EdDSA key pair…"
echo "(Your private key will be saved to the macOS Keychain automatically.)"
echo ""

# generate_keys prints the public key inside a <string> tag
PUBLIC_KEY=$("$GENERATE_KEYS" 2>&1 | grep -oE '[A-Za-z0-9+/=]{40,}' | head -1)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Setup complete."
echo ""
echo " Add the following to version.env:"
echo ""
echo "   SPARKLE_PUBLIC_KEY=${PUBLIC_KEY}"
echo ""
echo " Next steps:"
echo ""
echo "  1. Create a public Gist for the appcast (run once):"
echo "       gh gist create --public appcast.xml \\"
echo "         --desc 'LocalTube appcast'"
echo "     Copy the Gist ID from the URL."
echo ""
echo "  2. Add to version.env:"
echo "       APPCAST_URL=https://gist.githubusercontent.com/<user>/<gistId>/raw/appcast.xml"
echo "       GIST_ID=<gist-id>"
echo ""
echo "  3. Release with:"
echo "       ./Scripts/release.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
