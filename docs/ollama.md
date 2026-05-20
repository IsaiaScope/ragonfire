<h3 align="center">Ollama — Local Model Runtime 🦙</h3>

<p align="center">
  <em>Serves the LLM (qwen2.5-vl) and the embedding model (bge-m3) entirely on the host GPU.</em>
</p>

<br />

<p align="center">
  <img src="https://img.shields.io/badge/Ollama-0.x-000000?logo=ollama&logoColor=white" alt="Ollama" />
  <img src="https://img.shields.io/badge/Metal-Apple%20GPU-A2AAAD?logo=apple&logoColor=white" alt="Metal" />
  <img src="https://img.shields.io/badge/HTTP-:11434-00ADD8?logoColor=white" alt="port" />
</p>

---

## 🦙 Role in RagOnFire

Ollama is the **model server**. It exposes an HTTP API on `localhost:11434` and lets the rest of the stack talk to large neural networks without writing any inference code.

- **Generation** — `qwen2.5-vl:7b` answers questions, extracts entities, interprets images.
- **Embeddings** — `bge-m3` turns chunks of text into 1024-dim vectors for semantic search.

Both models run on **Metal** (Apple Silicon GPU). No CUDA, no API key, no cloud.

## 📦 Models

| Model | Tag | Size | Role | License |
|-------|-----|------|------|---------|
| **qwen2.5-vl** | `qwen2.5vl:7b` | ~6 GB | Text generation + vision (charts, tables, diagrams) | Apache-2.0 / Tongyi Qianwen Research |
| **bge-m3** | `bge-m3` | ~1.2 GB | Multilingual dense embeddings (100+ languages, 1024-dim) | MIT |

## ⚙️ Install

Handled by `../rag-anything/bootstrap.sh`. Manual:

```bash
brew install ollama
brew services start ollama
ollama pull qwen2.5vl:7b   # vision / image interpretation
ollama pull qwen2.5:7b     # text entity extraction
ollama pull bge-m3         # embeddings
```

## 🔍 Verify

```bash
ollama list
# qwen2.5vl:7b   ...   6.0 GB
# bge-m3         ...   1.2 GB

curl -s http://localhost:11434/api/tags | jq '.models[].name'
```

## 🗄️ Where models live (keep on the INTERNAL SSD)

Ollama stores models at `~/.ollama/models/` and this stack keeps them there
(`OLLAMA_MODELS=~/.ollama/models`, set by `bootstrap.sh`).

⚠️ **Do NOT move the model store to the exFAT data drive.** Ollama reloads GGUF
weights every time it swaps between the extraction model (`qwen2.5:7b`) and the
embedding model (`bge-m3`) mid-ingest. From an exFAT external SSD each reload
costs seconds and dominates ingest runtime; from the internal SSD a load is
~0.06s. Measured impact: the same CV ingest dropped from ~16 min to ~5 min after
moving weights back internal. Bulk read-once caches (HuggingFace, MinerU) are
fine on the data drive — only the hot Ollama weights must stay internal.

If weights ever end up on an external drive, move them back:

```bash
brew services stop ollama   # or: pkill -f "ollama serve"
mkdir -p ~/.ollama/models
rsync -a /path/to/external/models/ollama/ ~/.ollama/models/
launchctl setenv OLLAMA_MODELS ~/.ollama/models   # session; .env makes it durable
brew services start ollama
ollama list   # qwen2.5vl:7b + qwen2.5:7b + bge-m3
```

## 🩺 Health checks

```bash
# Daemon up?
curl -sf http://localhost:11434/api/tags >/dev/null && echo OK

# Generation works?
curl -s http://localhost:11434/api/generate -d '{
  "model": "qwen2.5vl:7b",
  "prompt": "Say hi.",
  "stream": false
}' | jq -r '.response'

# Embedding works?
curl -s http://localhost:11434/api/embed -d '{
  "model": "bge-m3",
  "input": "hello world"
}' | jq '.embeddings[0] | length'   # should print 1024
```

## 🔧 Tunables

Env vars Ollama reads at start (set via `launchctl setenv` for the daemon, or `export` in your shell for CLI use):

| Env var | What it does | Default |
|---------|--------------|---------|
| `OLLAMA_MODELS` | Directory for model blobs | `~/.ollama/models` |
| `OLLAMA_HOST` | Bind address | `127.0.0.1:11434` |
| `OLLAMA_KEEP_ALIVE` | How long a loaded model stays in VRAM after last use | `5m` |
| `OLLAMA_NUM_PARALLEL` | Concurrent requests per model | `1` |
| `OLLAMA_MAX_LOADED_MODELS` | Models held in VRAM at once | `1` |
| `OLLAMA_FLASH_ATTENTION` | Faster attention kernels (Metal) | `0` |

For RagOnFire we keep defaults — they fit comfortably on 16 GB+ Apple Silicon Macs.

## 📚 Links

- Project: [ollama/ollama](https://github.com/ollama/ollama)
- Model library: [ollama.com/library](https://ollama.com/library)
- qwen2.5-vl: [QwenLM/Qwen2.5-VL](https://github.com/QwenLM/Qwen2.5-VL)
- bge-m3: [FlagOpen/FlagEmbedding](https://github.com/FlagOpen/FlagEmbedding)

---

<p align="center">
  All inference local — no API keys, no cloud. 🔥
</p>
