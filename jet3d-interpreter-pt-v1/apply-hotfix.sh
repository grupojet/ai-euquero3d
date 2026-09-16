#!/usr/bin/env bash
set -euo pipefail

APP_DIR=/opt/jet3d/app
VENV=/opt/jet3d/venv
TARGET="$APP_DIR/engineering_service/app/planning/interpreter.py"
URL="https://raw.githubusercontent.com/grupojet/ai-euquero3d/jet3d-interpreter-pt-v1/jet3d-interpreter-pt-v1/interpreter.py"
TMP=/tmp/jet3d-interpreter.py

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Execute como root." >&2
  exit 1
fi

test -d "$APP_DIR"
test -x "$VENV/bin/python"
test -f "$TARGET"

cp -a "$TARGET" "${TARGET}.bak.$(date +%Y%m%d%H%M%S)"
curl -fsSL --retry 3 "$URL" -o "$TMP"
python3 -m py_compile "$TMP"
install -m 0644 "$TMP" "$TARGET"

cd "$APP_DIR"
"$VENV/bin/pip" install -q "$APP_DIR"
systemctl restart jet3d-api.service

for i in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8765/health >/tmp/jet3d-health.json 2>/dev/null; then
    break
  fi
  sleep 1
done
curl -fsS http://127.0.0.1:8765/health >/tmp/jet3d-health.json

"$VENV/bin/python" - <<'PY'
from engineering_service.app.planning.interpreter import interpret_instruction

box = interpret_instruction(
    "Crie uma caixa eletrônica de 180 x 120 x 55 mm com 4 parafusos M4, ventilação lateral, tampa removível, logo Grupo Jet em baixo-relevo e abertura para prensa-cabo de 20 mm.",
    {"revision": 0, "parameters": {}},
)
assert box["kind"] == "electronics_enclosure"
assert box["dimensions_mm"]["width"] == 180.0
assert box["fastener"] == {"count": 4, "metric": "M4"}
assert box["gland_diameter_mm"] == 20.0
assert box["removable_lid"] is True
assert box["logo_mode"] == "deboss"

revision = interpret_instruction(
    "altere a largura para 190 mm e a altura para 60 mm",
    {"revision": 1, "parameters": {}},
)
assert revision["changes"] == {"width_mm": 190.0, "height_mm": 60.0}

move = interpret_instruction(
    "mova o prensa-cabo 12 mm para a direita",
    {"revision": 1, "parameters": {}},
)
assert move["direction"] == "right"
print("PORTUGUESE_INTERPRETER_OK")
PY

echo "=== JET3D HEALTH ==="
cat /tmp/jet3d-health.json
echo
echo "=== INTERPRETADOR ==="
echo "PORTUGUESE_INTERPRETER_OK"
echo "=== HOTFIX CONCLUIDO ==="
