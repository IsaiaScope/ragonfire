<h1 align="center">🔥 RagOnFire</h1>

<p align="center">
  <em>Fully-local, zero-API-cost multimodal RAG on portable Postgres storage.</em>
</p>

<p align="center">
  <img src="https://shieldcn.dev/badge/Python-3.12-3776AB.svg?logo=python&logoColor=fff&variant=default&size=xs" alt="Python 3.12" />
  <img src="https://shieldcn.dev/badge/Ollama-local-000000.svg?logo=ollama&logoColor=fff&variant=default&size=xs" alt="Ollama" />
  <img src="https://shieldcn.dev/badge/%F0%9F%95%B8%EF%B8%8F%20LightRAG-1.4.5-FF6B6B.svg?logo=false&logoColor=fff&variant=default&size=xs" alt="LightRAG 1.4.5" />
  <img src="https://shieldcn.dev/badge/Postgres-16-4169E1.svg?logo=postgresql&logoColor=fff&variant=default&size=xs" alt="Postgres 16" />
  <img src="https://shieldcn.dev/badge/Docker-compose-2496ED.svg?logo=docker&logoColor=fff&variant=default&size=xs" alt="Docker Compose" />
</p>

<p align="center">
  <img src="https://shieldcn.dev/badge/status-stable-22C55E.svg?logo=false&statusDot=true&logoColor=fff&variant=default&size=xs" alt="stable" />
  <img src="https://shieldcn.dev/badge/AI-tooling-7C3AED.svg?logo=ri:RiSparkling2Fill&logoColor=fff&variant=default&size=xs" alt="AI tooling" />
</p>

---

## 🚀 Quickstart

### ♻️ New machine, same drive

The external drive already carries `pgdata.ext4.img`:

```bash
# 1. Plug the drive in
# 2. Install Docker      https://docs.docker.com/get-docker/
# 3. From the repo on the drive:
./rag-anything/bootstrap.sh
/lightrag-start
```

The same vectors, graph, and KV come back up. No re-ingest.

### 🍎 macOS · 🐧 Linux

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

Stay in Windows tooling with Git Bash.

- Git for Windows — run everything from the **Git Bash** shell
- Docker Desktop on the **WSL2 backend** (the Hyper-V backend is not supported)
- Ollama for Windows — `bootstrap.sh` can install it via `winget`

### 🐧 WSL2

Work from a Linux shell inside WSL2.

- Ubuntu 22.04+ or another glibc-based distro
- Docker Desktop with WSL integration, or native `docker-ce`
- Ollama via `https://ollama.com/install.sh` — avoid the Windows-side service, both bind port `11434`

Both paths then run the same three commands:

```bash
git clone https://github.com/IsaiaScope/ragonfire.git
cd ragonfire
./rag-anything/bootstrap.sh
/lightrag-start
```

> Windows native is simpler if you already use Git Bash. WSL2 is simpler if you already live in a Linux shell.

### 🎛️ Skills only

Skills live in `.claude/skills/`, so Claude Code picks them up whenever its working directory is this repo — no install step. Copy them out only to reach them from another agent or from outside the repo:

```bash
./scripts/install-skills.sh --agent codex    # → ~/.codex/skills
./scripts/install-skills.sh                  # → ~/.claude/skills (global, outside-repo use)
./scripts/install-skills.sh --agent all
```

---

## ✨ Features

Three open-source pieces stitched into one local knowledge base — no API keys, no cloud bills, your data never leaves the machine.

- 🧠 **[Ollama](docs/ollama.md)** — runs the LLM and embedding models natively, so they reach the GPU directly.
- 📄 **[MinerU](docs/mineru.md)** — parses PDFs, Office docs, images, tables, equations, and OCR into structured artifacts.
- 🔗 **[RAG-Anything](rag-anything/)** — orchestrates multimodal ingest on top of LightRAG's hybrid vector + graph retrieval.
- 🐘 **Postgres 16 + pgvector + Apache AGE** — one database holds the vectors, the graph, and the KV store.
- 🔌 **Portable by design** — the Postgres data directory sits in an ext4 loopback image on the external drive, so the drive moves between macOS, Linux, Windows native, and WSL2 without re-ingesting.

---

## 🧱 Stack At A Glance

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

**Ingest routing** (`PARSER=auto`):

| Input | Route |
|-------|-------|
| Scanned PDF | MinerU OCR |
| Digital PDF with figures | Hybrid — MinerU vision + text recovery |
| Text-only PDF | `pymupdf` fast path |

---

## 🛠️ Skills

Every skill is a slash command in Claude Code. Flags and arguments are documented in each skill's own `SKILL.md` under [`.claude/skills/`](.claude/skills/).

**Stack lifecycle**

| | Skill | Does |
|-|-------|------|
| ▶️ | `/lightrag-start` | Boot Ollama, Postgres, LightRAG |
| ⏹️ | `/lightrag-stop` | Stop containers, unload the model |
| 🩺 | `/lightrag-status` | Health of every layer |
| ⏏️ | `/lightrag-eject` | Stop, sync, eject the drive |
| ⬆️ | `/lightrag-upgrade` | Rebuild after a schema pin change |

**Knowledge base**

| | Skill | Does |
|-|-------|------|
| 📝 | `/lightrag-upload` | Text document via REST |
| 📚 | `/raganything-upload` | PDF or Office via MinerU + VLM |
| ❓ | `/lightrag-query` | Ask the graph a question |
| 🕸️ | `/lightrag-explore` | Walk the graph around an entity |

**Backups**

| | Skill | Does |
|-|-------|------|
| 💾 | `/db-snapshot` | Take a gzip `pg_dump` |
| ♻️ | `/db-restore` | Restore from a dump |
| 📋 | `/db-list-snapshots` | List available dumps |
| 📈 | `/db-grow` | Resize the ext4 image |

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

Every path is configurable through `~/rag-anything/.env` after bootstrap.

| | What | Default path |
|-|------|--------------|
| 📜 | Runtime scripts + venv | `~/rag-anything/` |
| 💽 | Data root | `<repo>/data/` |
| 🐘 | Postgres image | `<repo>/data/pgdata.ext4.img` |
| 📦 | Parsed artifacts | `<repo>/data/output/` |
| 📥 | Batch ingest drop-zone | `<repo>/data/input/` |
| 🗃️ | Backups | `<repo>/data/backups/` |
| 🧠 | Ollama models | `~/.ollama/models/` |
| 🤗 | HF / MinerU caches | `<repo>/data/hf/`, `<repo>/data/mineru/` |

> **🧠 Ollama weights live on the internal SSD, not the data drive.** Ollama reloads GGUF weights every time it swaps between the extraction and embedding models mid-ingest. On an exFAT external drive each reload costs seconds and comes to dominate ingest runtime; an internal load is ~0.06s. `bootstrap.sh` sets `OLLAMA_MODELS=~/.ollama/models` automatically.

---

## ✅ Requirements

- 🐳 **Docker** — runs Postgres and the LightRAG server. Desktop on macOS and Windows native, Desktop WSL integration or native `docker-ce` on WSL2, Engine on Linux.
- 🧠 **Ollama** — runs natively on the host. `bootstrap.sh` installs it via Homebrew (macOS), the official script (Linux/WSL2), or `winget` (Windows).
- ⚡ **GPU** — Apple Silicon or NVIDIA for fast inference. CPU fallback works, but it is slow.
- 💾 **~20 GB internal SSD** — Docker images and the Python venv. The 50 GB Postgres image, model caches, and artifacts live under `data/` on the external drive.
- 🔌 **External drive** — exFAT is fine. Postgres data sits inside an ext4 loopback image, which preserves the POSIX semantics it needs.
- 🐍 **Python 3.12 + uv** — the host venv, installed by `bootstrap.sh`.

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
