#!/usr/bin/env bash
set -euo pipefail
URL="https://raw.githubusercontent.com/grupojet/ai-euquero3d/jet3d-web-ui-v1/jet3d-web-ui-v1/jet3d-web-ui-v1.tar.gz"
EXPECTED_SHA256="e622be1a567c33c4296c82084e365c8c100fee286ae9f3acc858bb762a89f8ca"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl -fL --retry 3 "$URL" -o "$TMP_DIR/jet3d-web-ui-v1.tar.gz"
ACTUAL_SHA256="$(sha256sum "$TMP_DIR/jet3d-web-ui-v1.tar.gz" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "Checksum invalido: $ACTUAL_SHA256" >&2
  exit 3
fi
tar -xzf "$TMP_DIR/jet3d-web-ui-v1.tar.gz" -C "$TMP_DIR"
bash "$TMP_DIR/deploy/install-web-ui.sh"
