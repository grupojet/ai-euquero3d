# 🧠 EUQUERO3D AI PLATFORM v2.0.0

> **from desire to reality ▮**

Plataforma de geração de modelos 3D por Inteligência Artificial — **100% self-hosted, open-source, sem APIs de terceiros**.

```
Texto ou Imagem → IA (Hunyuan3D/TripoSR) → Mesh 3D → STL pronto para impressão
```

## 🎨 Identidade Visual

Baseado no **Manual de Marca euquero3d v2.0 — Tech Edition**:

| Token | Valor | Uso |
|-------|-------|-----|
| Cyber Violet | `#7C3AED` | Primária, gradientes |
| Neon Lime | `#C6F432` | Accent, CTAs, badges |
| Electric Cyan | `#22D3EE` | Secundária, HUD elements |
| Deep Space | `#0A0A0F` | Background |
| Ghost White | `#E5E5F0` | Texto |

**Tipografia**: Space Grotesk (display) + JetBrains Mono (UI técnica) + Inter (body)

## 🏗️ Arquitetura

```
┌─────────────────────────────────────────────────────────────┐
│  FRONTEND (Next.js 15) — Dark-mode native, Three.js viewer │
├─────────────────────────────────────────────────────────────┤
│  BACKEND (FastAPI) — REST API, WebSocket, PostgreSQL, Redis  │
├─────────────────────────────────────────────────────────────┤
│  WORKER GPU (PyTorch) — Hunyuan3D-2 + TripoSR inference      │
├─────────────────────────────────────────────────────────────┤
│  STORAGE (MinIO) — S3-compatible, uploads e outputs          │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Deploy Rápido

### DigitalOcean (Automático)

```bash
# SSH no seu droplet
ssh root@SEU_IP

# Execute o instalador
curl -fsSL https://raw.githubusercontent.com/euquero3d/ai-platform/main/install.sh | bash
```

### Manual (Qualquer servidor)

```bash
# 1. Clone
git clone https://github.com/euquero3d/ai-platform.git
cd euquero3d-ai-platform

# 2. Configure
cp .env.example .env
nano .env  # edite senhas e domínio

# 3. Suba
chmod +x setup.sh
./setup.sh
```

## 📁 Estrutura

```
├── docker-compose.yml          # Desenvolvimento local
├── docker-compose.prod.yml     # Produção (DigitalOcean)
├── install.sh                  # One-liner deploy
├── setup.sh                    # Setup local
├── DEPLOY.md                   # Guia completo
│
├── backend/                    # FastAPI + PostgreSQL + Redis
│   ├── app/
│   │   ├── main.py             # API principal
│   │   ├── api/jobs.py         # Endpoints de geração
│   │   ├── services/           # Queue, MinIO
│   │   └── models/job.py       # Schema do banco
│   └── Dockerfile
│
├── worker/                     # Motor de IA (GPU)
│   ├── app/
│   │   ├── main.py             # Worker loop (consome Redis)
│   │   └── pipeline/
│   │       ├── hunyuan3d.py    # Tencent Hunyuan3D-2
│   │       ├── triposr.py      # Stability TripoSR
│   │       ├── postprocess.py  # Watertight + STL + Preview
│   │       └── pricing.py      # Cálculo de orçamento
│   ├── Dockerfile              # GPU (CUDA 12.1)
│   └── Dockerfile.cpu          # CPU fallback
│
├── frontend/                   # Next.js 15 + Three.js
│   ├── src/
│   │   ├── app/page.tsx        # Página principal
│   │   ├── components/         # UI euquero3d branded
│   │   └── lib/api.ts          # Cliente HTTP
│   └── Dockerfile
│
└── nginx/
    ├── nginx.conf               # Desenvolvimento
    └── nginx.prod.conf          # Produção + SSL
```

## 🔧 Motores de IA

| Motor | Origem | Input | VRAM | Licença |
|-------|--------|-------|------|---------|
| **Hunyuan3D-2** | Tencent | Texto + Imagem | 24GB | Open weights |
| **TripoSR** | Stability/VAST | Imagem | 6GB | MIT |

> Sem Meshy. Sem Tripo API. Sem custos por geração.

## 💰 Custos (Self-Hosted)

| Componente | Custo Mensal |
|------------|-------------|
| VPS 8GB (DigitalOcean) | ~$48 |
| GPU Cloud (RunPod RTX 4090, 20h) | ~$40 |
| **Total** | **~$88/mês** |

Break-even: ~20 projetos/mês a R$45-120 cada.

## 🛠️ Comandos Úteis

```bash
# Logs
docker logs -f e3d-worker
docker logs -f e3d-backend

# Restart
docker compose -f docker-compose.prod.yml restart

# Update
git pull && docker compose -f docker-compose.prod.yml up -d --build

# Backup
docker exec e3d-postgres pg_dump -U euquero3d euquero3d_ai > backup.sql

# Acesso ao banco
docker exec -it e3d-postgres psql -U euquero3d -d euquero3d_ai
```

## 📜 Licença

MIT — Uso comercial permitido.

---

**euquero3d** • print(you) • from desire to reality ▮
