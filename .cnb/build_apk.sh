#!/usr/bin/env bash
set +x
set -euo pipefail
cd -- "$(dirname -- "$0")/.."

if [[ $# != 1 || ( $1 != split && $1 != universal ) ]]; then
  echo "Usage: bash .cnb/build_apk.sh split|universal" >&2
  exit 2
fi
: "${KEYSTORE_JKS_BASE64:?Missing KEYSTORE_JKS_BASE64}"
: "${KEY_PROPERTIES_BASE64:?Missing KEY_PROPERTIES_BASE64}"

signing_dir=$(mktemp -d)
trap 'rm -rf -- "$signing_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export TRAFARCH_SIGNING_PROPERTIES="$signing_dir/key.properties"
(
  umask 077
  printf '%s' "$KEYSTORE_JKS_BASE64" | tr -d '[:space:]' | base64 --decode > "$signing_dir/upload-keystore.jks"
  printf '%s' "$KEY_PROPERTIES_BASE64" | tr -d '[:space:]' | base64 --decode > "$TRAFARCH_SIGNING_PROPERTIES"
  # Java Properties uses the last definition. A blank line ends any continuation.
  printf '\n\nstoreFile=upload-keystore.jks\n' >> "$TRAFARCH_SIGNING_PROPERTIES"
)
unset KEYSTORE_JKS_BASE64 KEY_PROPERTIES_BASE64

python3 .cnb/build_apk.py "$1"
