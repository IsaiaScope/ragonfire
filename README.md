<h3 align="center">RagOnFire 🔥</h3>

<p align="center">
  <em>Fully-local, zero-API-cost multimodal RAG with portable Postgres storage.</em>
</p>

<br />

<p align="center">
  <img src="https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white" alt="Python" />
  <img src="https://img.shields.io/badge/Ollama-local-000000?logo=ollama&logoColor=white" alt="Ollama" />
  <img src="https://img.shields.io/badge/LightRAG-1.4-FF6B6B?logoColor=white" alt="LightRAG" />
  <img src="https://img.shields.io/badge/MinerU-2-2496ED?logoColor=white" alt="MinerU" />
  <img src="https://img.shields.io/badge/qwen2.5--vl-7B-1C7CFF?logoColor=white" alt="qwen2.5-vl" />
  <img src="https://img.shields.io/badge/bge--m3-1024d-7C3AED?logoColor=white" alt="bge-m3" />
  <img src="https://img.shields.io/badge/Postgres-16-4169E1?logo=postgresql&logoColor=white" alt="Postgres" />
  <img src="https://img.shields.io/badge/pgvector_+_AGE-graph-336791?logoColor=white" alt="pgvector + AGE" />
  <img src="https://img.shields.io/badge/OS-macOS%20%7C%20Linux%20%7C%20Windows%20%7C%20WSL2-555?logoColor=white" alt="OS" />
</p>

---

## 🔥 About

RagOnFire stitches three open-source pieces into one local knowledge base — no API keys, no cloud bills, your data never leaves the machine:

| | Piece | Role |
|-|-------|------|
| 🧠 | **[Ollama](docs/ollama.md)** | Runs the LLM + embedding models natively for GPU access |
| 📄 | **[MinerU](docs/mineru.md)** | Parses PDFs, Office docs, images, tables, equations, and OCR into structured artifacts |
| 🔗 | **[RAG-Anything](rag-anything/)** | Orchestrates multimodal ingest on top of LightRAG hybrid vector + graph retrieval |

Retrieval state lives in **Postgres 16** with **pgvector** and **Apache AGE**. The Postgres data directory sits inside an ext4 loopback image on the external drive, so the same drive moves between macOS, Linux, Windows native, and WSL2 without re-ingesting.

---

## 🧱 Stack At A Glance

<p align="center">
  <img src="https://img.shields.io/badge/Docker-compose-2496ED?logo=docker&logoColor=white" alt="Docker" />
  <img src="https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi&logoColor=white" alt="FastAPI" />
  <img src="https://img.shields.io/badge/GitHub_Actions-CI-2088FF?logo=githubactions&logoColor=white" alt="GitHub Actions" />
</p>

```
Claude / Codex skills
        │
        ▼
LightRAG server container :9622
        │
        ├──▶ Postgres container :5433   (pgvector + AGE, ext4 .img on drive)
        ├──▶ Ollama native :11434       (qwen2.5:7b · qwen2.5vl:7b · bge-m3)
        └──▶ MinerU native parser       (during ingest)
```

**Ingest routing** (`PARSER=auto`): scanned PDF → MinerU OCR · digital PDF with figures → hybrid (MinerU vision + text recovery) · text-only PDF → pymupdf fast path.

---

## 🚀 Quickstart

### ♻️ New machine, same drive

If the external drive already has a populated `pgdata.ext4.img`:

```bash
# 1. Plug the drive in
# 2. Install Docker (https://docs.docker.com/get-docker/)
# 3. From the repo on the drive:
./rag-anything/bootstrap.sh
/lightrag-start
```

The same vectors, graph, and KV come up. No re-ingest.

### 🍎 macOS / 🐧 Linux

```bash
git clone https://github.com/IsaiaScope/ragonfire.git
cd ragonfire

./rag-anything/bootstrap.sh                  # Claude Code: skills already live in .claude/skills/
./rag-anything/bootstrap.sh --agent codex    # also copy skills → ~/.codex/skills
./rag-anything/bootstrap.sh --skip-skills    # runtime only

/lightrag-start
/raganything-upload /path/to/paper.pdf
/lightrag-query "What are the main findings?"
/lightrag-eject
```

### 🪟 Windows native

Stay in Windows tooling and Git Bash.

- Git for Windows (use **Git Bash** as the shell)
- Docker Desktop with the **WSL2 backend** (Hyper-V backend not supported)
- Ollama for Windows — `bootstrap.sh` can install via `winget`

```bash
git clone https://github.com/IsaiaScope/ragonfire.git
cd ragonfire
./rag-anything/bootstrap.sh
/lightrag-start
```

### 🐧 WSL2

Work from a Linux shell inside WSL2.

- Ubuntu 22.04+ or another glibc-based distro
- Docker Desktop with WSL integration, or native `docker-ce`
- Ollama via `https://ollama.com/install.sh` (avoid the Windows-side service — both use port `11434`)

```bash
git clone https://github.com/IsaiaScope/ragonfire.git
cd ragonfire
./rag-anything/bootstrap.sh
/lightrag-start
```

> Windows native is simpler if you already use Git Bash. WSL2 is simpler if you already live in a Linux shell.

### 🎛️ Skills only

Skills live in `.claude/skills/`, so Claude Code picks them up automatically when
its working directory is this repo — no install step. Copy them out only to use
them from another agent or from outside the repo:

```bash
./scripts/install-skills.sh --agent codex    # → ~/.codex/skills
./scripts/install-skills.sh                  # → ~/.claude/skills (global, outside-repo use)
./scripts/install-skills.sh --agent all
```

---

## 🛠️ Skills

| | Skill | What it does |
|-|-------|--------------|
| ▶️ | `/lightrag-start` | Boot Ollama, Postgres, and LightRAG |
| ⏹️ | `/lightrag-stop` | Stop containers and unload the Ollama model |
| ⏏️ | `/lightrag-eject` | Stop, sync, and eject the external drive |
| 📝 | `/lightrag-upload` | Upload a text document through the LightRAG REST API |
| 📚 | `/raganything-upload` | Ingest multimodal documents through MinerU + VLM |
| 🩺 | `/lightrag-status` | Show Ollama, Docker, Postgres, LightRAG, and disk health |
| ❓ | `/lightrag-query` | Ask the knowledge graph a question |
| 🕸️ | `/lightrag-explore` | Walk the graph around an entity |
| 💾 | `/db-snapshot` | Create a gzip `pg_dump` backup |
| ♻️ | `/db-restore` | Restore from a `pg_dump` backup |
| 📋 | `/db-list-snapshots` | List available backups |
| 📈 | `/db-grow` | Grow the ext4 loopback image |
| ⬆️ | `/lightrag-upgrade` | Snapshot, rebuild, and re-ingest after schema pin changes |

---

## 🗂️ Project Layout

```
ragonfire/
├── .claude/
│   └── skills/                 # agent skills (project-scoped)
├── infra/
│   ├── docker-compose.yml
│   ├── lightrag-server/
│   ├── postgres/
│   └── os/                     # OS detect + per-OS installers
├── rag-anything/
│   ├── bootstrap.sh
│   ├── requirements.txt
│   └── scripts/
├── scripts/
│   └── install-skills.sh
├── tests/                      # phase1 linux · phase3 windows · phase4 wsl2
├── docs/
│   ├── ollama.md
│   ├── mineru.md
│   └── superpowers/
└── data/                       # gitignored, populated at runtime
    ├── pgdata.ext4.img         # 50G ext4 loopback (Postgres data)
    ├── hf/  mineru/            # model caches
    └── input/ output/ working/ backups/
```

---

## 📍 Runtime Locations

All paths are configurable via `~/rag-anything/.env` after bootstrap.

| | What | Default path |
|-|------|--------------|
| 📜 | Runtime scripts + venv | `~/rag-anything/` |
| 💽 | Data root | `<repo>/data/` |
| 🐘 | Postgres image | `<repo>/data/pgdata.ext4.img` |
| 📦 | Parsed artifacts | `<repo>/data/output/` |
| 📥 | Batch ingest drop-zone | `<repo>/data/input/` |
| 🗃️ | Backups | `<repo>/data/backups/` |
| 🧠 | Ollama models | `~/.ollama/models/` *(internal SSD — see note)* |
| 🤗 | HF / MinerU caches | `<repo>/data/hf/`, `<repo>/data/mineru/` |

> **🧠 Ollama weights live on the internal SSD, not the data drive.** Ollama reloads GGUF weights when it swaps between the extraction and embedding models mid-ingest; on an exFAT external drive each reload costs seconds and dominates ingest runtime (internal load is ~0.06s). `bootstrap.sh` sets `OLLAMA_MODELS=~/.ollama/models` automatically.

---

## ✅ Requirements

| | Requirement | Notes |
|-|-------------|-------|
| 🐳 | **Docker** | Postgres + LightRAG server. Desktop on macOS/Windows native, Desktop WSL integration or native `docker-ce` on WSL2, Engine on Linux |
| 🧠 | **Ollama** | Runs natively on the host. `bootstrap.sh` installs via Homebrew (macOS), the official script (Linux/WSL2), or `winget` (Windows) |
| ⚡ | **GPU** | Apple Silicon / NVIDIA recommended for fast inference. CPU fallback works but is slow |
| 💾 | **~20 GB internal SSD** | Docker images + Python venv. The 50 GB Postgres image, model caches, and artifacts live under `data/` on the external drive |
| 🔌 | **External drive** | ExFAT is fine — Postgres data lives inside an ext4 loopback image, preserving POSIX semantics |
| 🐍 | **Python 3.12 + uv** | Host venv, installed by `bootstrap.sh` |

---

## 📄 Licenses

RagOnFire integrates third-party open-source software. See each module's README for license attribution.

| Component | License |
|-----------|---------|
| Ollama | MIT |
| MinerU | AGPL-3.0 |
| LightRAG / RAG-Anything | MIT |
| qwen2.5-vl | Apache-2.0 / Tongyi Qianwen Research |
| bge-m3 | MIT |

This wrapper repo is **MIT**.

---

<p align="center">
  Built local-first — no API keys, no cloud bills. 🔥
</p>
