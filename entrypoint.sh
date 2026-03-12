#!/bin/bash
# =============================================================================
# BitNet b1.58 2B — entrypoint
# O build já foi feito no Dockerfile (stage builder)
# Este script apenas: baixa o modelo se necessário e inicia o servidor
# =============================================================================
set -e

MODEL_DIR="/models"
MODEL_FILE="$MODEL_DIR/ggml-model-i2_s.gguf"
THREADS=${BITNET_THREADS:-3}
CTX=${BITNET_CTX:-4096}
PORT=${BITNET_PORT:-8080}
TEMP=${BITNET_TEMPERATURE:-0.0}

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     BitNet b1.58 2B — CPU Inference      ║"
echo "╠══════════════════════════════════════════╣"
echo "║  Threads : $THREADS | Context : $CTX | Porta : $PORT  ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ─── PASSO 1: Modelo ──────────────────────────────────────────────────────────
# O modelo não vai na imagem (muito grande) — baixa uma vez no volume
if [ ! -f "$MODEL_FILE" ]; then
    echo "▶ [1/2] Baixando modelo BitNet 2B do HuggingFace (~400MB)..."

    # Tenta arquivo i2_s (otimizado para x86)
    huggingface-cli download microsoft/bitnet-b1.58-2B-4T-gguf \
        --local-dir /tmp/dl \
        --include "*i2_s*"

    FOUND=$(find /tmp/dl -name "*i2_s*.gguf" | head -1)

    # Fallback: BF16 (arquivo correto confirmado)
    if [ -z "$FOUND" ]; then
        echo "        i2_s não encontrado, baixando BF16..."
        curl -L -o /tmp/bitnet.gguf \
            "https://huggingface.co/microsoft/BitNet-b1.58-2B-4T-gguf/resolve/main/BitNet-b1.58-2B-4T-BF16.gguf"
        FOUND="/tmp/bitnet.gguf"
    fi

    if [ -z "$FOUND" ] || [ ! -f "$FOUND" ]; then
        echo "✗ ERRO FATAL: Nenhum modelo encontrado."
        exit 1
    fi

    # Valida que é um arquivo GGUF real (não uma página de erro HTML)
    MAGIC=$(head -c 4 "$FOUND" 2>/dev/null || echo "")
    if [ "$MAGIC" != "GGUF" ] && [[ "$MAGIC" != *"GGU"* ]]; then
        echo "✗ ERRO: Arquivo inválido — não é um GGUF. Conteúdo: $MAGIC"
        exit 1
    fi

    mkdir -p "$MODEL_DIR"
    cp "$FOUND" "$MODEL_FILE"
    rm -rf /tmp/dl /tmp/bitnet.gguf 2>/dev/null || true
    echo "✓ Modelo salvo: $MODEL_FILE"
else
    echo "✓ [1/2] Modelo encontrado: $MODEL_FILE"
fi

# ─── PASSO 2: Servidor ────────────────────────────────────────────────────────
echo ""
echo "▶ [2/2] Iniciando servidor na porta $PORT..."
echo "        http://0.0.0.0:$PORT/v1/chat/completions"
echo ""

cd /app/BitNet

exec python3 run_inference_server.py \
    -m "$MODEL_FILE" \
    --host 0.0.0.0 \
    --port "$PORT" \
    -t "$THREADS" \
    -c "$CTX" \
    --temperature "$TEMP"