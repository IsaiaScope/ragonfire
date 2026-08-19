<h3 align="center">RAG-Anything + LightRAG 🔗</h3>

<p align="center">
  <em>Orchestrates MinerU + Ollama into a queryable, multimodal knowledge graph.</em>
</p>

<br />

<p align="center">
  <img src="https://img.shields.io/badge/RAG--Anything-multimodal-FF6B6B?logoColor=white" alt="RAG-Anything" />
  <img src="https://img.shields.io/badge/LightRAG-1.4-FF6B6B?logoColor=white" alt="LightRAG" />
  <img src="https://img.shields.io/badge/Postgres-16-4169E1?logo=postgresql&logoColor=white" alt="Postgres" />
  <img src="https://img.shields.io/badge/pgvector-HNSW-336791?logoColor=white" alt="pgvector" />
  <img src="https://img.shields.io/badge/Apache_AGE-Cypher-336791?logoColor=white" alt="Apache AGE" />
  <img src="https://img.shields.io/badge/Ollama-local-000000?logo=ollama&logoColor=white" alt="Ollama" />
  <img src="https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white" alt="Python" />
</p>

---

## 🔗 Role In RagOnFire

This module wires everything together.

| | Piece | Role |
|-|-------|------|
| 🧩 | **RAG-Anything** | Multimodal dispatcher — routes each parsed block (text, table, equation, image) to the right model |
| 🕸️ | **LightRAG** | Retrieval engine — owns the knowledge graph, vector store, KV state, and doc status inside Postgres |
| 🐳 | **Docker** | Runs Postgres + the LightRAG server. Ollama and MinerU stay native for GPU access |

```
PDF / DOCX / image
        │
        ▼
MinerU native parser
        │
        ▼
RAG-Anything ingest ──▶ Ollama native (qwen2.5vl · bge-m3)
        │
        ▼
LightRAG storage
        │
        ▼
Postgres 16 container (pgvector + Apache AGE)
```

---

## 🚀 Bootstrap

```bash
./bootstrap.sh
```

| | Step | What |
|-|------|------|
| 1️⃣ | Verify Docker | Installed and reachable |
| 2️⃣ | Install tooling | `uv` and Ollama |
| 3️⃣ | Pull models | `qwen2.5vl:7b` · `qwen2.5:7b` · `bge-m3` |
| 4️⃣ | Create venv | Python 3.12 at `~/rag-anything/.venv` |
| 5️⃣ | Install deps | Pinned Python requirements |
| 6️⃣ | Stage runtime | Copy scripts, requirements, `.env.example` |
| 7️⃣ | Create image | `pgdata.ext4.img` if missing |
| 8️⃣ | Build compose | Docker Compose images |
| 9️⃣ | Install skills | Agent skills, unless `--skip-skills` |

---

## 🗄️ Storage Backend

Retrieval state lives in a single **Postgres 16** container running **pgvector + Apache AGE**. The Postgres entrypoint mounts the ext4 loopback image before handing off, so the live data directory stays on the external drive:

```
<repo>/data/pgdata.ext4.img      ◀ ext4 inside, ExFAT outside
                                   50 GB cap, growable
```

| | Storage | Backend |
|-|---------|---------|
| 🧮 | Vectors | pgvector HNSW (`M=16`, `EF_CONSTRUCTION=64`, `EF_SEARCH=40`) |
| 🕸️ | Graph | AGE Cypher |
| 🔑 | KV state | Plain Postgres tables |
| 📊 | Doc status | Plain Postgres tables |

All four LightRAG storages share one database, so a single `pg_dump` captures the entire knowledge base.

---

## 📦 Installed Runtime

| | Path | What |
|-|------|------|
| 🐍 | `~/rag-anything/.venv/` | Python venv on internal SSD |
| 📜 | `~/rag-anything/scripts/` | Lifecycle, backup, and ingest scripts |
| ⚙️ | `~/rag-anything/.env` | Runtime config |
| 📝 | `$HOST_LOGS_DIR` | Ollama/server logs, default `<repo>/data/logs/` |
| 🐘 | `<repo>/data/pgdata.ext4.img` | Portable Postgres data image |
| 📦 | `<repo>/data/output/` | MinerU parsed artifacts |
| 📥 | `<repo>/data/input/` | Batch ingest drop-zone |
| 🗃️ | `<repo>/data/backups/` | `pg_dump` snapshots |

---

## 🔄 Lifecycle

```bash
/lightrag-start                     # mounts .img, boots PG + LightRAG, ensures Ollama
/raganything-upload /path/doc.pdf   # ingest (server stays up)
/lightrag-query "What is X?"        # ask
/db-snapshot                        # back up before big changes
/lightrag-eject                     # stop everything + eject drive before unplug
```

---

## ❓ Query Modes

| | Mode | What it does |
|-|------|--------------|
| 🔀 | `hybrid` | Entity relationships + graph traversal + vectors |
| 🧬 | `mix` | Knowledge graph + vector retrieval combined |
| 📎 | `naive` | Basic vector similarity |
| 📍 | `local` | Immediate entity relationships |
| 🌐 | `global` | High-level cross-graph knowledge |

---

## ⚙️ .env Reference

```ini
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_HOST_EXTERNAL=localhost
POSTGRES_PORT_EXTERNAL=5433
POSTGRES_USER=ragonfire
POSTGRES_PASSWORD=ragonfire
POSTGRES_DATABASE=ragonfire
POSTGRES_WORKSPACE=default

LIGHTRAG_KV_STORAGE=PGKVStorage
LIGHTRAG_VECTOR_STORAGE=PGVectorStorage
LIGHTRAG_GRAPH_STORAGE=PGGraphStorage
LIGHTRAG_DOC_STATUS_STORAGE=PGDocStatusStorage

RAGONFIRE_DATA_DIR=<repo>/data
PGDATA_IMG=<repo>/data/pgdata.ext4.img
PGDATA_IMG_CAP=50G

LIGHTRAG_PORT_EXTERNAL=9622
LIGHTRAG_PORT_INTERNAL=9621
LOG_DIR=/var/log/lightrag
HOST_LOGS_DIR=<repo>/data/logs

LLM_BINDING=ollama
LLM_BINDING_HOST=http://host.docker.internal:11434
LLM_MODEL=qwen2.5vl:7b
EXTRACTION_MODEL=qwen2.5:7b   # text entity extraction
VISION_MODEL=qwen2.5vl:7b     # image interpretation
TIMEOUT=900                   # 300 times out mid-extract on M-series

EMBEDDING_BINDING=ollama
EMBEDDING_BINDING_HOST=http://host.docker.internal:11434
EMBEDDING_MODEL=bge-m3
EMBEDDING_DIM=1024

OLLAMA_MODELS=~/.ollama/models  # internal SSD (NOT the exFAT data drive)

MINERU_DEVICE=auto
MINERU_BACKEND=pipeline
PARSER=auto                   # scanned->mineru; text+figures->hybrid; text-only->pymupdf
PARSE_METHOD=auto
```

---

## ⚠️ Gotchas

- 🐳 Docker must be running before `/lightrag-start`.
- ⏳ First Ollama calls after idle take 10-30 s while the model loads.
- 🔁 Changing the embedding model or dimension requires rebuilding the knowledge base.
- ⏏️ Use `/lightrag-eject` before physically unplugging the drive.

---

## 🔗 Links

| Resource | Link |
|----------|------|
| RAG-Anything | [HKUDS/RAG-Anything](https://github.com/HKUDS/RAG-Anything) |
| LightRAG | [HKUDS/LightRAG](https://github.com/HKUDS/LightRAG) |
| LightRAG paper | [arXiv:2410.05779](https://arxiv.org/abs/2410.05779) |
| License | MIT |

---

<p align="center">
  One database for vectors, graph, and KV. Pull the drive, plug it anywhere. 🔥
</p>
