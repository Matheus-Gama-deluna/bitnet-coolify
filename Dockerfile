# =============================================================================
# BitNet b1.58 2B — Dockerfile para CPU x86_64
# Correções aplicadas:
# 1. Bug const pointer em ggml-bitnet-mad.cpp (linha 811)
# 2. setup_env.py retorna exit code 1 mesmo com sucesso — ignorado
# 3. Shared libraries (libllama.so, libggml.so) copiadas para /usr/local/lib
# 4. Build via setup_env.py (não cmake direto) — gera kernels x86 corretos
# =============================================================================

# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    git cmake python3 python3-pip wget curl \
    build-essential clang \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Clona com submódulos
RUN git clone --recursive https://github.com/microsoft/BitNet.git .

# Instala dependências Python
RUN pip3 install --break-system-packages \
    -r requirements.txt \
    huggingface_hub

# Corrige bug de const pointer que causa falha de compilação no x86 Linux
# Ref: https://esso.dev/blog-posts/deploying-microsoft-bit-net-1-58-bit-llm
RUN sed -i 's/int8_t \* y_col = y/const int8_t * y_col = y/g' \
    src/ggml-bitnet-mad.cpp

# Compila via setup_env.py (detecta hardware, gera kernels x86 otimizados)
# Exit code 1 é esperado — ocorre na conversão do modelo que não precisamos
# O que importa é que build/bin/llama-cli e llama-server sejam gerados
RUN python3 setup_env.py \
    --hf-repo microsoft/BitNet-b1.58-2B-4T \
    -q i2_s \
    --model-dir /tmp/dummy-model-dir \
    || true

# Verifica que os binários foram gerados
RUN test -f build/bin/llama-server && echo "✓ llama-server OK" \
    || (echo "✗ llama-server não encontrado" && find build -name "llama-*" && exit 1)

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    python3 python3-pip curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copia repositório compilado
COPY --from=builder /build /app/BitNet

# Copia shared libraries necessárias para o runtime
COPY --from=builder /build/build/3rdparty/llama.cpp/src/libllama.so /usr/local/lib/ 2>/dev/null || true
COPY --from=builder /build/build/3rdparty/llama.cpp/ggml/src/libggml.so /usr/local/lib/ 2>/dev/null || true
RUN ldconfig

# Instala dependências Python no runtime
RUN pip3 install --break-system-packages \
    huggingface_hub

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/models"]

EXPOSE 8080

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]