#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME=${APP_NAME:-LocalTube}
BUNDLE_ID=${BUNDLE_ID:-com.local.localtube}
APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"
APP_PROCESS_PATTERN="${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

log "==> Killing existing ${APP_NAME} instances"
pkill -f "${APP_PROCESS_PATTERN}" 2>/dev/null || true
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 0.3

# Remove stale Keychain items left by older builds that used Security framework.
# Ad-hoc re-signing changes the code signature each build, so macOS prompts for
# access to items stored under the old signature. Deleting them once here
# eliminates the launch-time Keychain dialog entirely.
log "==> Cleaning up legacy Keychain items"
security delete-generic-password -s "${BUNDLE_ID}" -a "pin"      2>/dev/null || true
security delete-generic-password -s "${BUNDLE_ID}" -a "recovery"  2>/dev/null || true
security delete-generic-password -s "com.local.localtube" -a "pin"      2>/dev/null || true
security delete-generic-password -s "com.local.localtube" -a "recovery"  2>/dev/null || true

log "==> Building and packaging ${APP_NAME}"
APP_NAME="$APP_NAME" BUNDLE_ID="$BUNDLE_ID" SIGNING_MODE=adhoc \
  "${ROOT_DIR}/Scripts/package_app.sh" release

log "==> Launching ${APP_NAME}"
if ! open "${APP_BUNDLE}"; then
  log "WARN: open failed; launching binary directly"
  "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1 &
  disown
fi

for _ in {1..15}; do
  if pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null 2>&1; then
    log "✅ ${APP_NAME} is running."
    exit 0
  fi
  sleep 0.4
done
fail "App exited immediately. Check Console.app (User Reports) for crash logs."
