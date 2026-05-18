
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

### Skills only (fast, no runtime install)

If you already have Ollama + the venv set up elsewhere, or just want the Claude Code slash commands:

```bash
git clone https://github.com/IsaiaScope/ragonfire.git
cd ragonfire

# Default: Claude Code (~/.claude/skills/)
./scripts/install-skills.sh

# Codex (~/.codex/skills/)
./scripts/install-skills.sh --agent codex

# Both agents
./scripts/install-skills.sh --agent all
```

### Full install (Ollama + models + venv + skills)

```bash
# 1. Clone
git clone https://github.com/IsaiaScope/ragonfire.git
cd ragonfire

# 2. Install everything (Ollama, models, Python venv, MinerU, skills)
./rag-anything/bootstrap.sh                  # default: skills → Claude Code
./rag-anything/bootstrap.sh --agent codex    # or skills → Codex
./rag-anything/bootstrap.sh --agent all      # or both

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

## 🗄️ Runtime locations (defaults)

All paths are configurable via `~/rag-anything/.env` after bootstrap. The defaults below assume a single root.

| What | Default path | Override |
|------|--------------|----------|
| Code, venv, scripts | `~/rag-anything/` | `RAGONFIRE_RUNTIME` env (advanced) |
| KG + vectors | `~/rag-anything/storage/` | `WORKING_DIR` in `.env` |
| Parsed artifacts | `~/rag-anything/output/` | `OUTPUT_DIR` in `.env` |
| Batch ingest drop-zone | `~/rag-anything/input/` | `INPUT_DIR` in `.env` |
| Ollama models | `~/.ollama/models/` | `OLLAMA_MODELS` env |
| MinerU models | `~/.mineru/` and HF / ModelScope caches | `HF_HOME`, `MODELSCOPE_CACHE` env |

> **Tip:** to keep multi-GB models off your boot drive, point `OLLAMA_MODELS`, `HF_HOME`, and `MODELSCOPE_CACHE` at an external SSD. Python venvs need a POSIX filesystem (APFS/HFS+/ext4), so keep `~/rag-anything/.venv` on the internal drive even if data lives elsewhere.

## 🧪 Requirements

<p>
  <img src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white" alt="macOS" />
  <img src="https://img.shields.io/badge/Apple_Silicon-M1%2FM2%2FM3%2FM4-A2AAAD?logo=apple&logoColor=white" alt="Apple Silicon" />
  <img src="https://img.shields.io/badge/RAM-16GB%2B-2C5BB4?logoColor=white" alt="RAM" />
  <img src="https://img.shields.io/badge/Disk-~20GB_free-FF9F1C?logoColor=white" alt="Disk" />
  <img src="https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white" alt="Python" />
  <img src="https://img.shields.io/badge/uv-package_manager-DE5FE9?logoColor=white" alt="uv" />
  <img src="https://img.shields.io/badge/Homebrew-required-FBB040?logo=homebrew&logoColor=white" alt="Homebrew" />
</p>

- **macOS 13+** on Apple Silicon (M1 or newer). MPS is used for MinerU layout and OCR models.
- **16 GB unified memory** minimum (32 GB comfortable). The qwen2.5-vl 7B Q4 quant fits in ~6 GB; 32B variants need 32 GB+.
- **~20 GB free disk** for Ollama models (~7 GB), MinerU models (~5 GB), Python venv (~3 GB), and parsed artifacts.
- **Homebrew** for installing Ollama.
- **uv** for the Python venv: `curl -LsSf https://astral.sh/uv/install.sh | sh`

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
