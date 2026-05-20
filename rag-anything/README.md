<h3 align="center">RAG-Anything + LightRAG Pipeline</h3>

<p align="center">
  <em>Orchestrates MinerU + Ollama into a queryable, multimodal knowledge graph.</em>
</p>

---

## Role In RagOnFire

This module wires everything together.

- RAG-Anything is the multimodal dispatcher. For each parsed block it decides whether to send text, tables, equations, or images to the model.
- LightRAG is the retrieval engine. It maintains the knowledge graph, vector store, KV state, and document status inside Postgres.
- Docker runs Postgres + the LightRAG server. Ollama and MinerU stay native for GPU access.

```
PDF/DOCX/image
      |
      v
MinerU native parser
      |
      v
RAG-Anything ingest
      |
      +--> Ollama native (qwen2.5vl + bge-m3)
      |
      v
LightRAG storage
      |
      v
Postgres 16 container (pgvector + Apache AGE)
```

## Bootstrap

```bash
./bootstrap.sh
```

What it does:

1. Verifies Docker is installed and reachable.
2. Installs or verifies `uv` and Ollama.
3. Pulls `qwen2.5vl:7b` and `bge-m3`.
4. Creates a Python 3.12 venv at `~/rag-anything/.venv`.
5. Installs pinned Python dependencies.
6. Copies scripts, requirements, and `.env.example` into the runtime.
7. Creates `pgdata.ext4.img` if missing.
8. Builds the Docker Compose images.
9. Installs agent skills unless `--skip-skills` is passed.

## Installed Runtime

| Path | What |
|------|------|
| `~/rag-anything/.venv/` | Python venv on internal SSD |
| `~/rag-anything/scripts/` | Lifecycle, backup, and ingest scripts |
| `~/rag-anything/.env` | Runtime config |
| `$HOST_LOGS_DIR` | Ollama/server logs, defaulting under `<repo>/data/logs/` |
| `<repo>/data/pgdata.ext4.img` | Portable Postgres data image |
| `<repo>/data/output/` | MinerU parsed artifacts |
| `<repo>/data/input/` | Batch ingest drop-zone |
| `<repo>/data/backups/` | pg_dump snapshots |

## Storage Backend

Retrieval state lives in a single Postgres 16 container running pgvector + Apache AGE. The Postgres entrypoint mounts the ext4 loopback image before handing off to the official Postgres entrypoint, so the live data directory stays on the external drive:

```
<repo>/data/pgdata.ext4.img                         <- ext4 inside, ExFAT outside
                                                     started at 50 GB cap, growable
```

Vectors use HNSW indexes (`HNSW_M=16`, `HNSW_EF_CONSTRUCTION=64`, `HNSW_EF_SEARCH=40`). Graph uses AGE Cypher. KV and doc-status are plain Postgres tables. All four LightRAG storages share the same database, so a single `pg_dump` snapshot captures the entire knowledge base.

## Lifecycle

```bash
/lightrag-start                     # mounts .img, boots PG + LightRAG, ensures Ollama
/raganything-upload /path/doc.pdf   # ingest (server stays up)
/lightrag-query "What is X?"        # ask
/db-snapshot                        # take a backup before big changes
/lightrag-eject                     # stop everything + eject drive before unplug
```

## .env Reference

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

## Query Modes

| Mode | What it does |
|------|--------------|
| `hybrid` | Entity relationships + graph traversal + vectors |
| `mix` | Knowledge graph + vector retrieval combined |
| `naive` | Basic vector similarity |
| `local` | Immediate entity relationships |
| `global` | High-level cross-graph knowledge |

## Gotchas

- Docker must be running before `/lightrag-start`.
- First Ollama calls after idle can take 10-30 seconds while the model loads.
- Changing embedding model or dimension requires rebuilding the knowledge base.
- Use `/lightrag-eject` before physically unplugging the drive.

## Links

- RAG-Anything: [HKUDS/RAG-Anything](https://github.com/HKUDS/RAG-Anything)
- LightRAG: [HKUDS/LightRAG](https://github.com/HKUDS/LightRAG)
- LightRAG paper: [arXiv:2410.05779](https://arxiv.org/abs/2410.05779)
- License: MIT
