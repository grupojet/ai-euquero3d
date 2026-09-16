#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_SOURCE="$SOURCE_ROOT/web"
WEB_ROOT=/var/www/jet3d
ENV_FILE=/etc/jet3d/jet3d.env
AUTH_SNIPPET=/etc/nginx/snippets/jet3d-auth.conf
SITE=/etc/nginx/sites-available/jet3d
ENABLED=/etc/nginx/sites-enabled/jet3d

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Execute como root." >&2
  exit 1
fi

if [ ! -d "$WEB_SOURCE" ] || [ ! -f "$WEB_SOURCE/index.html" ]; then
  echo "Arquivos web nao encontrados em $WEB_SOURCE" >&2
  exit 2
fi
if [ ! -r "$ENV_FILE" ]; then
  echo "Configuracao da API nao encontrada: $ENV_FILE" >&2
  exit 3
fi

API_TOKEN="$(awk -F= '$1=="JET3D_API_TOKEN" {sub(/^[^=]*=/,""); print; exit}' "$ENV_FILE")"
if ! printf '%s' "$API_TOKEN" | grep -Eq '^[A-Za-z0-9._~-]{20,256}$'; then
  echo "JET3D_API_TOKEN ausente ou invalido." >&2
  exit 4
fi

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx curl ca-certificates

install -d -m 0755 "$WEB_ROOT" /etc/nginx/snippets
rm -rf "$WEB_ROOT"/*
cp -a "$WEB_SOURCE"/. "$WEB_ROOT"/
find "$WEB_ROOT" -type d -exec chmod 0755 {} +
find "$WEB_ROOT" -type f -exec chmod 0644 {} +

cat > "$AUTH_SNIPPET" <<EOF
set \$jet3d_api_token "$API_TOKEN";
proxy_set_header Authorization "Bearer \$jet3d_api_token";
EOF
chmod 0600 "$AUTH_SNIPPET"
chown root:root "$AUTH_SNIPPET"

if [ -f "$SITE" ] && [ ! -f "${SITE}.pre-web-ui" ]; then
  cp -a "$SITE" "${SITE}.pre-web-ui"
fi

cat > "$SITE" <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/jet3d;
    index index.html;

    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;

    location = /health {
        proxy_pass http://127.0.0.1:8765/health;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }

    location /api/ {
        include /etc/nginx/snippets/jet3d-auth.conf;
        proxy_pass http://127.0.0.1:8765/v1/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 240s;
        proxy_send_timeout 240s;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }

    location ~* \.(?:css|js|png|jpg|jpeg|svg|ico|woff2?)$ {
        expires 1h;
        add_header Cache-Control "public, max-age=3600";
        try_files $uri =404;
    }
}
NGINX

rm -f /etc/nginx/sites-enabled/default
ln -sfn "$SITE" "$ENABLED"

nginx -t
systemctl enable nginx >/dev/null
systemctl reload nginx || systemctl restart nginx

if command -v ufw >/dev/null 2>&1; then
  ufw allow 80/tcp >/dev/null || true
fi

curl -fsS http://127.0.0.1/health >/tmp/jet3d-web-health.json
curl -fsS http://127.0.0.1/ | grep -q "JET 3D Engineer"
curl -fsS http://127.0.0.1/api/profiles/printers/creality-k2-plus >/tmp/jet3d-web-api-check.json

echo "=== JET3D WEB HEALTH ==="
cat /tmp/jet3d-web-health.json
echo
echo "=== JET3D WEB UI ==="
echo "Interface: http://$(hostname -I | awk '{print $1}')/"
echo "API proxy: OK"
echo "Token: mantido somente no servidor"
echo "=== INSTALACAO WEB CONCLUIDA ==="
