#!/usr/bin/env bash
set -euo pipefail

APP_DIR=/opt/jet3d/app
VENV=/opt/jet3d/venv
PROJECT_ROOT=/srv/jet3d/projects
BRANCH=jet3d-blender-worker-v1
BASE_URL="https://raw.githubusercontent.com/grupojet/ai-euquero3d/${BRANCH}/jet3d-blender-worker-v1"
STAGE=/tmp/jet3d-blender-worker-v1
BACKUP="/opt/jet3d/backups/blender-worker-$(date +%Y%m%d%H%M%S)"
ADDON_ARCHIVE=blender-addon-v1.tar.gz
FILES=(
  engineering_service/app/blender/__init__.py
  engineering_service/app/blender/jobs.py
  engineering_service/app/blender/service.py
  engineering_service/app/api/manufacturing.py
  engineering_service/app/main.py
  engineering_service/app/settings.py
  scripts/blender_headless_worker.py
  web/index.html
  web/styles.css
  web/js/preview.js
  web/js/api.js
  web/js/app.js
  deploy/install-web-ui.sh
)

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Execute como root." >&2
  exit 1
fi

test -d "$APP_DIR"
test -x "$VENV/bin/python"
test -d "$PROJECT_ROOT"
command -v blender >/dev/null
command -v curl >/dev/null

rm -rf "$STAGE"
mkdir -p "$STAGE" "$BACKUP/app" "$BACKUP/web"
for rel in "${FILES[@]}"; do
  mkdir -p "$STAGE/$(dirname "$rel")"
  curl -fsSL --retry 3 "$BASE_URL/files/$rel" -o "$STAGE/$rel"
done
curl -fsSL --retry 3 "$BASE_URL/$ADDON_ARCHIVE" -o "$STAGE/$ADDON_ARCHIVE"
curl -fsSL --retry 3 "$BASE_URL/manifest.sha256" -o "$STAGE/manifest.sha256"
(
  cd "$STAGE"
  sha256sum -c manifest.sha256
)

for rel in \
  engineering_service/app/blender/__init__.py \
  engineering_service/app/blender/jobs.py \
  engineering_service/app/blender/service.py \
  engineering_service/app/api/manufacturing.py \
  engineering_service/app/main.py \
  engineering_service/app/settings.py \
  scripts/blender_headless_worker.py; do
  if [ -f "$APP_DIR/$rel" ]; then
    mkdir -p "$BACKUP/app/$(dirname "$rel")"
    cp -a "$APP_DIR/$rel" "$BACKUP/app/$rel"
  fi
  install -D -m 0644 "$STAGE/$rel" "$APP_DIR/$rel"
done

if [ -d "$APP_DIR/blender_addon/jet_3d_engineer" ]; then
  mkdir -p "$BACKUP/app/blender_addon"
  cp -a "$APP_DIR/blender_addon/jet_3d_engineer" "$BACKUP/app/blender_addon/"
fi
rm -rf "$APP_DIR/blender_addon/jet_3d_engineer"
mkdir -p "$APP_DIR/blender_addon"
tar -xzf "$STAGE/blender-addon-v1.tar.gz" -C "$APP_DIR"
test -f "$APP_DIR/blender_addon/jet_3d_engineer/geometry/executor.py"

if [ -d /var/www/jet3d ]; then
  cp -a /var/www/jet3d/. "$BACKUP/web/"
fi

"$VENV/bin/python" -m py_compile \
  "$APP_DIR/engineering_service/app/blender/jobs.py" \
  "$APP_DIR/engineering_service/app/blender/service.py" \
  "$APP_DIR/engineering_service/app/api/manufacturing.py" \
  "$APP_DIR/scripts/blender_headless_worker.py"
"$VENV/bin/pip" install -q "$APP_DIR"

systemctl restart jet3d-api.service
for i in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8765/health >/tmp/jet3d-health.json 2>/dev/null; then
    break
  fi
  sleep 1
done
curl -fsS http://127.0.0.1:8765/health >/tmp/jet3d-health.json

SMOKE=/tmp/jet3d-blender-smoke
rm -rf "$SMOKE"
mkdir -p "$SMOKE/project/exports/r001" "$SMOKE/project/assets"
cat > "$SMOKE/job.json" <<EOF
{
  "schema_version": 1,
  "project_id": "smoke",
  "revision": 1,
  "export_version": 1,
  "project_root": "$SMOKE/project",
  "blend_path": "$SMOKE/project/project.blend",
  "export_dir": "$SMOKE/project/exports/r001",
  "operation_graph": [
    {"id":"base","type":"create_box","part":"body","parameters":{"width_mm":20,"depth_mm":20,"height_mm":10}}
  ],
  "printer_profile": "creality-k2-plus",
  "material_profile": "petg",
  "asset_registry": {}
}
EOF
if ! blender --background --factory-startup --python "$APP_DIR/scripts/blender_headless_worker.py" -- "$SMOKE/job.json" "$SMOKE/result.json" >/tmp/jet3d-blender-smoke.log 2>&1; then
  echo "=== BLENDER SMOKE LOG ===" >&2
  cat /tmp/jet3d-blender-smoke.log >&2
  exit 1
fi
if [ ! -f "$SMOKE/result.json" ]; then
  echo "Blender smoke test did not produce result.json" >&2
  echo "=== BLENDER SMOKE LOG ===" >&2
  cat /tmp/jet3d-blender-smoke.log >&2
  exit 1
fi
"$VENV/bin/python" - <<'PY'
import json
from pathlib import Path
p = Path('/tmp/jet3d-blender-smoke')
result = json.loads((p/'result.json').read_text(encoding='utf-8'))
assert result['status'] == 'ok', result
assert (p/'project/project.blend').is_file()
assert any((p/'project'/rel).is_file() for rel in result['stl_parts'])
assert result['object_signatures']
print('BLENDER_SMOKE_OK')
PY

TOKEN=$(sed -n 's/^JET3D_API_TOKEN=//p' /etc/jet3d/jet3d.env | head -n1)
AUTH=()
if [ -n "$TOKEN" ]; then AUTH=(-H "Authorization: Bearer $TOKEN"); fi
HTTP_CODE=$(curl -sS -o /tmp/jet3d-manufacturing-route.json -w '%{http_code}' "${AUTH[@]}" http://127.0.0.1:8765/v1/projects/nonexistent/manufacturing/status)
if [ "$HTTP_CODE" != "404" ]; then
  cat /tmp/jet3d-manufacturing-route.json
  echo "Manufacturing API route check failed: HTTP $HTTP_CODE" >&2
  exit 1
fi
echo "MANUFACTURING_API_OK"

bash "$STAGE/deploy/install-web-ui.sh"

echo "=== JET3D HEALTH ==="
cat /tmp/jet3d-health.json
echo
echo "BLENDER_SMOKE_OK"
echo "MANUFACTURING_API_OK"
echo "=== BLENDER WORKER V1 INSTALADO ==="
