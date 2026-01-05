#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  Scripts/make_dmg.sh --app <path-to-app> --out <path-to-output.dmg> [--volname <name>]
EOF
}

APP_PATH=""
OUT_DMG=""
VOLNAME="AerialFlow"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="${2:-}"; shift 2 ;;
    --out)
      OUT_DMG="${2:-}"; shift 2 ;;
    --volname)
      VOLNAME="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown arg: $1" ;;
  esac
done

[[ -n "${APP_PATH}" ]] || { usage; die "Missing --app"; }
[[ -n "${OUT_DMG}" ]] || { usage; die "Missing --out"; }
[[ -d "${APP_PATH}" ]] || die "App not found: ${APP_PATH}"

require_cmd /usr/bin/hdiutil
require_cmd /bin/ln
require_cmd /bin/mkdir
require_cmd /bin/cp
require_cmd /usr/bin/shasum

OUT_DIR="$(cd -- "$(dirname -- "${OUT_DMG}")" && pwd)"
/bin/mkdir -p "${OUT_DIR}"

TMP_DIR="$(repo_root)/.tmp/release/dmg-src"
rm -rf "${TMP_DIR}"
/bin/mkdir -p "${TMP_DIR}"

log "Preparing DMG source folder…"
/bin/cp -R "${APP_PATH}" "${TMP_DIR}/"
/bin/ln -s /Applications "${TMP_DIR}/Applications"

log "Creating DMG: ${OUT_DMG}"
/usr/bin/hdiutil create \
  -volname "${VOLNAME}" \
  -srcfolder "${TMP_DIR}" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "${OUT_DMG}"

log "Writing checksum…"
/usr/bin/shasum -a 256 "${OUT_DMG}" > "${OUT_DMG}.sha256.txt"

log "OK"


