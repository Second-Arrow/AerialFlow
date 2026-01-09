#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/lib/common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  Scripts/lib/notarize.sh --file <path> [--staple <path>] \
    (--profile <notarytool-profile> | --api-key <key.p8> --key-id <id> --issuer <uuid>)

Notes:
  - Uses: xcrun notarytool submit --wait
  - Optionally staples a target via: xcrun stapler staple
  - Either use --profile (keychain) OR --api-key + --key-id + --issuer (direct API key)
EOF
}

PROFILE=""
API_KEY=""
KEY_ID=""
ISSUER=""
FILE_PATH=""
STAPLE_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"; shift 2 ;;
    --api-key)
      API_KEY="${2:-}"; shift 2 ;;
    --key-id)
      KEY_ID="${2:-}"; shift 2 ;;
    --issuer)
      ISSUER="${2:-}"; shift 2 ;;
    --file)
      FILE_PATH="${2:-}"; shift 2 ;;
    --staple)
      STAPLE_PATH="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown arg: $1" ;;
  esac
done

[[ -n "${FILE_PATH}" ]] || { usage; die "Missing --file"; }
[[ -e "${FILE_PATH}" ]] || die "File not found: ${FILE_PATH}"

# Validate authentication method
if [[ -n "${PROFILE}" ]]; then
  if [[ -n "${API_KEY}" || -n "${KEY_ID}" || -n "${ISSUER}" ]]; then
    die "Cannot use both --profile and --api-key options. Choose one authentication method."
  fi
elif [[ -n "${API_KEY}" ]]; then
  [[ -n "${KEY_ID}" ]] || { usage; die "Missing --key-id (required with --api-key)"; }
  [[ -n "${ISSUER}" ]] || { usage; die "Missing --issuer (required with --api-key)"; }
  [[ -e "${API_KEY}" ]] || die "API key file not found: ${API_KEY}"
else
  { usage; die "Missing authentication: either --profile or --api-key + --key-id + --issuer"; }
fi

require_cmd /usr/bin/xcrun
require_cmd /usr/sbin/spctl

log "Notarizing: ${FILE_PATH}"

if [[ -n "${PROFILE}" ]]; then
  log "Using keychain profile: ${PROFILE}"
  /usr/bin/xcrun notarytool submit "${FILE_PATH}" --keychain-profile "${PROFILE}" --wait
else
  log "Using API key: ${API_KEY} (key-id: ${KEY_ID})"
  /usr/bin/xcrun notarytool submit "${FILE_PATH}" \
    --key "${API_KEY}" \
    --key-id "${KEY_ID}" \
    --issuer "${ISSUER}" \
    --wait
fi

if [[ -n "${STAPLE_PATH}" ]]; then
  [[ -e "${STAPLE_PATH}" ]] || die "Staple target not found: ${STAPLE_PATH}"
  log "Stapling: ${STAPLE_PATH}"
  /usr/bin/xcrun stapler staple "${STAPLE_PATH}"
fi

log "OK"

