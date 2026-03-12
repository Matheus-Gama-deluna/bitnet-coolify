#!/bin/bash
# =============================================================================
# BitNet b1.58 2B — entrypoint
# 1. Baixa o modelo GGUF se não existir
# 2. Compila bitnet.cpp na primeira execução (cacheia no volume)
# 3. Inicia servidor OpenAI-compatible na porta configurada
# =============================================================================
set -e

MODEL_DIR="/models"
MODEL_FILE="$MODEL_DIR/ggml-model-i2_s.gguf"
BUILD_DIR="/app/BitNet/build"
BUILD_MARKER="$BUILD_DIR/.compiled_ok"
THREADS=${BITNET_THREADS:-3}
CTX=${BITNET_CTX:-4096}
PORT=${BITNET_PORT:-8080}
TEMP=${BITNET_TEMPERATURE:-0.0}

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     BitNet b1.58 2B — CPU Inference      ║"
echo "╠══════════════════════════════════════════╣"
echo "║  Threads : $THREADS                            ║"
echo "║  Context : $CTX tokens                   ║"
echo "║  Porta   : $PORT                          ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ─── PASSO 1: Modelo ──────────────────────────────────────────────────────────
if [ ! -f "$MODEL_FILE" ]; then
    echo "▶ [1/3] Baixando modelo BitNet 2B do HuggingFace..."
    echo "        Repositório : microsoft/bitnet-b1.58-2B-4T-gguf"
    echo "        Arquivo     : kernel i2_s (otimizado para x86)"
    echo "        Tamanho     : ~400MB"
    echo ""

    huggingface-cli download microsoft/bitnet-b1.58-2B-4T-gguf \
        --local-dir /tmp/dl \
        --include "*i2_s*"

    FOUND=$(find /tmp/dl -name "*i2_s*.gguf" | head -1)

    # Fallback: qualquer .gguf disponível
    if [ -z "$FOUND" ]; then
        echo "        i2_s não encontrado, tentando fallback..."
        huggingface-cli download microsoft/bitnet-b1.58-2B-4T-gguf \
            --local-dir /tmp/dl
        FOUND=$(find /tmp/dl -name "*.gguf" | head -1)
    fi

    if [ -z "$FOUND" ]; then
        echo "✗ ERRO FATAL: Nenhum arquivo .gguf encontrado no download."
        exit 1
    fi

    mkdir -p "$MODEL_DIR"
    cp "$FOUND" "$MODEL_FILE"
    rm -rf /tmp/dl

    echo "✓ Modelo salvo em: $MODEL_FILE"
    echo ""
else
    echo "✓ [1/3] Modelo encontrado: $MODEL_FILE"
fi

# ─── PASSO 2: Compilação ──────────────────────────────────────────────────────
if [ ! -f "$BUILD_MARKER" ] || [ ! -f "$BUILD_DIR/bin/llama-server" ]; then
    echo ""
    echo "▶ [2/3] Compilando bitnet.cpp com kernels x86 (I2_S)..."
    echo "        Isso leva ~3-5 minutos na primeira execução."
    echo "        O resultado será cacheado no volume para próximas inicializações."
    echo ""

    cd /app/BitNet
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    cmake .. \
        -DCMAKE_C_COMPILER=clang-18 \
        -DCMAKE_CXX_COMPILER=clang++-18 \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_RUNTIME_OUTPUT_DIRECTORY="$BUILD_DIR/bin" \
        2>&1 | tail -5

    make -j"$(nproc)" 2>&1 | tail -10

    # Garante que o binário está onde o run_inference_server.py espera
    mkdir -p "$BUILD_DIR/bin"
    # Move qualquer binário llama-server encontrado para build/bin/
    FOUND_BIN=$(find "$BUILD_DIR" -name "llama-server" -not -path "*/bin/*" | head -1)
    if [ -n "$FOUND_BIN" ]; then
        cp "$FOUND_BIN" "$BUILD_DIR/bin/llama-server"
        echo "        Binário copiado para $BUILD_DIR/bin/llama-server"
    fi

    # Diagnóstico: mostra onde os binários foram gerados
    echo "        Binários gerados:"
    find "$BUILD_DIR" -type f -executable -name "llama-*" 2>/dev/null || echo "        (nenhum encontrado)"

    if [ ! -f "$BUILD_DIR/bin/llama-server" ]; then
        echo "✗ ERRO: llama-server não encontrado em $BUILD_DIR/bin/"
        echo "  Verifique os logs do cmake acima."
        exit 1
    fi

    touch "$BUILD_MARKER"
    echo ""
    echo "✓ Compilação concluída e cacheada em $BUILD_DIR"
else
    echo "✓ [2/3] Build cacheado encontrado — pulando compilação."
fi

# ─── PASSO 3: Servidor ────────────────────────────────────────────────────────
echo ""
echo "▶ [3/3] Iniciando servidor OpenAI-compatible..."
echo "        Endpoint : http://0.0.0.0:$PORT/v1/chat/completions"
echo ""

cd /app/BitNet

exec python3 run_inference_server.py \
    -m "$MODEL_FILE" \
    --host 0.0.0.0 \
    --port "$PORT" \
    -t "$THREADS" \
    -c "$CTX" \
    --temperature "$TEMP"