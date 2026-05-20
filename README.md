<h3 align="center">RagOnFire</h3>

<p align="center">
  <em>Fully-local, zero-API-cost multimodal RAG with portable Postgres storage.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white" alt="Python" />
  <img src="https://img.shields.io/badge/Ollama-local-000000?logo=ollama&logoColor=white" alt="Ollama" />
  <img src="https://img.shields.io/badge/LightRAG-1.4-FF6B6B?logoColor=white" alt="LightRAG" />
  <img src="https://img.shields.io/badge/MinerU-2-2496ED?logoColor=white" alt="MinerU" />
  <img src="https://img.shields.io/badge/qwen2.5--vl-7B-1C7CFF?logoColor=white" alt="qwen2.5-vl" />
  <img src="https://img.shields.io/badge/bge--m3-1024d-7C3AED?logoColor=white" alt="bge-m3" />
  <img src="https://img.shields.io/badge/OS-macOS%20%7C%20Linux%20%7C%20WSL2-555?logoColor=white" alt="OS" />
  <img src="https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi&logoColor=white" alt="FastAPI" />
</p>

---

## About

RagOnFire stitches three open-source pieces into one local knowledge base:

- [Ollama](docs/ollama.md) runs an LLM and embedding model natively for GPU access.
- [MinerU](docs/mineru.md) parses PDFs, Office docs, images, tables, equations, and OCR into structured artifacts.
- [RAG-Anything](rag-anything/) orchestrates multimodal ingest on top of LightRAG hybrid vector + graph retrieval.

Retrieval state lives in Postgres 16 with pgvector and Apache AGE. The Postgres data directory sits inside an ext4 loopback image on the external drive, so the same drive can move between macOS, Linux, and WSL2 without re-ingesting.

## Stack At A Glance

```
Claude/Codex skills
        |
        v
LightRAG server container :9622
        |
        +--> Postgres container :5433 (pgvector + AGE, ext4 .img on drive)
        |
        +--> Ollama native :11434 (qwen2.5vl:7b + bge-m3)
        |
        +--> MinerU native parser during ingest
```

## Modules

| Module | Role |
|--------|------|
| [docs/ollama.md](docs/ollama.md) | LLM + embedding runtime: `qwen2.5vl:7b` and `bge-m3` |
| [docs/mineru.md](docs/mineru.md) | Document parser: PDF/DOCX/PPTX/XLSX -> text, tables, equations, images |
| [rag-anything/](rag-anything/) | Pipeline, Docker stack, lifecycle scripts, and 13 agent skills |

## Quickstart

### New machine, same drive

If the Crucial-4T already has a populated `pgdata.ext4.img`:

```bash
# 1. Plug the drive in
# 2. Install Docker (per-OS instructions: https://docs.docker.com/get-docker/)
# 3. From the repo on the drive:
./rag-anything/bootstrap.sh
/lightrag-start
```

The same vectors, graph, and KV come up. No re-ingest.

### Full install

```bash
git clone https://github.com/IsaiaScope/ragonfire.git
cd ragonfire

./rag-anything/bootstrap.sh                  # default: skills -> Claude Code
./rag-anything/bootstrap.sh --agent codex    # or skills -> Codex
./rag-anything/bootstrap.sh --agent all      # or both

/lightrag-start
/raganything-upload /path/to/paper.pdf
/lightrag-query "What are the main findings?"
/lightrag-eject
```

### Skills only

```bash
./scripts/install-skills.sh
./scripts/install-skills.sh --agent codex
./scripts/install-skills.sh --agent all
```

## Skills

| Skill | What it does |
|-------|--------------|
| `/lightrag-start` | Boot Ollama, Postgres, and LightRAG |
| `/lightrag-stop` | Stop containers and unload the Ollama model |
| `/lightrag-eject` | Stop, sync, and eject the external drive |
| `/lightrag-upload` | Upload a text document through the LightRAG REST API |
| `/raganything-upload` | Ingest multimodal documents through MinerU + VLM |
| `/lightrag-status` | Show Ollama, Docker, Postgres, LightRAG, and disk health |
| `/lightrag-query` | Ask the KG a question |
| `/lightrag-explore` | Walk the graph around an entity |
| `/db-snapshot` | Create a gzip pg_dump backup |
| `/db-restore` | Restore from a pg_dump backup |
| `/db-list-snapshots` | List available backups |
| `/db-grow` | Grow the ext4 loopback image |
| `/lightrag-upgrade` | Snapshot, rebuild, and re-ingest after schema pin changes |

## Project Layout

```
ragonfire/
├── infra/
│   ├── docker-compose.yml
│   ├── lightrag-server/
│   ├── postgres/
│   └── os/
├── rag-anything/
│   ├── bootstrap.sh
│   ├── requirements.txt
│   ├── scripts/
│   └── skills/
├── scripts/
│   └── install-skills.sh
├── tests/
│   ├── fixtures/
│   ├── phase1-smoke.sh
│   └── phase2-smoke.sh
├── docs/
│   ├── ollama.md
│   ├── mineru.md
│   └── superpowers/
└── data/                       # gitignored, populated at runtime
    ├── pgdata.ext4.img         # 50G ext4 loopback (Postgres data)
    ├── ollama/  hf/  mineru/   # model caches
    └── input/ output/ working/ backups/
```

## Runtime Locations

All paths are configurable via `~/rag-anything/.env` after bootstrap.

| What | Default path |
|------|--------------|
| Runtime scripts + venv | `~/rag-anything/` |
| Data root | `<repo>/data/` |
| Postgres image | `<repo>/data/pgdata.ext4.img` |
| Parsed artifacts | `<repo>/data/output/` |
| Batch ingest drop-zone | `<repo>/data/input/` |
| Backups | `<repo>/data/backups/` |
| Ollama models | `<repo>/data/ollama/` |
| HF/MinerU caches | `<repo>/data/hf/`, `<repo>/data/mineru/` |

## Requirements

- **Docker** (Desktop on macOS/Windows, engine on Linux) - runs Postgres + LightRAG server.
- **Ollama** (native - installed automatically by `bootstrap.sh` via brew on macOS, the official install script on Linux, or manual install on WSL2).
- **Apple Silicon / NVIDIA GPU recommended** for fast inference. CPU fallback works but is slow.
- **~20 GB free internal SSD** for Docker images + Python venv. The 50 GB Postgres image, model caches, and parsed artifacts live under the repo-root `data/` directory on the external drive.
- **External drive** formatted ExFAT is fine - Postgres data lives inside an ext4 loopback image so POSIX semantics are preserved.
- **Python 3.12** + **uv** for the host venv (installed by `bootstrap.sh`).

## Licenses

RagOnFire integrates third-party open-source software. See each module's README for license attribution:

- Ollama - MIT
- MinerU - AGPL-3.0
- LightRAG / RAG-Anything - MIT
- qwen2.5-vl - Apache-2.0 / Tongyi Qianwen Research
- bge-m3 - MIT

This wrapper repo is MIT.
