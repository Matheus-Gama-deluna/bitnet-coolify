FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# ─── Dependências de build ───────────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    git cmake python3 python3-pip wget curl \
    lsb-release software-properties-common gnupg \
    && wget -qO- https://apt.llvm.org/llvm.sh | bash -s -- 18 \
    && apt-get install -y clang-18 \
    && update-alternatives --install /usr/bin/clang   clang   /usr/bin/clang-18 100 \
    && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-18 100 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ─── Repositório oficial BitNet ───────────────────────────────────────────────
RUN git clone --recursive https://github.com/microsoft/BitNet.git

WORKDIR /app/BitNet

# ─── Dependências Python ──────────────────────────────────────────────────────
RUN pip3 install --break-system-packages \
    -r requirements.txt \
    huggingface_hub

# ─── Entrypoint ───────────────────────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/models", "/app/BitNet/build"]

EXPOSE 8080

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
