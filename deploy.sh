#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# EUQUERO3D AI PLATFORM — Deploy Script
# Servidor: 159.223.116.50
# Execute: bash deploy.sh
# ═══════════════════════════════════════════════════════════════

set -e

IP="159.223.116.50"
PROJECT_DIR="/opt/euquero3d-ai"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     🧠 EUQUERO3D AI PLATFORM — Deploy v2.0.0                 ║"
echo "║     Servidor: $IP                                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# ── Verificar root ──
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Execute como root: sudo bash deploy.sh"
    exit 1
fi

# ── Verificar Docker ──
if ! command -v docker &> /dev/null; then
    echo "[1/8] Instalando Docker..."
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker root
    systemctl enable docker
    systemctl start docker
else
    echo "[1/8] Docker já instalado ✓"
fi

if ! docker compose version &> /dev/null && ! docker-compose version &> /dev/null; then
    echo "[2/8] Instalando Docker Compose..."
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
else
    echo "[2/8] Docker Compose já instalado ✓"
fi

# ── Diretório do projeto ──
echo "[3/8] Preparando diretório..."
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# ── Baixar pacote ──
echo "[4/8] Baixando pacote..."
if [ ! -f "docker-compose.yml" ]; then
    # Se o pacote foi enviado via SCP, ele já está aqui
    # Senão, tenta baixar do gist/temp
    echo "[INFO] Pacote não encontrado. Certifique-se de que os arquivos estão em $PROJECT_DIR"
fi

# ── Configurar .env ──
echo "[5/8] Configurando ambiente..."
if [ ! -f ".env" ]; then
    cat > .env << 'EOF'
DB_PASSWORD=e3d_prod_$(openssl rand -hex 8)
MINIO_USER=euquero3d
MINIO_PASS=e3d_minio_$(openssl rand -hex 8)
SECRET_KEY=$(openssl rand -hex 32)
EOF
    echo "[WARN] Arquivo .env criado com senhas aleatórias."
    echo "[WARN] EDITE o .env se quiser configurar domínio ou HuggingFace token."
fi

# ── Firewall ──
echo "[6/8] Configurando firewall..."
ufw default deny incoming 2>/dev/null || true
ufw default allow outgoing 2>/dev/null || true
ufw allow ssh 2>/dev/null || true
ufw allow 80/tcp 2>/dev/null || true
ufw allow 443/tcp 2>/dev/null || true
ufw allow 8000/tcp 2>/dev/null || true
ufw allow 3000/tcp 2>/dev/null || true
ufw allow 9000/tcp 2>/dev/null || true
ufw allow 9001/tcp 2>/dev/null || true
ufw --force enable 2>/dev/null || true

# ── Build e deploy ──
echo "[7/8] Buildando containers..."
if docker compose version &> /dev/null; then
    COMPOSE="docker compose"
else
    COMPOSE="docker-compose"
fi

$COMPOSE -f docker-compose.yml pull 2>/dev/null || true
$COMPOSE -f docker-compose.yml build --parallel

echo "[8/8] Iniciando serviços..."
$COMPOSE -f docker-compose.yml up -d

# ── Aguardar ──
echo ""
echo "[INFO] Aguardando serviços iniciarem..."
sleep 15

# ── Criar buckets MinIO ──
docker exec e3d-minio mc alias set local http://localhost:9000 euquero3d $(grep MINIO_PASS .env | cut -d= -f2) 2>/dev/null || true
docker exec e3d-minio mc mb local/euquero3d-uploads 2>/dev/null || true
docker exec e3d-minio mc mb local/euquero3d-outputs 2>/dev/null || true

# ── Status ──
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    ✅ DEPLOY CONCLUÍDO!                        ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  🌐 Frontend:  http://$IP:3000                                ║"
echo "║  🔌 API Docs:  http://$IP:8000/docs                           ║"
echo "║  📊 MinIO:     http://$IP:9001 (login: euquero3d)              ║"
echo "║  💾 API:       http://$IP:8000                                 ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Comandos úteis:                                               ║"
echo "║    docker logs -f e3d-worker                                  ║"
echo "║    docker logs -f e3d-backend                                 ║"
echo "║    docker compose -f docker-compose.yml ps                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "[IMPORTANTE] Este servidor NÃO tem GPU. O worker roda em modo"
echo "             CPU com fallback (meshes básicas)."
echo ""
echo "             Para geração 3D real com IA, conecte um worker GPU"
echo "             remoto (RunPod/Vast.ai) usando worker-gpu.sh"
echo ""
echo "print(you) // from desire to reality"
echo ""
