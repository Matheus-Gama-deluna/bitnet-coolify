#!/bin/bash
# =============================================================================
# BitNet b1.58 2B — entrypoint
# O build e compilação já estão na imagem Docker
# Este script: verifica/copia o modelo e inicia o servidor
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

# ─── Modelo: usa o que está no volume ou copia da imagem ──────────────────────
# O modelo foi baixado durante o build e está em /app/BitNet/models/
# Na primeira execução, copia para o volume persistente /models/
if [ ! -f "$MODEL_FILE" ]; then
    # Procura o modelo que veio na imagem (baixado pelo Dockerfile)
    BUILT_IN=$(find /app/BitNet/models -name "*.gguf" | head -1)

    if [ -n "$BUILT_IN" ]; then
        echo "▶ [1/2] Copiando modelo da imagem para o volume..."
        mkdir -p "$MODEL_DIR"
        cp "$BUILT_IN" "$MODEL_FILE"
        echo "✓ Modelo copiado: $MODEL_FILE"
    else
        echo "▶ [1/2] Modelo não encontrado na imagem, baixando do HuggingFace..."
        huggingface-cli download microsoft/bitnet-b1.58-2B-4T-gguf \
            --local-dir /tmp/dl \
            --include "*i2_s*"

        FOUND=$(find /tmp/dl -name "*i2_s*.gguf" | head -1)
        if [ -z "$FOUND" ]; then
            echo "✗ ERRO FATAL: Modelo não encontrado."
            exit 1
        fi

        mkdir -p "$MODEL_DIR"
        cp "$FOUND" "$MODEL_FILE"
        rm -rf /tmp/dl
        echo "✓ Modelo salvo: $MODEL_FILE"
    fi
else
    echo "✓ [1/2] Modelo no volume: $MODEL_FILE"
fi

# ─── Servidor ─────────────────────────────────────────────────────────────────
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