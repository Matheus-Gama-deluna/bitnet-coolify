# =============================================================================
# BitNet b1.58 2B — Dockerfile CPU x86_64
# Estratégia correta:
# 1. Baixa o modelo GGUF no build (necessário para setup_env.py -md)
# 2. Roda setup_env.py -md <modelo> -q i2_s (compila com kernels x86 corretos)
# 3. Runtime só precisa iniciar o servidor
# =============================================================================

FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git cmake python3 python3-pip wget curl \
    build-essential clang \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Clona BitNet com submódulos
RUN git clone --recursive https://github.com/microsoft/BitNet.git .

# Dependências Python
RUN pip3 install --break-system-packages \
    -r requirements.txt \
    huggingface_hub

# Corrige bug de const pointer (causa falha no clang Linux x86)
RUN sed -i 's/int8_t \* y_col = y/const int8_t * y_col = y/g' \
    src/ggml-bitnet-mad.cpp 2>/dev/null || true

# Baixa o modelo GGUF (setup_env.py -md precisa do arquivo local)
RUN huggingface-cli download microsoft/bitnet-b1.58-2B-4T-gguf \
    --local-dir /build/models/BitNet-b1.58-2B-4T \
    --include "*i2_s*"

# Compila usando -md (model dir local) — não usa --hf-repo que tem lista restrita
# setup_env.py vai: compilar cmake, gerar kernels x86, quantizar o modelo
RUN python3 setup_env.py \
    -md models/BitNet-b1.58-2B-4T \
    -q i2_s \
    || true

# Mostra o que foi gerado para diagnóstico
RUN echo "=== build/bin ===" \
    && ls -la /build/build/bin/ 2>/dev/null || echo "(vazio)" \
    && echo "=== llama-* encontrados ===" \
    && find /build/build -name "llama-*" -type f 2>/dev/null | head -20 || echo "(nenhum)"

# Falha explicitamente se o servidor não existir
RUN test -f /build/build/bin/llama-server \
    && echo "✓ llama-server OK" \
    || (echo "✗ FALHOU — llama-server ausente" && exit 1)

# ── Runtime ───────────────────────────────────────────────────────────────────
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    python3 python3-pip curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copia repositório compilado inteiro (inclui build/bin e scripts Python)
COPY --from=builder /build /app/BitNet

# Registra shared libraries
RUN find /app/BitNet/build -name "*.so" -exec cp {} /usr/local/lib/ \; 2>/dev/null || true \
    && ldconfig

RUN pip3 install --break-system-packages huggingface_hub

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/models"]
EXPOSE 8080
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]