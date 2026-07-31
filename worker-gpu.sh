#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# EUQUERO3D AI WORKER — GPU Remote (RunPod / Vast.ai / Local GPU)
# Run this on a machine with NVIDIA GPU + CUDA
# ═══════════════════════════════════════════════════════════════

set -e

REDIS_URL="${REDIS_URL:-redis://localhost:6379/0}"
MINIO_ENDPOINT="${MINIO_ENDPOINT:-localhost:9000}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     EUQUERO3D AI WORKER — GPU Edition                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Redis: $REDIS_URL"
echo "MinIO: $MINIO_ENDPOINT"
echo ""

# Check GPU
if ! command -v nvidia-smi &> /dev/null; then
    echo "[ERROR] nvidia-smi não encontrado. GPU NVIDIA necessária."
    exit 1
fi

echo "[INFO] GPU detectada:"
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv

# Check CUDA
python3 -c "import torch; print(f'PyTorch: {torch.__version__}'); print(f'CUDA: {torch.version.cuda}'); print(f'GPU: {torch.cuda.get_device_name(0)}')" || {
    echo "[ERROR] PyTorch com CUDA não instalado"
    exit 1
}

# Install deps if needed
if [ ! -d "venv" ]; then
    echo "[INFO] Criando ambiente virtual..."
    python3 -m venv venv
fi

source venv/bin/activate
pip install -q -r requirements.txt

# Download models
echo "[INFO] Baixando modelos (primeira execução, ~15GB)..."
python3 -c "
from app.pipeline.hunyuan3d import Hunyuan3DEngine
from app.pipeline.triposr import TripoSREngine
print('Loading Hunyuan3D...')
h = Hunyuan3DEngine()
h.load()
print('Loading TripoSR...')
t = TripoSREngine()
t.load()
print('Models ready!')
"

# Run worker
echo "[INFO] Iniciando worker GPU..."
python3 -u app/main.py
