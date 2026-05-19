# Portable Postgres-backed RagOnFire on Crucial-4T

**Date:** 2026-05-19
**Status:** Draft — grilled, ready for implementation plan
**Author:** ragonfire maintainers

## Summary

Make RagOnFire a "plug a drive into any Docker-capable machine and use it"
system. Replace the four file-based LightRAG stores (NetworkX graph,
NanoVectorDB vectors, JSON KV, JSON doc-status) with a single Postgres 16
instance running pgvector + Apache AGE inside a Docker container. The
Postgres data directory lives inside an ext4 loopback image stored on the
Crucial-4T external drive (ExFAT host filesystem), so the database
literally travels with the drive. Native Ollama and native MinerU stay on
the host SSD for GPU access (Metal/CUDA).

## Goals

1. **Drive-as-database.** Live Postgres bytes live inside a single file on
   Crucial-4T. Plug the drive into a new machine, install Docker + Ollama,
   run a bootstrap script, and the same knowledge graph comes up.
2. **One database for retrieval state.** Vectors, graph, KV, and
   doc-status all in the same Postgres. One backup stream, one restore,
   one schema to version.
3. **OS-agnostic at the Docker layer.** Compose file and ext4 loopback
   work identically on macOS Docker Desktop, native Linux, and Windows
   WSL2. Native pieces (Ollama, MinerU) are installed per-OS by the
   bootstrap script.
4. **Headroom to 500 GB live PG without reformatting the drive.** Ext4
   image starts at 50 GB and grows on demand via a documented procedure.

## Non-goals

- Production hardening (HA, replication, PITR). Single-user local KB.
- Multi-tenant schemas / multi-corpus support beyond a single workspace.
- An automated JSON → Postgres data-migration tool. The current corpus is
  ~26 MB across 2 documents; re-ingest is the migration path.
- Containerizing Ollama or MinerU. Both stay native to keep GPU access on
  macOS (Metal) and Linux (CUDA).
- Pre-formatting the Crucial-4T drive as APFS. The drive stays ExFAT for
  cross-OS file access of bulk artifacts.

## Current state

```
~/rag-anything/storage/
├── graph_chunk_entity_relation.graphml   (NetworkX)
├── vdb_chunks.json                       (NanoVectorDB)
├── vdb_entities.json                     (NanoVectorDB)
├── vdb_relationships.json                (NanoVectorDB)
├── kv_store_full_docs.json               (JSON KV)
├── kv_store_text_chunks.json             (JSON KV)
├── kv_store_llm_response_cache.json      (JSON KV)
└── doc_status.json                       (JSON doc-status)
```

Pain points that motivate the rewrite:

- The LightRAG server holds these JSON files open. Out-of-process ingest
  (`raganything-upload`) needs `/lightrag-stop` first, then restart.
- No transactional updates. A crash mid-write corrupts JSON files.
- Vector dim is locked at create time. Changing the embedding model means
  wiping `storage/` blindly.
- macOS-only install: brew, MPS-as-default. The runtime assumes
  `~/rag-anything/` on an APFS disk.
- No portability across machines beyond rsync of the entire storage dir.

## Target architecture

```
┌──────────────────────────────────────────────────────────────┐
│ Claude Code skills                                           │
│   /lightrag-start  /lightrag-stop  /lightrag-eject           │
│   /lightrag-query  /lightrag-explore  /lightrag-status       │
│   /lightrag-upload  /raganything-upload                      │
│   /db-snapshot  /db-restore  /db-list-snapshots  /db-grow    │
│   /lightrag-upgrade                                          │
└────────────┬─────────────────────────────────────────────────┘
             │ REST :9622 (host) → :9621 (container)
   ┌─────────▼──────────────┐
   │ LightRAG server        │  Container
   │  FastAPI + PG drivers  │  pinned: lightrag-hku==1.4.5
   └─────────┬──────────────┘
             │ asyncpg → postgres:5432 (compose-internal)
   ┌─────────▼─────────────────────────────────────────┐
   │ Postgres 16                                       │  Container
   │   image: pgvector/pgvector:pg16 + AGE v1.5.0      │
   │   ├─ pgvector  — vectors  (HNSW indexes)          │
   │   ├─ AGE       — graph    (Cypher subset)         │
   │   ├─ tables    — KV + doc_status                  │
   │   └─ lightrag_meta — schema version stamp         │
   │   data dir: ext4 inside loopback /pgdata-vol      │
   └────────────────────┬──────────────────────────────┘
                        │ depends_on (service_completed_successfully)
   ┌────────────────────▼──────────────────────────────┐
   │ pg-init                                           │  Container (one-shot, privileged)
   │   mount -o loop /mnt/host/pgdata.ext4.img → ...   │
   │   chown postgres:postgres /pgdata-vol             │
   │   exit 0                                          │
   └────────────────────┬──────────────────────────────┘
                        │ bind-mounts the .img file from host
                        ▼
                   ┌──────────────────────────────────────────┐
                   │ /Volumes/Crucial-4T/rag-anything/        │  Host (ExFAT)
                   │   pgdata.ext4.img                        │
                   └──────────────────────────────────────────┘

   ┌───────────────────────────────────────────────┐
   │ Ollama                                        │  Native, port 11434
   │   models: /Volumes/Crucial-4T/.../ollama/     │  bind via OLLAMA_MODELS env
   │   qwen2.5vl:7b + bge-m3                       │
   └───────────────────────────────────────────────┘
   ┌───────────────────────────────────────────────┐
   │ MinerU                                        │  Native, in ~/rag-anything/.venv/
   │   device probe: mps / cuda / cpu              │
   │   models: /Volumes/Crucial-4T/.../mineru/     │
   └───────────────────────────────────────────────┘
```

Service composition rationale:

- **Postgres + LightRAG server containerized.** No GPU need; lifecycle is
  network-only; compose handles ordering + healthchecks cleanly.
- **Ollama + MinerU native.** Both need GPU. Apple Metal (MPS) cannot be
  exposed to Docker containers on macOS; running these natively keeps the
  fast path on Mac (5-10 tok/s with qwen2.5vl 7B) instead of CPU-only in
  a container (~0.5 tok/s).
- **`pg-init` one-shot.** Mounts the ext4 image as a loopback device
  inside the Docker Linux VM, runs once per `docker compose up`. Postgres
  service `depends_on: pg-init: service_completed_successfully`.

## Storage layout

```
/Volumes/Crucial-4T/                                ← ExFAT, cross-OS readable
├── repo/ragonfire/                                 ← this repo (source on drive)
│   ├── infra/
│   │   ├── postgres/
│   │   │   ├── Dockerfile                          ← pgvector base + AGE build
│   │   │   └── init.sql                            ← extensions + meta table
│   │   ├── pg-init/
│   │   │   └── Dockerfile                          ← loop-mount helper
│   │   └── docker-compose.yml
│   ├── rag-anything/
│   │   ├── bootstrap.sh                            ← OS-agnostic
│   │   ├── requirements.txt                        ← pinned
│   │   ├── .env.example
│   │   ├── scripts/
│   │   │   ├── ingest.py                           ← repointed to PG via env
│   │   │   ├── db-init.sh                          ← one-time .img creation
│   │   │   ├── db-grow.sh                          ← grow .img cap
│   │   │   ├── mineru-device.sh                    ← MPS/CUDA/CPU probe
│   │   │   └── ...
│   │   └── skills/                                 ← installed to ~/.claude/skills/
│   └── docs/superpowers/specs/...
└── rag-anything/                                   ← runtime data (ExFAT)
    ├── pgdata.ext4.img                             ← live PG bytes (50 GB cap, growable)
    ├── input/                                      ← drop-zone for ingest
    ├── output/                                     ← MinerU parsed artifacts
    ├── backups/
    │   └── pgdump-YYYYMMDD-HHMMSS.sql.gz           ← manual snapshots
    └── models/
        ├── ollama/                                 ← OLLAMA_MODELS env
        ├── hf/                                     ← HF_HOME env
        └── mineru/                                 ← MINERU_MODELS_DIR env

~/rag-anything/                                     ← host internal SSD (POSIX required)
├── .venv/                                          ← Python venv (created by bootstrap)
├── .env                                            ← symlink to drive's .env (or copy)
└── logs/                                           ← server stdout/err + PID
```

The ext4 loopback image is the central trick: the `.img` file lives on
ExFAT (no POSIX semantics) but its INTERIOR is a real ext4 filesystem
(full POSIX, fsync, hardlinks, permissions) that Postgres can write to
safely. The loopback driver translates ext4 block writes into byte-range
writes on the underlying file, which ExFAT handles as ordinary file I/O.

## Component details

### `infra/postgres/Dockerfile`

```dockerfile
FROM pgvector/pgvector:pg16
ARG AGE_VERSION=v1.5.0
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git postgresql-server-dev-16 flex bison \
 && git clone --depth 1 --branch ${AGE_VERSION} https://github.com/apache/age.git /tmp/age \
 && cd /tmp/age && make install \
 && rm -rf /tmp/age \
 && apt-get purge -y build-essential git flex bison postgresql-server-dev-16 \
 && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
```

Image size ~250 MB after cleanup. AGE source build adds ~2 min to first
`docker compose build`; subsequent builds are cached.

### `infra/postgres/init.sql`

Runs once on first container boot via `/docker-entrypoint-initdb.d/`:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS age;
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

CREATE TABLE IF NOT EXISTS lightrag_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- bootstrap.sh writes lightrag_version row after first server start.
```

LightRAG auto-creates its own tables on first connection.

### `infra/pg-init/Dockerfile`

Minimal Alpine image with `e2fsprogs` and `util-linux`:

```dockerfile
FROM alpine:3.20
RUN apk add --no-cache util-linux e2fsprogs
COPY mount-loop.sh /usr/local/bin/
ENTRYPOINT ["/usr/local/bin/mount-loop.sh"]
```

`mount-loop.sh` mounts `/mnt/host/pgdata.ext4.img` (bind-mounted from host)
onto `/pgdata-vol` (shared volume with postgres service) via `mount -o loop`,
chowns to `postgres:postgres`, exits 0.

### `infra/docker-compose.yml`

```yaml
services:
  pg-init:
    build: ./pg-init
    privileged: true
    volumes:
      - /Volumes/Crucial-4T/rag-anything/pgdata.ext4.img:/mnt/host/pgdata.ext4.img
      - pgdata-vol:/pgdata-vol
    restart: "no"

  postgres:
    build: ./postgres
    container_name: ragonfire-postgres
    environment:
      POSTGRES_USER: ragonfire
      POSTGRES_PASSWORD: ragonfire
      POSTGRES_DB: ragonfire
      PGDATA: /pgdata-vol/pg
    ports:
      - "127.0.0.1:5433:5432"   # loopback only, non-default to avoid host PG collisions
    volumes:
      - pgdata-vol:/pgdata-vol
      - ./postgres/init.sql:/docker-entrypoint-initdb.d/00-init.sql:ro
    depends_on:
      pg-init:
        condition: service_completed_successfully
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ragonfire -d ragonfire"]
      interval: 5s
      timeout: 3s
      retries: 20
    networks: [internal]

  lightrag-server:
    image: ragonfire/lightrag-server:1.4.5   # built by infra/lightrag-server/Dockerfile
    ports:
      - "127.0.0.1:9622:9621"
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      # ... (full env in .env.example)
    depends_on:
      postgres:
        condition: service_healthy
    networks: [internal]

volumes:
  pgdata-vol:

networks:
  internal:
    driver: bridge
```

Postgres host port `127.0.0.1:5433` (non-default 5432) avoids collision
with any existing development Postgres on the host. Inter-container
traffic uses the compose-internal hostname `postgres:5432`.

### Pinned dependencies

```
# rag-anything/requirements.txt
lightrag-hku[api]==1.4.5
raganything[all]==1.2.4
mineru[core]==2.5.4
asyncpg==0.30.0
psycopg[binary]==3.2.3
ollama==0.4.7
python-dotenv==1.0.1
```

Image base: `pgvector/pgvector:pg16` (implicit pgvector 0.8.x, locked by
image tag). AGE pinned via Dockerfile ARG: `AGE_VERSION=v1.5.0`.

### `.env.example` (delta from current)

```ini
# Postgres (LightRAG storage backend)
POSTGRES_HOST=postgres            # compose-internal hostname (lightrag-server)
POSTGRES_HOST_EXTERNAL=localhost  # for host-side tools (DBeaver/psql)
POSTGRES_PORT_EXTERNAL=5433
POSTGRES_USER=ragonfire
POSTGRES_PASSWORD=ragonfire
POSTGRES_DATABASE=ragonfire
POSTGRES_WORKSPACE=default

LIGHTRAG_KV_STORAGE=PGKVStorage
LIGHTRAG_VECTOR_STORAGE=PGVectorStorage
LIGHTRAG_GRAPH_STORAGE=PGGraphStorage
LIGHTRAG_DOC_STATUS_STORAGE=PGDocStatusStorage

# pgvector HNSW (set on first PGVectorStorage init by LightRAG)
HNSW_M=16
HNSW_EF_CONSTRUCTION=64
HNSW_EF_SEARCH=40

# Bulk data on Crucial-4T (ExFAT, cross-OS)
INPUT_DIR=/Volumes/Crucial-4T/rag-anything/input
OUTPUT_DIR=/Volumes/Crucial-4T/rag-anything/output
WORKING_DIR=/Volumes/Crucial-4T/rag-anything/working   # ancillary LightRAG cache only
BACKUPS_DIR=/Volumes/Crucial-4T/rag-anything/backups

# Model caches on Crucial-4T (immutable blobs, sequential I/O — ExFAT OK)
OLLAMA_MODELS=/Volumes/Crucial-4T/rag-anything/models/ollama
HF_HOME=/Volumes/Crucial-4T/rag-anything/models/hf
MINERU_MODELS_DIR=/Volumes/Crucial-4T/rag-anything/models/mineru

# Loopback image
PGDATA_IMG=/Volumes/Crucial-4T/rag-anything/pgdata.ext4.img
PGDATA_IMG_CAP=50G

# MinerU device probe (auto → mps on macOS w/ MPS, cuda if available, else cpu)
MINERU_DEVICE=auto

# LightRAG server (host-facing port differs from container-internal)
LIGHTRAG_PORT_EXTERNAL=9622
LIGHTRAG_PORT_INTERNAL=9621
HOST=0.0.0.0
PORT=9621

# Ollama / embeddings / chunking — unchanged from current spec
LLM_BINDING=ollama
LLM_BINDING_HOST=http://host.docker.internal:11434
LLM_MODEL=qwen2.5vl:7b
EMBEDDING_BINDING=ollama
EMBEDDING_BINDING_HOST=http://host.docker.internal:11434
EMBEDDING_MODEL=bge-m3
EMBEDDING_DIM=1024
TOP_K=40
COSINE_THRESHOLD=0.2
CHUNK_SIZE=1200
CHUNK_OVERLAP_SIZE=100
```

LightRAG server container reaches host-native Ollama via the
Docker-provided `host.docker.internal` hostname.

### Bootstrap (`rag-anything/bootstrap.sh`)

Refactored OS-agnostic flow:

```
1. detect OS (uname → darwin | linux | wsl)
2. ensure Docker installed + daemon running (fail w/ install URL otherwise)
3. ensure Ollama installed (brew / apt / dnf / pacman / winget) + service running
4. ensure uv installed (curl install if missing)
5. pull ollama models (qwen2.5vl:7b, bge-m3) into $OLLAMA_MODELS
6. ./scripts/db-init.sh
     → if $PGDATA_IMG missing: create sparse 50GB file, mkfs.ext4 inside helper container
7. uv venv ~/rag-anything/.venv (Python 3.12)
8. uv pip install -r requirements.txt  → into venv
9. docker compose -f infra/docker-compose.yml build postgres lightrag-server
10. ./scripts/install-skills.sh --agent <claude-code|codex|all>
11. print next-step hint: "Run /lightrag-start to boot."
```

OS branches live in `infra/os/install-ollama.sh`, `infra/os/install-uv.sh`,
`infra/os/install-docker.sh` (the last only prints the platform-specific
URL — installing Docker programmatically is unsafe across OSes).

### Skills (new + repointed)

| Skill | Action |
|-------|--------|
| `/lightrag-start` | ensure Ollama daemon running → `docker compose up -d` → wait postgres healthy → wait `/health` on lightrag-server → check `lightrag_meta` version matches code → ready |
| `/lightrag-stop` | `docker compose stop` (graceful PG checkpoint + clean loop unmount) → `ollama stop qwen2.5vl:7b` (unload model from GPU) — daemon stays |
| `/lightrag-eject` | `/lightrag-stop` → `sync` → `diskutil eject` (mac) / `udisksctl power-off` (linux) — prints "safe to unplug" |
| `/lightrag-status` | health, doc counts, top entities — repointed to PG via REST as today |
| `/lightrag-query`, `/lightrag-explore`, `/lightrag-upload`, `/raganything-upload` | unchanged interface; PG backend underneath |
| `/db-snapshot` | `pg_dump | gzip > backups/pgdump-YYYYMMDD-HHMMSS.sql.gz` |
| `/db-restore [filename]` | restore from named or latest dump (refuses if PG not empty without `--force`) |
| `/db-list-snapshots` | lists dumps with size + timestamp |
| `/db-grow <new-size>` | `/lightrag-stop` → `truncate -s <new-size>` → `e2fsck` → `resize2fs` (inside helper container) → `/lightrag-start` |
| `/lightrag-upgrade` | bumps `lightrag_meta` version, snapshots, wipes `.img`, re-inits, replays `input/` |

`/lightrag-stop` deliberately stops everything (containers + Ollama
model). User wants one command for "I'm done." Granular control sits in
the `/db-*` skills.

### Schema-evolution policy

`lightrag_meta` table is written on first start with `lightrag_version` =
the pinned version from `requirements.txt`. Every `/lightrag-start`
checks: if the stored version disagrees with the installed library, the
skill refuses to start and instructs the user to run `/lightrag-upgrade`.
`/lightrag-upgrade` is the only path that touches the version stamp.

This blocks silent corruption when a user bumps the pin without
re-initialising.

### MinerU device probe (`mineru-device.sh`)

```bash
#!/usr/bin/env bash
~/rag-anything/.venv/bin/python - <<'EOF'
import sys
try:
    import torch
    if torch.backends.mps.is_available():
        print("mps"); sys.exit(0)
    if torch.cuda.is_available():
        print("cuda"); sys.exit(0)
except Exception:
    pass
print("cpu")
EOF
```

`ingest.py` reads this if `MINERU_DEVICE=auto`.

## Data flow (ingest)

```
PDF dropped in /Volumes/Crucial-4T/rag-anything/input/
    │
    ▼ /raganything-upload <file>
host ingest.py (in ~/rag-anything/.venv)
    │
    ▼  MinerU (native, MPS/CUDA/CPU)
parsed artifacts → /Volumes/Crucial-4T/rag-anything/output/<doc-slug>/
    │
    ▼  RAG-Anything dispatcher
text → Ollama qwen2.5vl  ┐
table → Ollama qwen2.5vl │  (host-native, port 11434)
image → Ollama qwen2.5vl │
equation → Ollama qwen2.5vl ┘
    │
    ▼  LightRAG Python lib (PGStorage backends)
asyncpg INSERTs → Postgres container :5433 host port / postgres:5432 internal
    │
    ▼
vectors (HNSW)  +  graph (AGE)  +  KV  +  doc_status   inside pgdata.ext4.img
```

## Data flow (query)

```
/lightrag-query "..."
    │
    ▼ HTTP POST :9622/query
LightRAG server (container)
    │
    ▼ hybrid retrieval
asyncpg → Postgres (pgvector HNSW search + AGE Cypher traversal)
    │
    ▼ context assembly
Ollama qwen2.5vl (host-native) for final answer generation
    │
    ▼
JSON response → user
```

## New-PC bring-up

```
1. Plug Crucial-4T into a new machine (mac, linux, or windows-WSL2)
2. Install Docker:
     macOS: brew install --cask docker
     Linux: apt install docker.io docker-compose-plugin
     Windows: install Docker Desktop with WSL2 backend
3. cd /Volumes/Crucial-4T/repo/ragonfire   (path may differ on linux/windows)
4. ./rag-anything/bootstrap.sh
     - installs Ollama (native) + uv + venv + skills
     - leaves existing pgdata.ext4.img untouched (mounts on next /lightrag-start)
5. /lightrag-start
     - same 50 GB ext4 image is mounted; same vectors/graph/KV come up
6. Query/ingest as normal.
```

The drive carries: source code, compose definitions, pinned
requirements, `.env`, models, parsed artifacts, the live PG image, and
optional snapshots. The host carries: Docker, Ollama, a fresh venv. Two
sources, both regenerable except for the `.img` itself.

## Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| Drive yanked while PG mounted → ext4 corruption | `/lightrag-eject` is the documented unplug procedure. Bootstrap and README emphasize it. Mount uses `data=ordered` (ext4 default) so journal replays cleanly on next mount. |
| `truncate -s` on ExFAT preallocates instead of sparse | Accepted. 50 GB initial = 1.25% of drive. Grow procedure exists for later. |
| `.img` cap hit mid-ingest | LightRAG inserts surface as `psycopg.errors.DiskFull`. `/db-grow` documented in error message. |
| LightRAG schema breakage on pin bump | `lightrag_meta` version stamp + `/lightrag-upgrade` skill blocks silent corruption. |
| AGE community smaller than Neo4j | Accepted. Single-DB simplicity > bus-factor concern at 500 GB personal-KB scale. Migration path (AGE → Neo4j) is `lightrag_meta` flip + re-index, not re-ingest. |
| macOS Docker Desktop loopback perf hit (~50% writes via virtiofs) | Accepted. RAG workload is read-heavy after ingest; ingest is offline. Linux native = full speed. |
| Ollama on ExFAT (no xattrs, no fsync semantics) | Verified compatible — Ollama uses sequential reads + mmap on immutable blob files; xattrs not used. Lock the manifest file location via OLLAMA_MODELS env. |
| New PC lacks GPU (Linux box w/o NVIDIA, mac w/o Apple Silicon) | Ollama falls back to CPU automatically (slower but correct). MinerU device probe falls back to cpu. Bootstrap warns. |

## Testing

Smoke test (`scripts/smoke-test.sh`, new):

1. `/lightrag-start`
2. Ingest `tests/fixtures/sample.pdf` (small 2-page synthetic PDF shipped
   in repo, contains a known phrase + a known entity)
3. Query: assert non-empty answer containing the known phrase
4. Inspect graph: query `ag_catalog.ag_graph` for the corpus's graph row,
   then Cypher `MATCH (n) RETURN count(n)` — assert > 0
5. Inspect vectors: query `information_schema.tables` for the LightRAG
   vector tables, assert at least one has rows
6. `/db-snapshot` → assert new file in `backups/`
7. `/lightrag-stop`

CI (`.github/workflows/smoke.yml`, new):

- Runs on `push` to any branch and on `pull_request`.
- Linux runner. Spins up only the Postgres service via compose.
- Stubs Ollama with a tiny mock HTTP server returning fixed 1024-d zero
  vectors (matches `bge-m3` dim) and stub LLM responses.
- Goal: catch breakage in PG storage wiring on Linux. Full ingest is too
  heavy for CI and is exercised manually on developer machines.

## Open questions

None blocking. Deferred to follow-up specs if needed:

- Optional Neo4j path (separate graph DB) — possible if AGE proves
  inadequate; LightRAG storage abstraction makes it a config flip.
- WAL-shipping incremental backups — possible if `pg_dump` snapshots
  become too large at >100 GB live DB; pgBackRest is the obvious choice.
- Native (non-Docker) Postgres install path across OSes — currently
  rejected; revisit only if Docker dependency becomes a real blocker.
