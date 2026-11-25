#!/usr/bin/env bash
set +x
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

if [[ $# != 1 || ( $1 != split && $1 != universal ) ]]; then
  echo "Usage: bash .cnb/build_apk.sh split|universal" >&2
  exit 2
fi
: "${TRAFARCH_KEYSTORE_BASE64:?Missing TRAFARCH_KEYSTORE_BASE64}"
: "${TRAFARCH_SIGNING_PROPERTIES_BASE64:?Missing TRAFARCH_SIGNING_PROPERTIES_BASE64}"

signing_dir=$(mktemp -d)
trap 'rm -rf -- "$signing_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export TRAFARCH_SIGNING_PROPERTIES="$signing_dir/key.properties"
(
  umask 077
  printf '%s' "$TRAFARCH_KEYSTORE_BASE64" | base64 --decode > "$signing_dir/release.keystore"
  printf '%s' "$TRAFARCH_SIGNING_PROPERTIES_BASE64" | base64 --decode > "$TRAFARCH_SIGNING_PROPERTIES"
)
unset TRAFARCH_KEYSTORE_BASE64 TRAFARCH_SIGNING_PROPERTIES_BASE64

python3 .cnb/build_apk.py "$1"
