#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/lib/common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  Scripts/lib/sparkle_generate_appcast.sh --tag <git-tag> [--repo <owner/repo>] [--derived-data <path>] [--updates-dir <dir>] --dmg <path-to-dmg>

What it does:
  - Copies the DMG into an updates folder
  - Runs Sparkle's generate_appcast to create:
    - appcast.xml
    - delta updates (if applicable)

Defaults:
  --repo         second-arrow/AerialFlow
  --derived-data <repo>/.derivedData
  --updates-dir  <repo>/dist/sparkle

Notes:
  - The app expects SUFeedURL to be:
      https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml
  - Enclosure URLs in the appcast are generated using:
      https://github.com/<owner>/<repo>/releases/download/<tag>/
  - You must upload the outputs (DMG, appcast.xml, and any .delta files) as assets to the GitHub release for <tag>.
EOF
}

TAG=""
REPO="second-arrow/AerialFlow"
DERIVED_DATA=""
UPDATES_DIR=""
DMG_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      TAG="${2:-}"; shift 2 ;;
    --repo)
      REPO="${2:-}"; shift 2 ;;
    --derived-data)
      DERIVED_DATA="${2:-}"; shift 2 ;;
    --updates-dir)
      UPDATES_DIR="${2:-}"; shift 2 ;;
    --dmg)
      DMG_PATH="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown arg: $1" ;;
  esac
done

[[ -n "${TAG}" ]] || { usage; die "Missing --tag"; }
[[ -n "${DMG_PATH}" ]] || { usage; die "Missing --dmg"; }
[[ -f "${DMG_PATH}" ]] || die "DMG not found: ${DMG_PATH}"

ROOT="$(repo_root)"
DERIVED_DATA="${DERIVED_DATA:-${ROOT}/.derivedData}"
UPDATES_DIR="${UPDATES_DIR:-${ROOT}/dist/sparkle}"

SPARKLE_BIN="${DERIVED_DATA}/SourcePackages/artifacts/sparkle/Sparkle/bin"
GENERATE_APPCAST="${SPARKLE_BIN}/generate_appcast"

[[ -x "${GENERATE_APPCAST}" ]] || die "Sparkle tool not found or not executable: ${GENERATE_APPCAST}. Run: xcodebuild -resolvePackageDependencies -derivedDataPath ${DERIVED_DATA}"

DOWNLOAD_PREFIX="https://github.com/${REPO}/releases/download/${TAG}/"

log "Preparing updates dir: ${UPDATES_DIR}"
rm -rf "${UPDATES_DIR}"
mkdir -p "${UPDATES_DIR}"

DMG_NAME="$(basename -- "${DMG_PATH}")"
log "Copying DMG into updates dir: ${DMG_NAME}"
cp -f "${DMG_PATH}" "${UPDATES_DIR}/${DMG_NAME}"

log "Generating appcast (download-url-prefix=${DOWNLOAD_PREFIX})…"
"${GENERATE_APPCAST}" \
  --download-url-prefix "${DOWNLOAD_PREFIX}" \
  "${UPDATES_DIR}"

APPCAST_PATH="${UPDATES_DIR}/appcast.xml"
[[ -f "${APPCAST_PATH}" ]] || die "Expected appcast not found at: ${APPCAST_PATH}"

log "Sparkle outputs:"
log "  ${APPCAST_PATH}"
log "  ${UPDATES_DIR}/${DMG_NAME}"
log "  (and any *.delta files in ${UPDATES_DIR})"
log ""
log "Next: upload these as assets to the GitHub release for tag: ${TAG}"

