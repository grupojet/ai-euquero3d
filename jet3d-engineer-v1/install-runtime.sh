#!/usr/bin/env bash
set -euo pipefail

APP_DIR=/opt/jet3d/app
DATA_DIR=/srv/jet3d/projects
VENV=/opt/jet3d/venv
ENV_DIR=/etc/jet3d
ENV_FILE=$ENV_DIR/jet3d.env
SERVICE_FILE=/etc/systemd/system/jet3d-api.service
BASE_URL=https://raw.githubusercontent.com/grupojet/ai-euquero3d/jet3d-engineer-v1/jet3d-engineer-v1
EXPECTED_SHA256=daa102150762bfd1fcd43405ee289c7c75b4b959d5e777f88a5a832e5319af89

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Execute como root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[1/8] Dependencias do sistema"
apt-get update
apt-get install -y python3 python3-venv python3-pip blender ufw curl ca-certificates openssl xz-utils

echo "[2/8] Baixando JET 3D Engineer V1"
rm -f /tmp/jet3d-part*.b64 /tmp/jet3d.tar.xz.b64 /tmp/jet3d.tar.xz
for n in 00 01 02 03; do
  curl -fL --retry 3 "$BASE_URL/part${n}.b64" -o "/tmp/jet3d-part${n}.b64"
done
cat /tmp/jet3d-part00.b64 /tmp/jet3d-part01.b64 /tmp/jet3d-part02.b64 /tmp/jet3d-part03.b64 > /tmp/jet3d.tar.xz.b64
base64 -d /tmp/jet3d.tar.xz.b64 > /tmp/jet3d.tar.xz
ACTUAL_SHA256=$(sha256sum /tmp/jet3d.tar.xz | awk '{print $1}')
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "Checksum invalido: $ACTUAL_SHA256" >&2
  exit 3
fi

echo "[3/8] Instalando arquivos"
mkdir -p "$APP_DIR" "$DATA_DIR" "$ENV_DIR"
rm -rf "$APP_DIR"/*
tar -xJf /tmp/jet3d.tar.xz -C "$APP_DIR"
test -f "$APP_DIR/pyproject.toml"
rm -f /tmp/jet3d-part*.b64 /tmp/jet3d.tar.xz.b64 /tmp/jet3d.tar.xz

echo "[4/8] Ambiente Python"
rm -rf "$VENV"
python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip wheel setuptools
"$VENV/bin/pip" install "$APP_DIR"

echo "[5/8] Configuracao segura"
if [ ! -s "$ENV_FILE" ]; then
  TOKEN=$(openssl rand -hex 32)
  cat > "$ENV_FILE" <<EOF
JET3D_HOST=127.0.0.1
JET3D_PORT=8765
JET3D_PROJECT_ROOT=$DATA_DIR
JET3D_API_TOKEN=$TOKEN
EOF
  chmod 600 "$ENV_FILE"
fi

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=JET 3D Engineer API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$VENV/bin/uvicorn engineering_service.app.main:app --host 127.0.0.1 --port 8765
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$DATA_DIR

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now jet3d-api.service

echo "[6/8] Firewall"
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 443/tcp
ufw --force enable

echo "[7/8] Validacao"
for i in $(seq 1 45); do
  if curl -fsS http://127.0.0.1:8765/health >/tmp/jet3d-health.json 2>/dev/null; then
    break
  fi
  if ! systemctl is-active --quiet jet3d-api.service; then
    echo "jet3d-api falhou ao iniciar" >&2
    journalctl -u jet3d-api.service --no-pager -n 100 >&2
    exit 4
  fi
  sleep 1
done
curl -fsS http://127.0.0.1:8765/health >/tmp/jet3d-health.json
"$VENV/bin/python" -c "from engineering_service.app.main import create_app; app=create_app(); print('FASTAPI_IMPORT_OK')"
blender --version | head -n 1

echo "[8/8] Resultado"
echo "=== JET3D HEALTH ==="
cat /tmp/jet3d-health.json
echo
echo "=== SERVICE ==="
systemctl --no-pager --full status jet3d-api.service | head -n 25
echo "=== FIREWALL ==="
ufw status
echo "=== API TOKEN (guarde em local seguro) ==="
grep '^JET3D_API_TOKEN=' "$ENV_FILE"
echo "=== INSTALACAO CONCLUIDA ==="
echo "API local: http://127.0.0.1:8765"
echo "Projetos: $DATA_DIR"
