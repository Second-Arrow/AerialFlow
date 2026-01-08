#!/usr/bin/env bash
set -euo pipefail

log() {
  # shellcheck disable=SC2145
  echo "[AerialFlow][release] $@" 1>&2
}

die() {
  log "ERROR: $*"
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

repo_root() {
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  (cd -- "${script_dir}/../.." && pwd)
}

