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
require_cmd /usr/bin/python3

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

tmp_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/aerialflow-entitlements.XXXXXX")"
cleanup() { rm -rf "${tmp_dir}"; }
trap cleanup EXIT

resign_with_preserved_entitlements() {
  local path="$1"

  # Best-effort: preserve existing entitlements (Sparkle helpers/XPCs often have them).
  local entitlements_file="${tmp_dir}/$(echo "${path}" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}').plist"
  if /usr/bin/codesign -d --entitlements :- "${path}" > "${entitlements_file}" 2>/dev/null && [[ -s "${entitlements_file}" ]]; then
    /usr/bin/codesign --force --options runtime --timestamp --sign "${IDENTITY}" --entitlements "${entitlements_file}" "${path}"
    return 0
  fi

  # If there are no entitlements (or extraction failed), do not pass --entitlements.
  rm -f "${entitlements_file}" || true
  /usr/bin/codesign --force --options runtime --timestamp --sign "${IDENTITY}" "${path}"
}

# Important: Do NOT rely on `codesign --deep` to propagate hardened runtime to nested code.
# Sign nested code explicitly first, then sign the app bundle last.
log "Signing nested components…"
/usr/bin/find "${APP_PATH}/Contents" \
  \( \
    -name "*.xpc" -o -name "*.app" -o -name "*.framework" -o -name "*.dylib" -o -name "*.so" \
    -o \( -type f -perm -111 \) \
  \) \
  -print0 \
| /usr/bin/python3 -c '
import os
import sys

app_path = os.path.realpath(sys.argv[1])
raw = sys.stdin.buffer.read().split(b"\0")

def is_macho(path: str) -> bool:
    # Detect Mach-O by magic (including FAT/universal). Avoid calling external `file`.
    try:
        with open(path, "rb") as f:
            magic = f.read(4)
    except OSError:
        return False
    if len(magic) != 4:
        return False
    # Known Mach-O and FAT magic values.
    return magic in (
        b"\xfe\xed\xfa\xce",  # MH_MAGIC
        b"\xce\xfa\xed\xfe",  # MH_CIGAM
        b"\xfe\xed\xfa\xcf",  # MH_MAGIC_64
        b"\xcf\xfa\xed\xfe",  # MH_CIGAM_64
        b"\xca\xfe\xba\xbe",  # FAT_MAGIC
        b"\xbe\xba\xfe\xca",  # FAT_CIGAM
    )

seen = set()
paths = []
for b in raw:
    if not b:
        continue
    p = b.decode("utf-8", errors="surrogateescape")
    rp = os.path.realpath(p)
    if rp == app_path:
        continue
    if rp in seen:
        continue
    # Keep bundle directories and libraries by name; keep only Mach-O for executables.
    if os.path.isdir(rp):
        seen.add(rp)
        paths.append(rp)
        continue
    if rp.endswith((".dylib", ".so")):
        seen.add(rp)
        paths.append(rp)
        continue
    if is_macho(rp):
        seen.add(rp)
        paths.append(rp)

# Sign deepest-first so parents (e.g. frameworks) are signed after their nested code.
paths.sort(key=lambda p: p.count(os.sep), reverse=True)
sys.stdout.write("\n".join(paths) + ("\n" if paths else ""))
' "${APP_PATH}" \
| while IFS= read -r nested || [[ -n "${nested}" ]]; do
  [[ -n "${nested}" ]] || continue
  resign_with_preserved_entitlements "${nested}"
done

log "Verifying Sparkle helpers are correctly signed (if present)…"
#
# Sparkle.framework contains an embedded helper executable named `Autoupdate`.
# Notarization rejects archives where this helper is not Developer ID–signed and timestamped.
#
shopt -s nullglob
sparkle_helpers=("${APP_PATH}"/Contents/Frameworks/Sparkle.framework/Versions/*/Autoupdate)
shopt -u nullglob
if [[ ${#sparkle_helpers[@]} -gt 0 ]]; then
  for helper in "${sparkle_helpers[@]}"; do
    [[ -f "${helper}" ]] || continue
    log "Checking: ${helper}"
    details="$(/usr/bin/codesign -dv --verbose=4 "${helper}" 2>&1 || true)"
    echo "${details}" | /usr/bin/grep -q 'Authority=Developer ID Application:' \
      || die "Sparkle helper is not signed with Developer ID Application: ${helper}"
    echo "${details}" | /usr/bin/grep -q '^Timestamp=' \
      || die "Sparkle helper signature missing secure timestamp: ${helper}"
  done
fi

log "Signing app bundle…"
resign_with_preserved_entitlements "${APP_PATH}"

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

