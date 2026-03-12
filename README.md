# BitNet b1.58 2B — CPU Inference Server

Servidor de inferência **OpenAI-compatible** para o [BitNet b1.58 2B](https://huggingface.co/microsoft/bitnet-b1.58-2B-4T-gguf) da Microsoft, otimizado para CPUs x86 sem GPU.

Projetado para deploy no **Coolify** como serviço interno de classificação e triagem em pipelines de agentes de IA.

---

## O que é o BitNet b1.58 2B

Primeiro LLM open source nativo de 1-bit treinado pela Microsoft em 4 trilhões de tokens. Pesos ternários `{-1, 0, +1}` permitem operações otimizadas que CPUs x86 executam nativamente, sem GPU.

| Métrica | Valor |
|---|---|
| Parâmetros | 2.4B |
| Memória RAM | ~400MB |
| Latência CPU (x86) | ~29ms/token |
| Velocidade estimada | 5–8 tok/s em 4 vCores |
| Contexto máximo | 4096 tokens |
| Licença | MIT |

---

## Estrutura do repositório

```
bitnet-cpu/
├── Dockerfile               ← build com clang-18 + bitnet.cpp
├── entrypoint.sh            ← download do modelo + compilação + servidor
├── docker-compose.yml       ← deploy no Coolify
├── .env.example             ← variáveis de ambiente
├── .gitignore
└── .github/
    └── workflows/
        └── build.yml        ← CI: build da imagem → GHCR → redeploy Coolify
```

---

## Deploy no Coolify

### Pré-requisito: network externa

Execute uma vez no VPS antes do primeiro deploy:

```bash
docker network create ai-stack
```

### Opção A — Build local no VPS (simples)

1. No Coolify: **New Resource → Docker Compose**
2. Conecte este repositório via GitHub App
3. **Base Directory:** `/` (raiz do repo)
4. **Build Pack:** Docker Compose
5. Adicione as variáveis de ambiente (veja `.env.example`)
6. Em **Advanced**: desabilite **Build Args Injection**
7. **Não atribua domínio** — serviço exclusivamente interno
8. Deploy

O container irá automaticamente:
- Baixar o modelo GGUF (~400MB) na primeira inicialização
- Compilar o bitnet.cpp com kernels x86 (~3-5 min)
- Subir o servidor na porta 8080 (interna)

> **Acompanhe os logs** na aba Logs do Coolify. O serviço estará pronto quando aparecer `[3/3] Iniciando servidor`.

### Opção B — Imagem pré-built via GitHub Actions (recomendado)

O workflow `.github/workflows/build.yml` faz o build pesado nos runners do GitHub e publica a imagem no GHCR. O Coolify só puxa a imagem pronta.

**Secrets necessários no GitHub:**

| Secret | Onde obter |
|---|---|
| `COOLIFY_WEBHOOK_URL` | Coolify → Recurso → Webhooks |
| `COOLIFY_TOKEN` | Coolify → Profile → API Tokens |

Após o primeiro push, o compose no Coolify pode usar a imagem diretamente:

```yaml
services:
  llamacpp-bitnet:
    image: ghcr.io/SEU_USUARIO/bitnet-cpu:latest
    # ... resto da config igual ao docker-compose.yml
```

---

## Variáveis de ambiente

| Variável | Padrão | Descrição |
|---|---|---|
| `BITNET_THREADS` | `3` | Threads de CPU (recomendado: vCores - 1) |
| `BITNET_CTX` | `4096` | Tamanho do contexto em tokens |
| `BITNET_PORT` | `8080` | Porta interna do servidor |
| `BITNET_TEMPERATURE` | `0.0` | Temperatura (0.0 = determinístico) |

---

## Integração com LiteLLM

Adicione ao `litellm_config.yaml`:

```yaml
- model_name: "classifier"
  litellm_params:
    model: openai/bitnet-2b
    api_base: "http://llamacpp-bitnet:8080"
    api_key: "none"
    max_tokens: 50
    timeout: 30
```

Chamada de teste de dentro da rede:

```bash
curl -X POST http://llamacpp-bitnet:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "bitnet",
    "messages": [{"role": "user", "content": "classifique: simples, medio ou complexo. Mensagem: ola tudo bem"}],
    "max_tokens": 10
  }'
```

---

## Uso recomendado

O BitNet 2B é ideal para tarefas leves que não precisam do Groq:

- **Classificação de intenção** em pipelines de customer service
- **Triagem de tickets** (simples / médio / complexo)
- **Respostas de FAQ** curtas e determinísticas
- **Roteamento de agentes** — decide qual modelo usar para cada tarefa

Para raciocínio complexo, use Groq via LiteLLM com `model: fast`.

---

## Volumes e persistência

| Volume | Conteúdo | Tamanho |
|---|---|---|
| `bitnet-models` | Modelo GGUF | ~400MB |
| `bitnet-build` | Binários compilados | ~200MB |

Ambos persistem entre restarts e redeploys. A recompilação só ocorre se o volume `bitnet-build` for deletado manualmente.

---

## Referências

- [microsoft/BitNet](https://github.com/microsoft/BitNet) — repositório oficial
- [BitNet b1.58 2B4T no HuggingFace](https://huggingface.co/microsoft/bitnet-b1.58-2B-4T-gguf)
- [Technical Report](https://arxiv.org/abs/2504.12285)
