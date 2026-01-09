#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/lib/common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  Scripts/lib/sign_app.sh <path-to-app> [--identity "<Developer ID Application: ...>"]

Environment:
  SIGN_IDENTITY  Optional fallback for --identity.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

APP_PATH="${1:-}"
shift || true

IDENTITY="${SIGN_IDENTITY:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity)
      IDENTITY="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown arg: $1" ;;
  esac
done

[[ -n "${APP_PATH}" ]] || { usage; die "Missing <path-to-app>"; }
[[ -d "${APP_PATH}" ]] || die "App not found: ${APP_PATH}"

require_cmd /usr/bin/codesign
require_cmd /usr/sbin/spctl
require_cmd /usr/bin/security
require_cmd /usr/bin/xcrun
require_cmd /usr/bin/lipo

if [[ -z "${IDENTITY}" ]]; then
  log "No identity specified; attempting to auto-detect a 'Developer ID Application' identity…"
  # Example line:
  #  1) <hash> "Developer ID Application: Name (TEAMID)" ...
  IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/grep -m1 'Developer ID Application:' \
    | /usr/bin/sed -E 's/.*"([^"]+)".*/\1/')"
fi

[[ -n "${IDENTITY}" ]] || die "Could not determine signing identity. Pass --identity or set SIGN_IDENTITY."

log "Signing: ${APP_PATH}"
log "Identity: ${IDENTITY}"

/usr/bin/codesign --force --options runtime --timestamp --sign "${IDENTITY}" --deep "${APP_PATH}"

log "Verifying codesign…"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

log "Gatekeeper assessment (spctl)…"
#
# Note:
# A freshly Developer-ID-signed app will typically be rejected by Gatekeeper until it has been notarized
# (and ideally stapled). We run this check as a *non-fatal* signal here to aid debugging, but we do not
# fail the signing step on an "Unnotarized Developer ID" result.
#
# The release pipeline performs a strict final Gatekeeper check after notarization/stapling.
if ! /usr/sbin/spctl -a -vv --type execute "${APP_PATH}"; then
  log "Note: spctl rejected the app (expected before notarization). Proceeding…"
fi

log "Universal arch check (lipo)…"
/usr/bin/lipo -archs "${APP_PATH}/Contents/MacOS/"* | /usr/bin/awk '{print "archs:", $0}'

log "OK"

