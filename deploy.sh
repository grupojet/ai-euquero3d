#!/bin/bash
set -e

echo "🚀 EUQUERO3D AI v2.1 — Deploy"

# Para tudo que está rodando
docker compose down 2>/dev/null || true

# Build e sobe
docker compose build --no-cache
docker compose up -d

echo "⏳ Aguardando serviços..."
sleep 10

echo "✅ Deploy concluído!"
echo "🌐 Frontend: http://159.223.116.50"
echo "🔌 API: http://159.223.116.50/api/v1"
echo "📊 MinIO Console: http://159.223.116.50:9001"

# Logs
docker logs -f e3d-worker &
docker logs -f e3d-backend &
