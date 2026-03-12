#!/bin/bash
# =============================================================================
# BitNet b1.58 2B — entrypoint
# 1. Baixa o modelo GGUF se não existir
# 2. Verifica submódulos, compila bitnet.cpp (cacheia no volume)
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
echo "║  Threads : $THREADS | Context : $CTX | Porta : $PORT  ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ─── PASSO 1: Modelo ──────────────────────────────────────────────────────────
if [ ! -f "$MODEL_FILE" ]; then
    echo "▶ [1/3] Baixando modelo BitNet 2B do HuggingFace (~400MB)..."

    huggingface-cli download microsoft/bitnet-b1.58-2B-4T-gguf \
        --local-dir /tmp/dl \
        --include "*i2_s*"

    FOUND=$(find /tmp/dl -name "*i2_s*.gguf" | head -1)

    if [ -z "$FOUND" ]; then
        echo "        i2_s não encontrado, tentando fallback..."
        huggingface-cli download microsoft/bitnet-b1.58-2B-4T-gguf \
            --local-dir /tmp/dl
        FOUND=$(find /tmp/dl -name "*.gguf" | head -1)
    fi

    if [ -z "$FOUND" ]; then
        echo "✗ ERRO FATAL: Nenhum arquivo .gguf encontrado."
        exit 1
    fi

    mkdir -p "$MODEL_DIR"
    cp "$FOUND" "$MODEL_FILE"
    rm -rf /tmp/dl
    echo "✓ Modelo salvo: $MODEL_FILE"
else
    echo "✓ [1/3] Modelo encontrado: $MODEL_FILE"
fi

# ─── PASSO 2: Compilação ──────────────────────────────────────────────────────
if [ ! -f "$BUILD_MARKER" ] || [ ! -f "$BUILD_DIR/bin/llama-server" ]; then
    echo ""
    echo "▶ [2/3] Compilando bitnet.cpp (~3-5 min)..."

    cd /app/BitNet

    # Verifica submódulos — sem isso o cmake falha com "No SOURCES given to target: ggml"
    if [ ! -f "3rdparty/llama.cpp/CMakeLists.txt" ]; then
        echo "        Inicializando submódulos (llama.cpp ausente)..."
        git submodule update --init --recursive
        echo "        Submódulos prontos."
    else
        echo "        Submódulos OK."
    fi

    # Limpa build anterior corrompido
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    cmake .. \
        -DCMAKE_C_COMPILER=clang-18 \
        -DCMAKE_CXX_COMPILER=clang++-18 \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_RUNTIME_OUTPUT_DIRECTORY="$BUILD_DIR/bin"

    make -j"$(nproc)"

    # Garante que o binário está em build/bin/ (onde run_inference_server.py espera)
    mkdir -p "$BUILD_DIR/bin"
    FOUND_BIN=$(find "$BUILD_DIR" -name "llama-server" ! -path "*/bin/llama-server" | head -1)
    if [ -n "$FOUND_BIN" ]; then
        echo "        Copiando: $FOUND_BIN → $BUILD_DIR/bin/llama-server"
        cp "$FOUND_BIN" "$BUILD_DIR/bin/llama-server"
        chmod +x "$BUILD_DIR/bin/llama-server"
    fi

    # Diagnóstico
    echo "        Binários encontrados:"
    find "$BUILD_DIR" -type f -name "llama-*" 2>/dev/null | head -10 || true

    if [ ! -f "$BUILD_DIR/bin/llama-server" ]; then
        echo "✗ ERRO: llama-server não encontrado em $BUILD_DIR/bin/"
        echo "  Todos os executáveis no build:"
        find "$BUILD_DIR" -type f -executable 2>/dev/null | head -20 || true
        exit 1
    fi

    touch "$BUILD_MARKER"
    echo "✓ Compilação concluída: $BUILD_DIR/bin/llama-server"
else
    echo "✓ [2/3] Build cacheado — pulando compilação."
fi

# ─── PASSO 3: Servidor ────────────────────────────────────────────────────────
echo ""
echo "▶ [3/3] Iniciando servidor na porta $PORT..."
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