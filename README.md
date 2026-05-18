<p align="center">
  <img src="docs/assets/ragonfire.png" width="80" alt="RagOnFire logo" />
</p>

<h3 align="center">RagOnFire 🔥📚</h3>

<p align="center">
  <em>Fully-local, zero-API-cost multimodal RAG for Apple Silicon.</em>
</p>

<br />

<p align="center">
  <img src="https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white" alt="Python" />
  <img src="https://img.shields.io/badge/Ollama-local-000000?logo=ollama&logoColor=white" alt="Ollama" />
  <img src="https://img.shields.io/badge/LightRAG-1.4-FF6B6B?logoColor=white" alt="LightRAG" />
  <img src="https://img.shields.io/badge/MinerU-2-2496ED?logoColor=white" alt="MinerU" />
  <img src="https://img.shields.io/badge/qwen2.5--vl-7B-1C7CFF?logoColor=white" alt="qwen2.5-vl" />
  <img src="https://img.shields.io/badge/bge--m3-1024d-7C3AED?logoColor=white" alt="bge-m3" />
  <img src="https://img.shields.io/badge/MPS-Apple%20Silicon-A2AAAD?logo=apple&logoColor=white" alt="MPS" />
  <img src="https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi&logoColor=white" alt="FastAPI" />
</p>

---

## 🔥 About

**RagOnFire** stitches three battle-tested open-source pieces into one knowledge-base on your Mac:

- **[Ollama](ollama/)** — runs an LLM and an embedding model entirely on local GPU (Apple Metal / MPS).
- **[MinerU](mineru/)** — parses PDFs, Office docs, and images into clean text + tables + equations + cropped images.
- **[RAG-Anything](rag-anything/)** — orchestrates the multimodal pipeline on top of **LightRAG**'s hybrid (vector + graph) retrieval engine.

Zero API keys. Zero per-token cost. Zero data leaving your machine.

## 🧠 Stack at a glance

```
                 ┌──────────────────────┐
                 │  Claude Code skills  │
                 │  /lightrag-* /rag-*  │
                 └──────────┬───────────┘
                            │ (REST + Python)
                 ┌──────────▼───────────┐
                 │  LightRAG  :9621     │  hybrid retrieval, KG, FastAPI
                 └─────┬──────────┬─────┘
                       │          │
              ┌────────▼──┐    ┌──▼────────┐
              │  Ollama   │    │  MinerU   │
              │  :11434   │    │  (MPS)    │
              │ qwen2.5vl │    │ parse +   │
              │ + bge-m3  │    │ OCR + eq  │
              └───────────┘    └───────────┘
```

## 📦 Modules

| | Module | Role |
|-|--------|------|
| 🦙 | **[ollama/](ollama/)** | LLM + embedding runtime. `qwen2.5vl:7b` (text + vision) and `bge-m3` (1024-dim multilingual embeddings) |
| ⛏️ | **[mineru/](mineru/)** | Document parser. PDF/DOCX/PPTX/XLSX → text + tables + equations + images |
| 🧠 | **[rag-anything/](rag-anything/)** | Pipeline + LightRAG server + 7 Claude Code skills (start, stop, upload, status, query, explore, raganything-upload) |

## 🚀 Quickstart

```bash
# 1. Clone
git clone <repo-url> ragonfire && cd ragonfire

# 2. Install everything (Ollama, models, Python venv, MinerU)
./rag-anything/bootstrap.sh

# 3. Start the server (lazy — only when you need it)
~/rag-anything/scripts/server-start.sh

# 4. Ingest a multimodal document
~/rag-anything/.venv/bin/python \
  ~/rag-anything/scripts/ingest.py \
  /path/to/paper.pdf

# 5. Query
curl -s -X POST http://localhost:9621/query \
  -H "Content-Type: application/json" \
  -d '{"query": "What are the main findings?", "mode": "hybrid"}'

# 6. Stop the server (frees ~3-5 GB of RAM)
~/rag-anything/scripts/server-stop.sh
```

## 🎛️ From Claude Code

All operations are exposed as slash commands once the skills are installed under `~/.claude/skills/`:

| Skill | What it does |
|-------|--------------|
| `/lightrag-start` | Boot the LightRAG server on `:9621` |
| `/lightrag-stop` | Shut it down, free RAM |
| `/lightrag-upload` | Push a text file to the KG (REST) |
| `/raganything-upload` | Ingest a multimodal PDF/Office doc (MinerU + VLM) |
| `/lightrag-status` | Doc counts, processing state, top entities |
| `/lightrag-query` | Ask the KG a question |
| `/lightrag-explore` | Walk the graph around an entity |

## 📂 Project layout

```
ragonfire/
├── README.md                       ← you are here
├── .gitignore                      ← excludes models, venv, storage
├── ollama/
│   └── README.md                   ← Ollama config + models
├── mineru/
│   └── README.md                   ← MinerU parser config
└── rag-anything/
    ├── README.md                   ← detailed deployment guide
    ├── bootstrap.sh                ← idempotent installer
    ├── requirements.txt
    ├── .env.example
    ├── scripts/
    │   ├── ingest.py               ← RAG-Anything Python entry
    │   ├── server-start.sh
    │   ├── server-stop.sh
    │   └── server-status.sh
    └── skills/                     ← copied to ~/.claude/skills/ by bootstrap
        ├── lightrag-start/
        ├── lightrag-stop/
        ├── lightrag-upload/
        ├── lightrag-status/
        ├── lightrag-query/
        ├── lightrag-explore/
        └── raganything-upload/
```

## 🗄️ Runtime locations

| What | Where | Why |
|------|-------|-----|
| Code, venv, scripts | `~/rag-anything/` (internal SSD) | exFAT external drives break Python venvs |
| KG + vectors | `/Volumes/Crucial-4T/rag-anything/storage/` | Big, slow, OK on external |
| Parsed artifacts | `/Volumes/Crucial-4T/rag-anything/output/` | MinerU markdown + cropped images |
| Ollama models | `~/.ollama/models/` (or moved to `/Volumes/Crucial-4T/models/ollama/`) | ~7 GB |
| MinerU models | `~/.mineru/` (or `/Volumes/Crucial-4T/models/mineru/`) | ~5 GB, lazy-downloaded |

## 🧪 Tested on

<p>
  <img src="https://img.shields.io/badge/macOS-15.x-000000?logo=apple&logoColor=white" alt="macOS" />
  <img src="https://img.shields.io/badge/Apple_M4-32GB-A2AAAD?logo=apple&logoColor=white" alt="M4" />
  <img src="https://img.shields.io/badge/Python-3.12.12-3776AB?logo=python&logoColor=white" alt="Python" />
  <img src="https://img.shields.io/badge/uv-package_manager-DE5FE9?logoColor=white" alt="uv" />
  <img src="https://img.shields.io/badge/Homebrew-4-FBB040?logo=homebrew&logoColor=white" alt="Homebrew" />
</p>

## 📜 Licenses

RagOnFire integrates third-party open-source software. See each module's README for license attribution:
- **Ollama** — MIT
- **MinerU** — AGPL-3.0
- **LightRAG / RAG-Anything** — MIT
- **qwen2.5-vl** — Apache-2.0 / Tongyi Qianwen Research
- **bge-m3** — MIT

This wrapper repo is MIT.

---

<p align="center">
  <sub>Built locally. Queried locally. Never leaves your laptop.</sub>
</p>
