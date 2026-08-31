#!/bin/zsh
set -euo pipefail

artifact_path="${1:?Usage: notarize.sh <artifact>}"
credentials=()

if [[ -n "${GLANCE_NOTARY_PROFILE:-}" ]]; then
  credentials+=(--keychain-profile "$GLANCE_NOTARY_PROFILE")
  if [[ -n "${GLANCE_NOTARY_KEYCHAIN:-}" ]]; then
    credentials+=(--keychain "$GLANCE_NOTARY_KEYCHAIN")
  fi
elif [[ -n "${GLANCE_NOTARY_KEY:-}${GLANCE_NOTARY_KEY_ID:-}${GLANCE_NOTARY_ISSUER_ID:-}" ]]; then
  if [[ -z "${GLANCE_NOTARY_KEY:-}" || -z "${GLANCE_NOTARY_KEY_ID:-}" || -z "${GLANCE_NOTARY_ISSUER_ID:-}" ]]; then
    print -u2 "API notarization requires GLANCE_NOTARY_KEY, GLANCE_NOTARY_KEY_ID, and GLANCE_NOTARY_ISSUER_ID."
    exit 1
  fi
  credentials+=(
    --key "$GLANCE_NOTARY_KEY"
    --key-id "$GLANCE_NOTARY_KEY_ID"
    --issuer "$GLANCE_NOTARY_ISSUER_ID"
  )
else
  print -u2 "No notarization credentials configured."
  exit 1
fi

xcrun notarytool submit "$artifact_path" "${credentials[@]}" --wait
xcrun stapler staple "$artifact_path"
xcrun stapler validate "$artifact_path"
