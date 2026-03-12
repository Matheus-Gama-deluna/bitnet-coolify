# =============================================================================
# BitNet b1.58 2B — Dockerfile para CPU x86_64
# =============================================================================

FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git cmake python3 python3-pip wget curl \
    build-essential clang \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN git clone --recursive https://github.com/microsoft/BitNet.git .

RUN pip3 install --break-system-packages \
    -r requirements.txt \
    huggingface_hub

# Corrige bug de const pointer no ggml-bitnet-mad.cpp
RUN sed -i 's/int8_t \* y_col = y/const int8_t * y_col = y/g' \
    src/ggml-bitnet-mad.cpp

# Compila via setup_env.py — ignora exit code (falha esperada na conversão do modelo)
RUN python3 setup_env.py \
    --hf-repo microsoft/BitNet-b1.58-2B-4T \
    -q i2_s \
    --model-dir /tmp/dummy \
    || true

# Diagnóstico: mostra TUDO que foi gerado no build para identificar o path correto
RUN echo "=== Binários llama-* ===" \
    && find /build/build -type f -name "llama-*" 2>/dev/null || echo "(nenhum)" \
    && echo "=== Executáveis em build/bin ===" \
    && ls -la /build/build/bin/ 2>/dev/null || echo "(bin/ não existe)" \
    && echo "=== Estrutura de /build/build ===" \
    && find /build/build -maxdepth 3 -type f -executable 2>/dev/null | head -30 || echo "(vazio)"

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    python3 python3-pip curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /build /app/BitNet

# Copia shared libraries
RUN find /app/BitNet/build -name "libllama.so" -exec cp {} /usr/local/lib/ \; 2>/dev/null || true \
    && find /app/BitNet/build -name "libggml.so" -exec cp {} /usr/local/lib/ \; 2>/dev/null || true \
    && ldconfig

RUN pip3 install --break-system-packages huggingface_hub

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/models"]
EXPOSE 8080
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]