#!/usr/bin/env bash
set -euo pipefail

APP_DIR=/opt/jet3d/app
DATA_DIR=/srv/jet3d/projects
VENV=/opt/jet3d/venv
ENV_DIR=/etc/jet3d
ENV_FILE=$ENV_DIR/jet3d.env
SERVICE_FILE=/etc/systemd/system/jet3d-api.service
BASE_URL=https://raw.githubusercontent.com/grupojet/ai-euquero3d/jet3d-engineer-v2/jet3d-runtime-v2
EXPECTED_SHA256=775fcd9af0e6591e5499804db2f0350e277e49353e3e9e9e5f14aa20782b73d3

[ "${EUID:-$(id -u)}" -eq 0 ] || { echo 'Execute como root' >&2; exit 1; }

echo '[1/7] Baixando runtime V2'
rm -f /tmp/jet3d-v2-part*.b64 /tmp/jet3d-v2.b64 /tmp/jet3d-v2.tar.gz
for n in 00 01 02; do
  curl -fL --retry 3 "$BASE_URL/part${n}.b64" -o "/tmp/jet3d-v2-part${n}.b64"
done

[ "$(wc -c </tmp/jet3d-v2-part00.b64)" -eq 8000 ] || { echo 'part00 tamanho invalido'; exit 2; }
[ "$(wc -c </tmp/jet3d-v2-part01.b64)" -eq 8000 ] || { echo 'part01 tamanho invalido'; exit 2; }
[ "$(wc -c </tmp/jet3d-v2-part02.b64)" -eq 5308 ] || { echo 'part02 tamanho invalido'; exit 2; }

cat /tmp/jet3d-v2-part00.b64 /tmp/jet3d-v2-part01.b64 /tmp/jet3d-v2-part02.b64 > /tmp/jet3d-v2.b64
base64 -d /tmp/jet3d-v2.b64 > /tmp/jet3d-v2.tar.gz
ACTUAL_SHA256=$(sha256sum /tmp/jet3d-v2.tar.gz | awk '{print $1}')
[ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] || { echo "SHA invalido: $ACTUAL_SHA256"; exit 3; }

echo '[2/7] Extraindo arquivos'
mkdir -p "$APP_DIR" "$DATA_DIR" "$ENV_DIR"
rm -rf "$APP_DIR"/*
tar -xzf /tmp/jet3d-v2.tar.gz -C "$APP_DIR"
test -f "$APP_DIR/pyproject.toml"

echo '[3/7] Instalando ambiente Python'
rm -rf "$VENV"
python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip setuptools wheel
"$VENV/bin/pip" install "$APP_DIR"

echo '[4/7] Configurando token e systemd'
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

echo '[5/7] Validando API'
for i in $(seq 1 30); do
  curl -fsS http://127.0.0.1:8765/health >/tmp/jet3d-health.json 2>/dev/null && break
  systemctl is-active --quiet jet3d-api.service || { journalctl -u jet3d-api.service --no-pager -n 100; exit 4; }
  sleep 1
done
curl -fsS http://127.0.0.1:8765/health >/tmp/jet3d-health.json

echo '[6/7] Validando Blender'
blender --version | head -n 1

echo '[7/7] Resultado'
echo '=== JET3D HEALTH ==='
cat /tmp/jet3d-health.json
echo
echo '=== SERVICE ==='
systemctl --no-pager --full status jet3d-api.service | head -n 20
echo '=== API TOKEN CONFIGURADO ==='
awk -F= '/^JET3D_API_TOKEN=/{print "JET3D_API_TOKEN=CONFIGURADO"}' "$ENV_FILE"
echo '=== INSTALACAO V2 CONCLUIDA ==='
