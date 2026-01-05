#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  Scripts/notarize.sh --profile <notarytool-profile> --file <path> [--staple <path>]

Notes:
  - Uses: xcrun notarytool submit --wait
  - Optionally staples a target via: xcrun stapler staple
EOF
}

PROFILE=""
FILE_PATH=""
STAPLE_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"; shift 2 ;;
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

[[ -n "${PROFILE}" ]] || { usage; die "Missing --profile"; }
[[ -n "${FILE_PATH}" ]] || { usage; die "Missing --file"; }
[[ -e "${FILE_PATH}" ]] || die "File not found: ${FILE_PATH}"

require_cmd /usr/bin/xcrun
require_cmd /usr/sbin/spctl

log "Notarizing: ${FILE_PATH}"
log "Profile: ${PROFILE}"

/usr/bin/xcrun notarytool submit "${FILE_PATH}" --keychain-profile "${PROFILE}" --wait

if [[ -n "${STAPLE_PATH}" ]]; then
  [[ -e "${STAPLE_PATH}" ]] || die "Staple target not found: ${STAPLE_PATH}"
  log "Stapling: ${STAPLE_PATH}"
  /usr/bin/xcrun stapler staple "${STAPLE_PATH}"
fi

log "OK"


