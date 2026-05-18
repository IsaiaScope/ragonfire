
<h3 align="center">RAG-Anything + LightRAG — The Pipeline</h3>

<p align="center">
  <em>Orchestrates MinerU + Ollama into a queryable, multimodal knowledge graph.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/RAG--Anything-multimodal-FF6B6B?logoColor=white" alt="RAG-Anything" />
  <img src="https://img.shields.io/badge/LightRAG-1.4-1C7CFF?logoColor=white" alt="LightRAG" />
  <img src="https://img.shields.io/badge/FastAPI-:9621-009688?logo=fastapi&logoColor=white" alt="FastAPI" />
  <img src="https://img.shields.io/badge/NetworkX-graph-2C5BB4?logoColor=white" alt="NetworkX" />
  <img src="https://img.shields.io/badge/NanoVectorDB-vectors-7C3AED?logoColor=white" alt="NanoVectorDB" />
</p>

---

## 🧠 Role in RagOnFire

This module wires everything together.

- **RAG-Anything** is the multimodal dispatcher. For each parsed block it decides: send to the LLM as text? send the image to the vision model? extract LaTeX?
- **LightRAG** is the retrieval engine. It builds and maintains a knowledge graph (entities + relationships) alongside a vector store, and exposes hybrid search over both.

```
PDF/DOCX/image
      │
      ▼
┌──────────────┐    ┌──────────────────────┐
│   MinerU     │ →  │  RAG-Anything        │
│   (parser)   │    │  ────────────────    │
└──────────────┘    │  text  → LLM         │
                    │  table → LLM         │
                    │  image → VLM         │
                    │  eq    → LLM (LaTeX) │
                    └────────┬─────────────┘
                             │
                    ┌────────▼─────────────┐
                    │  LightRAG            │
                    │  ────────────────    │
                    │  bge-m3 embed        │
                    │  entity merge        │
                    │  graph build         │
                    └────────┬─────────────┘
                             │
                    ┌────────▼─────────────┐
                    │  storage/  (JSON)    │
                    │  NetworkX + NanoVDB  │
                    └──────────────────────┘
```

## 🚀 Bootstrap

```bash
./bootstrap.sh
```

What it does (idempotent):

1. Verifies `brew` and `uv` are present.
2. Installs Ollama via Homebrew if missing; starts the service.
3. Pulls `qwen2.5vl:7b` and `bge-m3` (skips if already present).
4. Creates a Python 3.12 venv at `~/rag-anything/.venv` (internal SSD — exFAT external drives break venvs).
5. Installs `raganything[all]`, `lightrag-hku[api]`, `mineru[core]`, `ollama`, `python-dotenv`.
6. Triggers a MinerU import to validate the install.
7. Copies `skills/` into `~/.claude/skills/` (so `/lightrag-*` slash commands are available).
8. Copies `.env.example` → `~/rag-anything/.env`.

## 🗂️ What gets installed where

| | Path | What |
|-|------|------|
| 🧰 | `~/rag-anything/.venv/` | Python venv (internal SSD) |
| 🧰 | `~/rag-anything/scripts/` | Server lifecycle + `ingest.py` |
| 🧰 | `~/rag-anything/.env` | Config (paths, model names, ports) |
| 🧰 | `~/rag-anything/logs/` | Server stdout/err + PID file |
| 💾 | `~/rag-anything/storage/` | KG + vectors (JSON) |
| 💾 | `~/rag-anything/output/` | MinerU parsed artifacts |
| 💾 | `~/rag-anything/input/` | Drop-zone for batch ingest |
| 🎛️ | `~/.claude/skills/lightrag-*/` | 6 LightRAG slash commands |
| 🎛️ | `~/.claude/skills/raganything-upload/` | Multimodal ingest slash command |

## 🎛️ Skills (Claude Code slash commands)

| Skill | What it does | Triggers REST? |
|-------|--------------|----------------|
| `/lightrag-start` | Boot the LightRAG server, ensure Ollama is up | n/a |
| `/lightrag-stop` | Kill the server, free RAM | n/a |
| `/lightrag-upload` | Push a text file (TXT, MD, simple PDF) | `POST /documents/upload` |
| `/raganything-upload` | Run MinerU + VLM pipeline on a multimodal doc | Python (not REST) |
| `/lightrag-status` | Server health, doc counts, top entities | `/documents/pipeline_status`, `/documents`, `/graph/label/popular` |
| `/lightrag-query` | Ask the KG a question, get markdown + sources | `POST /query` |
| `/lightrag-explore` | Subgraph around an entity | `/graph/label/search`, `/graphs` |

## 🔁 Lifecycle (server is on-demand)

The server is **not** a daemon. You start it when you need it and stop it when you don't, so it doesn't sit in RAM forever.

```bash
# Boot
~/rag-anything/scripts/server-start.sh

# Check
~/rag-anything/scripts/server-status.sh
curl http://localhost:9621/health

# Ingest a multimodal PDF (auto-stops + restarts the server)
~/rag-anything/.venv/bin/python ~/rag-anything/scripts/ingest.py /path/to/doc.pdf

# Query
curl -s -X POST http://localhost:9621/query \
  -H 'Content-Type: application/json' \
  -d '{"query": "What is X?", "mode": "hybrid"}'

# Free RAM when done
~/rag-anything/scripts/server-stop.sh
```

## 🔑 .env reference

```ini
# Storage (LightRAG)
WORKING_DIR=~/rag-anything/storage
INPUT_DIR=~/rag-anything/input

# Server
HOST=0.0.0.0
PORT=9621

# LLM
LLM_BINDING=ollama
LLM_BINDING_HOST=http://localhost:11434
LLM_MODEL=qwen2.5vl:7b

# Embeddings
EMBEDDING_BINDING=ollama
EMBEDDING_BINDING_HOST=http://localhost:11434
EMBEDDING_MODEL=bge-m3
EMBEDDING_DIM=1024

# Retrieval
TOP_K=40
COSINE_THRESHOLD=0.2

# Chunking
CHUNK_SIZE=1200
CHUNK_OVERLAP_SIZE=100

# MinerU
MINERU_DEVICE=mps
MINERU_BACKEND=pipeline
PARSER=mineru
PARSE_METHOD=auto
OUTPUT_DIR=~/rag-anything/output
```

## 🧪 Query modes

| Mode | What it does | When to use |
|------|--------------|-------------|
| `hybrid` (default) | Vector cosine + graph traversal | General questions |
| `mix` | Hybrid + reranker (if configured) | Highest quality, slowest |
| `local` | Walk neighborhood of mentioned entities | "Tell me about X" |
| `global` | High-level themes across the whole graph | "Main themes in my corpus?" |
| `naive` | Pure vector cosine (classic RAG) | Sanity-check baseline |

## ⚠️ Gotchas

- **The server holds storage files open.** Run `/lightrag-stop` (or the skill auto-handles it) before multimodal ingest, then restart so the KG reloads with new entities.
- **Vector dim is locked.** Switching `EMBEDDING_MODEL` means wiping `storage/` — old vectors are incompatible with the new model.
- **First Ollama call after a stop ≈ 10–30 s warmup** while the model loads to GPU. Subsequent calls are fast.
- **`ollama` Python package is required by LightRAG's Ollama binding** — listed in `requirements.txt`. If `ImportError: No module named 'ollama'`, run `uv pip install --python ~/rag-anything/.venv/bin/python ollama`.

## 📚 Links

- RAG-Anything: [HKUDS/RAG-Anything](https://github.com/HKUDS/RAG-Anything)
- LightRAG: [HKUDS/LightRAG](https://github.com/HKUDS/LightRAG)
- LightRAG paper: [arXiv:2410.05779](https://arxiv.org/abs/2410.05779)
- License: MIT (both)
