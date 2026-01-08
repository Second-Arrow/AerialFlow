#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/lib/common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  Scripts/lib/release_dmg.sh --notary-profile <profile> [--identity "<Developer ID Application: ...>"] [--sparkle-tag <tag>] [--sparkle-repo <owner/repo>]

Environment:
  NOTARYTOOL_PROFILE  Optional fallback for --notary-profile.
  SIGN_IDENTITY       Optional fallback for --identity.
  SPARKLE_TAG         Optional fallback for --sparkle-tag.
  SPARKLE_REPO        Optional fallback for --sparkle-repo.

Outputs:
  dist/AerialFlow-<version>(<build>)-universal.dmg
  dist/AerialFlow-<version>(<build>)-universal.dmg.sha256.txt
  dist/sparkle/appcast.xml (if --sparkle-tag is provided)
EOF
}

NOTARY_PROFILE="${NOTARYTOOL_PROFILE:-}"
IDENTITY="${SIGN_IDENTITY:-}"
SPARKLE_TAG="${SPARKLE_TAG:-}"
SPARKLE_REPO="${SPARKLE_REPO:-second-arrow/AerialFlow}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --notary-profile)
      NOTARY_PROFILE="${2:-}"; shift 2 ;;
    --identity)
      IDENTITY="${2:-}"; shift 2 ;;
    --sparkle-tag)
      SPARKLE_TAG="${2:-}"; shift 2 ;;
    --sparkle-repo)
      SPARKLE_REPO="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown arg: $1" ;;
  esac
done

[[ -n "${NOTARY_PROFILE}" ]] || { usage; die "Missing --notary-profile (or set NOTARYTOOL_PROFILE)"; }

require_cmd /usr/bin/xcodebuild
require_cmd /usr/bin/ditto
require_cmd /usr/sbin/spctl

ROOT="$(repo_root)"
PROJECT="${ROOT}/AerialFlow/AerialFlow.xcodeproj"
SCHEME="AerialFlow"
DERIVED="${ROOT}/.derivedData"
TMP_BASE="${ROOT}/.tmp/release"
DIST="${ROOT}/dist"

rm -rf "${TMP_BASE}"
mkdir -p "${TMP_BASE}" "${DIST}"

log "Resolving version/build…"
BUILD_SETTINGS="$(/usr/bin/xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -configuration Release -showBuildSettings -derivedDataPath "${DERIVED}")"
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
  # Fallback for any layout differences.
  APP_BUILT_PATH="$(/usr/bin/find "${DERIVED}/Build/Products" -maxdepth 4 -type d -name "${APP_NAME}.app" -path "*/Release/*" | /usr/bin/head -n 1 || true)"
fi
[[ -n "${APP_BUILT_PATH}" ]] || die "Could not locate built app in ${DERIVED}/Build/Products"
[[ -d "${APP_BUILT_PATH}" ]] || die "Built app not found: ${APP_BUILT_PATH}"

STAGED_APP="${TMP_BASE}/${APP_NAME}.app"
log "Staging app…"
cp -R "${APP_BUILT_PATH}" "${STAGED_APP}"

log "Signing app…"
if [[ -n "${IDENTITY}" ]]; then
  "${SCRIPT_DIR}/sign_app.sh" "${STAGED_APP}" --identity "${IDENTITY}"
else
  "${SCRIPT_DIR}/sign_app.sh" "${STAGED_APP}"
fi

ZIP_PATH="${TMP_BASE}/${APP_NAME}.zip"
log "Creating notarization zip…"
rm -f "${ZIP_PATH}"
/usr/bin/ditto -c -k --keepParent "${STAGED_APP}" "${ZIP_PATH}"

log "Notarizing zip + stapling app…"
${SCRIPT_DIR}/notarize.sh --profile "${NOTARY_PROFILE}" --file "${ZIP_PATH}" --staple "${STAGED_APP}"

DMG_NAME="${APP_NAME}-${VERSION}(${BUILD})-universal.dmg"
DMG_PATH="${DIST}/${DMG_NAME}"

log "Creating DMG…"
${SCRIPT_DIR}/make_dmg.sh --app "${STAGED_APP}" --out "${DMG_PATH}" --volname "${APP_NAME}"

log "Notarizing DMG + stapling DMG…"
${SCRIPT_DIR}/notarize.sh --profile "${NOTARY_PROFILE}" --file "${DMG_PATH}" --staple "${DMG_PATH}"

log "Final verification (spctl)…"
/usr/sbin/spctl -a -vv --type open "${DMG_PATH}"

if [[ -n "${SPARKLE_TAG}" ]]; then
  log "Generating Sparkle appcast (tag=${SPARKLE_TAG}, repo=${SPARKLE_REPO})…"
  "${SCRIPT_DIR}/sparkle_generate_appcast.sh" \
    --tag "${SPARKLE_TAG}" \
    --repo "${SPARKLE_REPO}" \
    --derived-data "${DERIVED}" \
    --dmg "${DMG_PATH}"
fi

log "Done:"
log "  ${DMG_PATH}"
log "  ${DMG_PATH}.sha256.txt"
if [[ -n "${SPARKLE_TAG}" ]]; then
  log "  ${DIST}/sparkle/appcast.xml"
fi

