#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# EUQUERO3D AI PLATFORM — DigitalOcean Deploy Script v1.0
# Run: curl -fsSL https://raw.githubusercontent.com/euquero3d/ai-platform/main/install.sh | bash
# ═══════════════════════════════════════════════════════════════

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

PROJECT_DIR="/opt/euquero3d-ai"
REPO_URL="https://github.com/euquero3d/ai-platform.git"

echo -e "${PURPLE}"
cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║     ███████╗██╗   ██╗ ██████╗ ██╗   ██╗███████╗██████╗  ██████╗ ██████╗ 
║     ██╔════╝██║   ██║██╔═══██╗██║   ██║██╔════╝██╔══██╗██╔═══██╗╚════██╗
║     █████╗  ██║   ██║██║   ██║██║   ██║█████╗  ██████╔╝██║   ██║ █████╔╝
║     ██╔══╝  ╚██╗ ██╔╝██║   ██║╚██╗ ██╔╝██╔══╝  ██╔══██╗██║   ██║██╔═══╝ 
║     ███████╗ ╚████╔╝ ╚██████╔╝ ╚████╔╝ ███████╗██║  ██║╚██████╔╝███████╗
║     ╚══════╝  ╚═══╝   ╚═════╝   ╚═══╝  ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝
║                                                                ║
║              AI PLATFORM — from desire to reality ▮            ║
║                         v2.0.0                                 ║
╚════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# ── Check root ──
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} Execute como root: sudo bash install.sh"
    exit 1
fi

# ── Detect OS ──
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
else
    echo -e "${RED}[ERROR]${NC} OS não suportado. Use Ubuntu 22.04+"
    exit 1
fi

echo -e "${CYAN}[INFO]${NC} OS detectado: $OS $VER"

# ── Update system ──
echo -e "${YELLOW}[1/10]${NC} Atualizando sistema..."
apt-get update -qq
apt-get upgrade -y -qq

# ── Install base packages ──
echo -e "${YELLOW}[2/10]${NC} Instalando dependências base..."
apt-get install -y -qq     curl wget git htop nano unzip     apt-transport-https ca-certificates     gnupg lsb-release software-properties-common     ufw fail2ban

# ── Install Docker ──
echo -e "${YELLOW}[3/10]${NC} Instalando Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker ${SUDO_USER:-root}
    systemctl enable docker
    systemctl start docker
    echo -e "${GREEN}[OK]${NC} Docker instalado"
else
    echo -e "${GREEN}[OK]${NC} Docker já instalado"
fi

# ── Install Docker Compose ──
echo -e "${YELLOW}[4/10]${NC} Instalando Docker Compose..."
if ! docker compose version &> /dev/null; then
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    echo -e "${GREEN}[OK]${NC} Docker Compose instalado"
else
    echo -e "${GREEN}[OK]${NC} Docker Compose já instalado"
fi

# ── Setup project directory ──
echo -e "${YELLOW}[5/10]${NC} Configurando diretório do projeto..."
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Clone or update
if [ -d ".git" ]; then
    echo -e "${CYAN}[INFO]${NC} Repositório existente. Atualizando..."
    git pull origin main || true
else
    echo -e "${CYAN}[INFO]${NC} Clonando repositório..."
    git clone $REPO_URL . || {
        echo -e "${YELLOW}[WARN]${NC} Repo não acessível. Criando estrutura manual..."
        mkdir -p backend/app frontend/src worker/app nginx
    }
fi

# ── Create .env ──
echo -e "${YELLOW}[6/10]${NC} Criando configurações..."
if [ ! -f .env ]; then
    cat > .env << 'ENVEOF'
# ═══════════════════════════════════════════
# EUQUERO3D AI PLATFORM — Production Config
# ═══════════════════════════════════════════

# Database (MUDE AS SENHAS!)
DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)

# MinIO
MINIO_USER=euquero3d
MINIO_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)

# App Security
SECRET_KEY=$(openssl rand -base64 64)

# Domain
DOMAIN=ai.euquero3d.com.br

# Worker Mode: cpu_fallback | gpu
WORKER_MODE=cpu_fallback

# Optional: HuggingFace Token
# HUGGINGFACE_TOKEN=hf_xxxxxxxx
ENVEOF
    echo -e "${GREEN}[OK]${NC} Arquivo .env criado"
    echo -e "${YELLOW}[WARN]${NC} EDITE O ARQUIVO .env ANTES DE CONTINUAR!"
    echo -e "    nano $PROJECT_DIR/.env"
    read -p "Pressione ENTER após editar o .env..."
else
    echo -e "${GREEN}[OK]${NC} .env já existe"
fi

# ── Firewall ──
echo -e "${YELLOW}[7/10]${NC} Configurando firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# ── Build & Deploy ──
echo -e "${YELLOW}[8/10]${NC} Buildando containers..."
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml build --parallel

echo -e "${YELLOW}[9/10]${NC} Iniciando serviços..."
docker compose -f docker-compose.prod.yml up -d

# ── Wait for services ──
echo -e "${YELLOW}[10/10]${NC} Aguardando serviços..."
sleep 15

# Create MinIO buckets
docker exec e3d-minio mc alias set local http://localhost:9000 euquero3d $(grep MINIO_PASS .env | cut -d= -f2) 2>/dev/null || true
docker exec e3d-minio mc mb local/euquero3d-uploads 2>/dev/null || true
docker exec e3d-minio mc mb local/euquero3d-outputs 2>/dev/null || true

# ── SSL (Let's Encrypt) ──
echo -e "${CYAN}[INFO]${NC} Configurando SSL..."
DOMAIN=$(grep DOMAIN .env | cut -d= -f2 || echo "ai.euquero3d.com.br")

if command -v certbot &> /dev/null; then
    certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email hello@euquero3d.com.br || {
        echo -e "${YELLOW}[WARN]${NC} Certbot falhou. SSL será configurado pelo container."
    }
else
    echo -e "${YELLOW}[WARN]${NC} Certbot não instalado. SSL via container certbot."
fi

# ── Status ──
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    ✅ DEPLOY CONCLUÍDO!                         ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  🌐 Acesse:     https://$DOMAIN                              ║"
echo "║  🔌 API Docs:   https://$DOMAIN/docs                         ║"
echo "║  📊 MinIO:      https://$DOMAIN:9001                           ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "║  Comandos úteis:                                               ║"
echo "║    docker logs -f e3d-worker    # Logs do worker              ║"
echo "║    docker logs -f e3d-backend   # Logs da API                 ║"
echo "║    docker compose -f docker-compose.prod.yml ps               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${CYAN}print(you) // from desire to reality${NC}"
echo ""
echo -e "${YELLOW}IMPORTANTE:${NC}"
echo "  • Edite o DNS para apontar $DOMAIN → $(curl -s ifconfig.me)"
echo "  • O worker está em modo CPU (fallback). Para GPU real:"
echo "  • Use RunPod/Vast.ai com o script worker-gpu.sh"
echo ""
