#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  Scripts/build_unsigned.sh [--dmg] [--install-to <dir>]

What it does:
  - Builds a universal (arm64+x86_64) Release app with code signing disabled
  - Writes the .app to: dist/unsigned/AerialFlow.app
  - Optional: creates an unsigned DMG via hdiutil
  - Optional: copies the app into an install directory

Examples:
  bash Scripts/build_unsigned.sh
  bash Scripts/build_unsigned.sh --dmg
  bash Scripts/build_unsigned.sh --install-to "/Applications"
EOF
}

MAKE_DMG="0"
INSTALL_TO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg)
      MAKE_DMG="1"; shift ;;
    --install-to)
      INSTALL_TO="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown arg: $1" ;;
  esac
done

require_cmd /usr/bin/xcodebuild
require_cmd /usr/bin/ditto

ROOT="$(repo_root)"
PROJECT="${ROOT}/AerialFlow/AerialFlow.xcodeproj"
SCHEME="AerialFlow"
DERIVED="${ROOT}/.derivedData"
TMP_BASE="${ROOT}/.tmp/unsigned"
DIST="${ROOT}/dist/unsigned"

rm -rf "${TMP_BASE}"
mkdir -p "${TMP_BASE}" "${DIST}"

log "Resolving version/build…"
BUILD_SETTINGS="$(/usr/bin/xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -configuration Release -showBuildSettings)"
VERSION="$(echo "${BUILD_SETTINGS}" | /usr/bin/awk -F ' = ' '/MARKETING_VERSION/ {print $2; exit}')"
BUILD="$(echo "${BUILD_SETTINGS}" | /usr/bin/awk -F ' = ' '/CURRENT_PROJECT_VERSION/ {print $2; exit}')"
[[ -n "${VERSION}" ]] || die "Could not determine MARKETING_VERSION"
[[ -n "${BUILD}" ]] || die "Could not determine CURRENT_PROJECT_VERSION"

log "Building (universal, unsigned)…"
/usr/bin/xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -sdk macosx \
  -derivedDataPath "${DERIVED}" \
  build \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

APP_NAME="AerialFlow"
APP_BUILT_PATH="${DERIVED}/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "${APP_BUILT_PATH}" ]]; then
  APP_BUILT_PATH="$(/usr/bin/find "${DERIVED}/Build/Products" -maxdepth 4 -type d -name "${APP_NAME}.app" -path "*/Release/*" | /usr/bin/head -n 1 || true)"
fi
[[ -n "${APP_BUILT_PATH}" ]] || die "Could not locate built app in ${DERIVED}/Build/Products"
[[ -d "${APP_BUILT_PATH}" ]] || die "Built app not found: ${APP_BUILT_PATH}"

OUT_APP="${DIST}/${APP_NAME}.app"
rm -rf "${OUT_APP}"
log "Copying app to: ${OUT_APP}"
/usr/bin/ditto "${APP_BUILT_PATH}" "${OUT_APP}"

if [[ "${MAKE_DMG}" == "1" ]]; then
  DMG_NAME="${APP_NAME}-${VERSION}(${BUILD})-unsigned-universal.dmg"
  DMG_PATH="${ROOT}/dist/${DMG_NAME}"
  log "Creating unsigned DMG…"
  "${SCRIPT_DIR}/make_dmg.sh" --app "${OUT_APP}" --out "${DMG_PATH}" --volname "${APP_NAME}"
  log "Unsigned DMG:"
  log "  ${DMG_PATH}"
  log "  ${DMG_PATH}.sha256.txt"
fi

if [[ -n "${INSTALL_TO}" ]]; then
  [[ -d "${INSTALL_TO}" ]] || die "Install dir not found: ${INSTALL_TO}"
  log "Installing to: ${INSTALL_TO}"
  rm -rf "${INSTALL_TO}/${APP_NAME}.app" || true
  # Note: may require sudo for /Applications.
  /bin/cp -R "${OUT_APP}" "${INSTALL_TO}/"
  log "Installed: ${INSTALL_TO}/${APP_NAME}.app"
fi

log "Done:"
log "  ${OUT_APP}"


