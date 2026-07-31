# 🚀 QUICK START — Servidor 159.223.116.50

## Passo 1: Subir os arquivos

No seu computador local (Windows/Mac/Linux), abra o terminal:

```bash
# Navegue até a pasta onde está o ZIP
cd ~/Downloads   # ou onde salvou

# Envie para o servidor
scp euquero3d-ai-platform-v2.0.0.zip root@159.223.116.50:/opt/
```

Se não tiver o ZIP, faça download primeiro.

## Passo 2: Conectar no servidor e extrair

```bash
ssh root@159.223.116.50

cd /opt
unzip euquero3d-ai-platform-v2.0.0.zip
cd euquero3d-ai-platform
```

## Passo 3: Executar o deploy

```bash
chmod +x deploy.sh
./deploy.sh
```

Isso vai:
- Instalar Docker (se não tiver)
- Buildar todos os containers
- Subir PostgreSQL, Redis, MinIO, Backend, Frontend
- Configurar firewall

## Passo 4: Acessar

Aguarde ~2 minutos e acesse:

| Serviço | URL |
|---------|-----|
| Plataforma (Frontend) | http://159.223.116.50:3000 |
| API Docs | http://159.223.116.50:8000/docs |
| MinIO Console | http://159.223.116.50:9001 |
| API direta | http://159.223.116.50:8000 |

Login MinIO: `euquero3d` / senha do `.env`

## Passo 5: Conectar Worker GPU (RunPod)

1. Vá em https://runpod.io
2. Crie um Pod:
   - Template: PyTorch 2.3
   - GPU: RTX 4090 (24GB)
   - Network: HTTP Port 8000
   - Volume: 50GB
3. No terminal do Pod, execute:

```bash
git clone https://github.com/Tencent-Hunyuan/Hunyuan3D-2.git /models/hunyuan3d2
git clone https://github.com/VAST-AI-Research/TripoSR.git /models/triposr

# Configure para apontar pro seu servidor
export REDIS_URL=redis://159.223.116.50:6379/0
export MINIO_ENDPOINT=159.223.116.50:9000
export MINIO_ACCESS_KEY=euquero3d
export MINIO_SECRET_KEY=SUA_SENHA_DO_ENV

# Rode o worker
python -u app/main.py
```

## Comandos úteis no servidor

```bash
# Ver containers rodando
docker compose ps

# Logs do worker
docker logs -f e3d-worker

# Logs da API
docker logs -f e3d-backend

# Restart tudo
docker compose restart

# Parar tudo
docker compose down

# Ver banco
docker exec -it e3d-postgres psql -U euquero3d -d euquero3d_ai
```

## ⚠️ IMPORTANTE

- **Este servidor não tem GPU.** O worker local gera apenas meshes placeholder.
- **Para geração 3D real**, conecte o worker GPU da RunPod (Passo 5).
- **Firewall:** Portas 3000, 8000, 9000, 9001 já liberadas no script.
- **SSL:** Configure com Cloudflare ou Let's Encrypt depois de apontar o domínio.

---

print(you) // from desire to reality
