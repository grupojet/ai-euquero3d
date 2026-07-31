#!/bin/bash
# ═══════════════════════════════════════════
# EUQUERO3D AI PLATFORM — Setup Script
# ═══════════════════════════════════════════

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     EUQUERO3D AI PLATFORM — Setup Automático v1.0           ║"
echo "║     from desire to reality ▮                               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Verificar Docker
echo -e "${YELLOW}[1/6]${NC} Verificando Docker..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker não encontrado. Instale primeiro:${NC}"
    echo "  curl -fsSL https://get.docker.com | sh"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "${RED}Docker Compose não encontrado. Instale primeiro.${NC}"
    exit 1
fi

# Verificar NVIDIA Docker (GPU)
echo -e "${YELLOW}[2/6]${NC} Verificando suporte a GPU NVIDIA..."
if ! docker info | grep -q "nvidia"; then
    echo -e "${YELLOW}Aviso: Runtime NVIDIA não detectado. O worker não usará GPU.${NC}"
    echo "  Para instalar: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
fi

# Verificar .env
echo -e "${YELLOW}[3/6]${NC} Verificando configurações..."
if [ ! -f .env ]; then
    echo -e "${YELLOW}Arquivo .env não encontrado. Criando a partir do exemplo...${NC}"
    cp .env.example .env
    echo -e "${RED}⚠️  IMPORTANTE: Edite o arquivo .env e configure suas senhas!${NC}"
fi

# Criar buckets no MinIO
echo -e "${YELLOW}[4/6]${NC} Criando buckets de storage..."
mkdir -p storage/models storage/uploads storage/outputs storage/previews

# Build das imagens
echo -e "${YELLOW}[5/6]${NC} Buildando containers (isso pode levar 10-20 minutos na primeira vez)..."
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

$COMPOSE_CMD build --parallel

# Subir serviços
echo -e "${YELLOW}[6/6]${NC} Iniciando serviços..."
$COMPOSE_CMD up -d

# Aguardar healthcheck
echo -e "${CYAN}Aguardando serviços ficarem prontos...${NC}"
sleep 10

# Criar bucket no MinIO
docker exec e3d-minio mc alias set local http://localhost:9000 euquero3d e3d_minio_2026_change_me 2>/dev/null || true
docker exec e3d-minio mc mb local/euquero3d-uploads 2>/dev/null || true
docker exec e3d-minio mc mb local/euquero3d-outputs 2>/dev/null || true

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              ✅ PLATAFORMA ONLINE!                            ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  🌐 Frontend:  http://localhost:3000                         ║"
echo "║  🔌 API:       http://localhost:8000/docs                    ║"
echo "║  📊 MinIO:     http://localhost:9001 (login: euquero3d)     ║"
echo "║  🧠 Worker:    Rodando em background                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}Próximos passos:${NC}"
echo "  1. Acesse http://localhost:3000 para usar a plataforma"
echo "  2. O worker vai baixar os modelos de IA na primeira execução (~15GB)"
echo "  3. Acompanhe logs: docker logs -f e3d-worker"
echo ""
echo -e "${CYAN}print(you) // from desire to reality${NC}"
