#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/lib/common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  Scripts/lib/check_notary_profile.sh <profile-name> [--test-with-file <path>]
  Scripts/lib/check_notary_profile.sh --api-key <key.p8> --key-id <id> --issuer <uuid> [--test-with-file <path>]

Checks if a notarytool keychain profile exists or validates API key credentials, and optionally tests it.

Examples:
  Scripts/lib/check_notary_profile.sh AerialFlowNotary
  Scripts/lib/check_notary_profile.sh AerialFlowNotary --test-with-file /path/to/test.zip
  Scripts/lib/check_notary_profile.sh --api-key ~/AuthKey.p8 --key-id ABC123DEFG --issuer YOUR-ISSUER-UUID
EOF
}

PROFILE=""
API_KEY=""
KEY_ID=""
ISSUER=""
TEST_FILE=""

# Check if first arg is a flag (API key mode) or profile name
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
elif [[ "${1:-}" == "--api-key" || "${1:-}" == "--key-id" || "${1:-}" == "--issuer" ]]; then
  # API key mode
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --api-key)
        API_KEY="${2:-}"; shift 2 ;;
      --key-id)
        KEY_ID="${2:-}"; shift 2 ;;
      --issuer)
        ISSUER="${2:-}"; shift 2 ;;
      --test-with-file)
        TEST_FILE="${2:-}"; shift 2 ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        die "Unknown arg: $1" ;;
    esac
  done
  [[ -n "${API_KEY}" ]] || { usage; die "Missing --api-key"; }
  [[ -n "${KEY_ID}" ]] || { usage; die "Missing --key-id"; }
  [[ -n "${ISSUER}" ]] || { usage; die "Missing --issuer"; }
  [[ -e "${API_KEY}" ]] || die "API key file not found: ${API_KEY}"
else
  # Profile mode
  PROFILE="${1:-}"
  if [[ -z "${PROFILE}" ]]; then
    usage
    exit 0
  fi
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --test-with-file)
        TEST_FILE="${2:-}"; shift 2 ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        die "Unknown arg: $1" ;;
    esac
  done
fi

require_cmd /usr/bin/xcrun

if [[ -n "${PROFILE}" ]]; then
  # Profile mode
  log "Checking notary profile: ${PROFILE}"

  # Method 1: Try to validate the profile
  log ""
  log "Step 1: Validating profile..."
  if xcrun notarytool store-credentials "${PROFILE}" --validate >/dev/null 2>&1; then
    log "✓ Profile '${PROFILE}' exists and is valid"
    PROFILE_EXISTS=1
  else
    log "✗ Profile '${PROFILE}' not found or invalid"
    PROFILE_EXISTS=0
  fi

  # Method 2: Check keychain directly
  log ""
  log "Step 2: Checking keychain..."
  if security find-generic-password -s "${PROFILE}" >/dev/null 2>&1; then
    log "✓ Profile found in keychain"
    KEYCHAIN_EXISTS=1
  else
    log "✗ Profile not found in keychain"
    KEYCHAIN_EXISTS=0
  fi

  # If profile doesn't exist, provide setup instructions
  if [[ "${PROFILE_EXISTS}" == "0" ]]; then
    log ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "SETUP REQUIRED: Profile '${PROFILE}' does not exist"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log ""
    log "To create this profile, run:"
    log "  xcrun notarytool store-credentials ${PROFILE}"
    log ""
    log "This will prompt you for:"
    log "  1. Apple ID (email address)"
    log "  2. App-specific password"
    log "     → Create one at: https://appleid.apple.com/account/manage"
    log "     → Sign in → App-Specific Passwords → Generate"
    log "  3. Team ID"
    log "     → Found in Apple Developer account: https://developer.apple.com/account"
    log "     → Membership section shows Team ID"
    log ""
    log "Alternative: Use App Store Connect API key method:"
    log "  xcrun notarytool store-credentials ${PROFILE} \\"
    log "    --apple-id <your-apple-id> \\"
    log "    --team-id <your-team-id> \\"
    log "    --key <path-to-key.p8> \\"
    log "    --key-id <key-id> \\"
    log "    --issuer <issuer-id>"
    log ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
  fi

  # Method 3: Test with a file if provided
  if [[ -n "${TEST_FILE}" ]]; then
    log ""
    log "Step 3: Testing profile with file: ${TEST_FILE}"
    if [[ ! -f "${TEST_FILE}" ]]; then
      die "Test file not found: ${TEST_FILE}"
    fi
    
    log "Submitting for notarization (this may take a few minutes)..."
    if xcrun notarytool submit "${TEST_FILE}" --keychain-profile "${PROFILE}" --wait 2>&1; then
      log "✓ Notarization test successful!"
    else
      log "✗ Notarization test failed"
      exit 1
    fi
  else
    log ""
    log "Step 3: Skipped (no test file provided)"
    log "To test the profile, use: --test-with-file <path>"
  fi

  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "✓ Profile '${PROFILE}' appears to be configured correctly."
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  # API key mode
  log "Checking API key credentials..."
  log "  Key file: ${API_KEY}"
  log "  Key ID: ${KEY_ID}"
  log "  Issuer: ${ISSUER}"

  log ""
  log "Step 1: Validating API key file..."
  if [[ ! -f "${API_KEY}" ]]; then
    die "API key file not found: ${API_KEY}"
  fi
  log "✓ API key file exists"

  log ""
  log "Step 2: Testing API key authentication..."
  if xcrun notarytool history \
    --key "${API_KEY}" \
    --key-id "${KEY_ID}" \
    --issuer "${ISSUER}" \
    >/dev/null 2>&1; then
    log "✓ API key authentication successful"
    API_KEY_VALID=1
  else
    log "✗ API key authentication failed"
    log "  Check that:"
    log "    - Key ID and Issuer ID are correct"
    log "    - The API key has not been revoked"
    log "    - The API key has proper permissions"
    API_KEY_VALID=0
  fi

  if [[ "${API_KEY_VALID}" == "0" ]]; then
    log ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "SETUP REQUIRED: API key validation failed"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log ""
    log "To create a new API key:"
    log "  1. Go to: https://appstoreconnect.apple.com/access/api"
    log "  2. Click '+' to create a new key"
    log "  3. Download the .p8 file immediately (only available once)"
    log "  4. Note the Key ID and Issuer ID"
    log ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
  fi

  # Method 3: Test with a file if provided
  if [[ -n "${TEST_FILE}" ]]; then
    log ""
    log "Step 3: Testing API key with file: ${TEST_FILE}"
    if [[ ! -f "${TEST_FILE}" ]]; then
      die "Test file not found: ${TEST_FILE}"
    fi
    
    log "Submitting for notarization (this may take a few minutes)..."
    if xcrun notarytool submit "${TEST_FILE}" \
      --key "${API_KEY}" \
      --key-id "${KEY_ID}" \
      --issuer "${ISSUER}" \
      --wait 2>&1; then
      log "✓ Notarization test successful!"
    else
      log "✗ Notarization test failed"
      exit 1
    fi
  else
    log ""
    log "Step 3: Skipped (no test file provided)"
    log "To test the API key, use: --test-with-file <path>"
  fi

  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "✓ API key appears to be configured correctly."
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi
