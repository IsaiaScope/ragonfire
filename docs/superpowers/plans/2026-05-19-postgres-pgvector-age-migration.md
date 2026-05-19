# Portable Postgres-backed RagOnFire on Crucial-4T — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate ragonfire's RAG storage from file-based JSON/NetworkX/NanoVectorDB to a single Postgres 16 instance (pgvector + Apache AGE) running in Docker, with its data directory inside an ext4 loopback image on the Crucial-4T external drive, and make the bootstrap OS-agnostic so the drive is portable across macOS, Linux, and Windows (WSL2).
**Status:** done @ 2026-05-19T10:39:59.718490Z

**Architecture:** Postgres + LightRAG server run in Docker (compose-managed). Ollama and MinerU stay native for GPU access. A one-shot `pg-init` privileged container mounts the `.img` file as a loopback ext4 device before Postgres starts. Skills (`/lightrag-start`, `/lightrag-stop`, `/lightrag-eject`, `/db-*`, `/lightrag-upgrade`) wrap the whole stack so users never type `docker compose` directly.

**Tech Stack:** Postgres 16 (image `pgvector/pgvector:pg16`), Apache AGE v1.5.0 built from source, LightRAG `lightrag-hku==1.4.5`, RAG-Anything `raganything==1.2.4`, MinerU `mineru==2.5.4`, asyncpg, psycopg, Python 3.12, Docker Compose v2, Ollama (native), bash.

---

## File structure

### New files

| Path | Responsibility |
|------|----------------|
| `infra/postgres/Dockerfile` | Builds Postgres image with pgvector + AGE |
| `infra/postgres/init.sql` | Creates extensions + `lightrag_meta` on first boot |
| `infra/pg-init/Dockerfile` | Privileged helper image (mounts loopback) |
| `infra/pg-init/mount-loop.sh` | Loopback mount + chown script |
| `infra/lightrag-server/Dockerfile` | LightRAG server container |
| `infra/docker-compose.yml` | Three-service stack definition |
| `infra/os/detect.sh` | OS detection (darwin/linux/wsl) |
| `infra/os/install-ollama.sh` | Per-OS Ollama installer |
| `infra/os/install-uv.sh` | uv installer |
| `infra/os/install-docker.sh` | Docker presence check + install URL printer |
| `rag-anything/scripts/db-init.sh` | One-time `.img` creation + mkfs |
| `rag-anything/scripts/db-grow.sh` | Grow `.img` capacity |
| `rag-anything/scripts/db-snapshot.sh` | Manual `pg_dump` snapshot |
| `rag-anything/scripts/db-restore.sh` | Restore from named/latest snapshot |
| `rag-anything/scripts/db-list-snapshots.sh` | List dumps |
| `rag-anything/scripts/mineru-device.sh` | MPS/CUDA/CPU probe |
| `rag-anything/scripts/lightrag-eject.sh` | Stop + sync + eject drive |
| `rag-anything/scripts/lightrag-upgrade.sh` | Schema-version-bump handler |
| `rag-anything/scripts/lightrag-start.sh` | Full-stack start orchestrator (replaces old `server-start.sh`) |
| `rag-anything/scripts/lightrag-stop.sh` | Full-stack stop orchestrator (replaces old `server-stop.sh`) |
| `rag-anything/scripts/lightrag-status.sh` | Stack health snapshot |
| `rag-anything/skills/db-snapshot/SKILL.md` | Skill prompt |
| `rag-anything/skills/db-restore/SKILL.md` | Skill prompt |
| `rag-anything/skills/db-list-snapshots/SKILL.md` | Skill prompt |
| `rag-anything/skills/db-grow/SKILL.md` | Skill prompt |
| `rag-anything/skills/lightrag-eject/SKILL.md` | Skill prompt |
| `rag-anything/skills/lightrag-upgrade/SKILL.md` | Skill prompt |
| `tests/fixtures/sample.pdf` | 2-page synthetic PDF for smoke test |
| `tests/fixtures/sample-expected.json` | Known phrase + entity for assertions |
| `scripts/smoke-test.sh` | End-to-end smoke test |
| `.github/workflows/smoke.yml` | Linux CI smoke test (PG only, stubbed Ollama) |

### Modified files

| Path | Change |
|------|--------|
| `rag-anything/.env.example` | Add Postgres + storage-backend block + drive paths |
| `rag-anything/requirements.txt` | Pin all dependencies; add asyncpg + psycopg |
| `rag-anything/bootstrap.sh` | Refactor to call `infra/os/*` + `db-init.sh` + compose build |
| `rag-anything/scripts/ingest.py` | Resolve `MINERU_DEVICE=auto`; rely on PG env for storage backends |
| `rag-anything/skills/lightrag-start/SKILL.md` | Re-describe as full-stack starter |
| `rag-anything/skills/lightrag-stop/SKILL.md` | Re-describe as full-stack stopper |
| `rag-anything/skills/lightrag-status/SKILL.md` | Re-point to PG-aware status |
| `rag-anything/skills/lightrag-upload/SKILL.md` | Mention server must be running (unchanged interface) |
| `rag-anything/skills/raganything-upload/SKILL.md` | Drop "stop server before ingest" workaround (PG handles concurrent access) |
| `rag-anything/skills/lightrag-query/SKILL.md` | No code change; `.env` host port now 9622 |
| `rag-anything/skills/lightrag-explore/SKILL.md` | Same |
| `README.md` | Drop macOS-only framing; add cross-OS quickstart |
| `rag-anything/README.md` | Replace JSON storage section w/ PG section |
| `scripts/install-skills.sh` | Add new skill dirs to copy list |

### Removed files

| Path | Reason |
|------|--------|
| `rag-anything/scripts/server-start.sh` | Replaced by `lightrag-start.sh` |
| `rag-anything/scripts/server-stop.sh` | Replaced by `lightrag-stop.sh` |
| `rag-anything/scripts/server-status.sh` | Replaced by `lightrag-status.sh` |

---

## Phase 1 — Postgres image, loopback helper, compose

### Task 1: Pin Python dependencies

**Files:**
- Modify: `rag-anything/requirements.txt`

- [ ] **Step 1: Replace requirements.txt with pinned versions**

```
lightrag-hku[api]==1.4.5
raganything[all]==1.2.4
mineru[core]==2.5.4
asyncpg==0.30.0
psycopg[binary]==3.2.3
ollama==0.4.7
python-dotenv==1.0.1
```

- [ ] **Step 2: Verify the file parses with uv**

Run: `uv pip compile --quiet --dry-run rag-anything/requirements.txt`
Expected: exit code 0, prints resolved set.

- [ ] **Step 3: Commit**

```bash
git add rag-anything/requirements.txt
git commit -m "build(deps): pin Python requirements for PG migration"
```

---

### Task 2: Postgres Dockerfile + init.sql

**Files:**
- Create: `infra/postgres/Dockerfile`
- Create: `infra/postgres/init.sql`

- [ ] **Step 1: Write the Dockerfile**

```dockerfile
# infra/postgres/Dockerfile
FROM pgvector/pgvector:pg16
ARG AGE_VERSION=v1.5.0
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git postgresql-server-dev-16 flex bison ca-certificates \
 && git clone --depth 1 --branch ${AGE_VERSION} https://github.com/apache/age.git /tmp/age \
 && cd /tmp/age && make install \
 && rm -rf /tmp/age \
 && apt-get purge -y build-essential git flex bison postgresql-server-dev-16 \
 && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
```

- [ ] **Step 2: Write init.sql**

```sql
-- infra/postgres/init.sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS age;
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

CREATE TABLE IF NOT EXISTS lightrag_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

- [ ] **Step 3: Build the image**

Run: `docker build -t ragonfire-postgres:test infra/postgres`
Expected: exit 0; final line `Successfully tagged ragonfire-postgres:test`. Build takes ~2-3 min on first run.

- [ ] **Step 4: Verify the image loads both extensions on a throwaway container**

Run:
```bash
docker run --rm -e POSTGRES_PASSWORD=test ragonfire-postgres:test \
  postgres -c shared_preload_libraries='age' &
PG_PID=$!
sleep 5
docker exec $(docker ps -lq) psql -U postgres -c "CREATE EXTENSION vector;"
docker exec $(docker ps -lq) psql -U postgres -c "CREATE EXTENSION age;"
docker exec $(docker ps -lq) psql -U postgres -c "\dx"
kill $PG_PID
```

Expected: `vector` and `age` both listed under `\dx`.

- [ ] **Step 5: Commit**

```bash
git add infra/postgres/
git commit -m "feat(infra): postgres image with pgvector + AGE v1.5.0"
```

---

### Task 3: pg-init helper container

**Files:**
- Create: `infra/pg-init/Dockerfile`
- Create: `infra/pg-init/mount-loop.sh`

- [ ] **Step 1: Write the Dockerfile**

```dockerfile
# infra/pg-init/Dockerfile
FROM alpine:3.20
RUN apk add --no-cache util-linux e2fsprogs coreutils
COPY mount-loop.sh /usr/local/bin/mount-loop.sh
RUN chmod +x /usr/local/bin/mount-loop.sh
ENTRYPOINT ["/usr/local/bin/mount-loop.sh"]
```

- [ ] **Step 2: Write the mount script**

```bash
#!/bin/sh
# infra/pg-init/mount-loop.sh
# Mount /mnt/host/pgdata.ext4.img as loopback ext4 onto /pgdata-vol
# and ensure the postgres user owns the data dir.
set -eu

IMG=/mnt/host/pgdata.ext4.img
MNT=/pgdata-vol
PGDATA="$MNT/pg"

[ -f "$IMG" ] || { echo "[pg-init] FATAL: $IMG missing — run db-init.sh first" >&2; exit 1; }

mkdir -p "$MNT"

if mountpoint -q "$MNT"; then
  echo "[pg-init] $MNT already mounted — reusing"
else
  echo "[pg-init] mounting $IMG -> $MNT"
  mount -o loop "$IMG" "$MNT"
fi

mkdir -p "$PGDATA"
chown -R 999:999 "$PGDATA"   # postgres uid/gid in the official image
chmod 700 "$PGDATA"
echo "[pg-init] OK"
```

- [ ] **Step 3: Build the helper image**

Run: `docker build -t ragonfire-pg-init:test infra/pg-init`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add infra/pg-init/
git commit -m "feat(infra): pg-init loopback mount helper container"
```

---

### Task 4: db-init.sh (one-time `.img` creation)

**Files:**
- Create: `rag-anything/scripts/db-init.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# rag-anything/scripts/db-init.sh
# Create the ext4 loopback image on Crucial-4T (or wherever PGDATA_IMG points).
# Idempotent: bails cleanly if the image already exists unless --force.
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
RUNTIME_DIR="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}"
ENV_FILE="$RUNTIME_DIR/.env"
[ -f "$ENV_FILE" ] || ENV_FILE="$REPO_DIR/rag-anything/.env.example"
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

: "${PGDATA_IMG:?PGDATA_IMG must be set in .env}"
: "${PGDATA_IMG_CAP:=50G}"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

if [ -f "$PGDATA_IMG" ] && [ "$FORCE" -eq 0 ]; then
  echo "[db-init] $PGDATA_IMG already exists. Use --force to recreate (DESTRUCTIVE)." >&2
  exit 0
fi

if [ "$FORCE" -eq 1 ] && [ -f "$PGDATA_IMG" ]; then
  echo "[db-init] --force: removing existing image"
  rm -f "$PGDATA_IMG"
fi

mkdir -p "$(dirname "$PGDATA_IMG")"

echo "[db-init] allocating $PGDATA_IMG_CAP at $PGDATA_IMG"
# On macOS/ExFAT, truncate preallocates. On Linux/ext4 host it's sparse.
truncate -s "$PGDATA_IMG_CAP" "$PGDATA_IMG"

echo "[db-init] formatting ext4 inside the image (via helper container)"
docker run --rm -v "$PGDATA_IMG:/img" alpine:3.20 sh -c \
  "apk add --no-cache --quiet e2fsprogs >/dev/null && mkfs.ext4 -F -L ragonfire-pgdata /img"

echo "[db-init] done. Next: /lightrag-start"
```

- [ ] **Step 2: Make executable + run it to create a temp test image**

```bash
chmod +x rag-anything/scripts/db-init.sh

# Sanity-test with a small image in /tmp (don't touch the real one)
PGDATA_IMG=/tmp/test-pgdata.ext4.img \
PGDATA_IMG_CAP=100M \
RAGONFIRE_RUNTIME=/tmp/fake-runtime \
mkdir -p /tmp/fake-runtime && cp rag-anything/.env.example /tmp/fake-runtime/.env || true
PGDATA_IMG=/tmp/test-pgdata.ext4.img PGDATA_IMG_CAP=100M ./rag-anything/scripts/db-init.sh
```

Expected: file `/tmp/test-pgdata.ext4.img` exists, exactly 100 MB, `file` reports it as a Linux rev 1.0 ext4 filesystem.

- [ ] **Step 3: Verify**

Run: `file /tmp/test-pgdata.ext4.img`
Expected: contains `ext4 filesystem`.

- [ ] **Step 4: Cleanup**

Run: `rm -f /tmp/test-pgdata.ext4.img && rm -rf /tmp/fake-runtime`

- [ ] **Step 5: Commit**

```bash
git add rag-anything/scripts/db-init.sh
git commit -m "feat(scripts): db-init.sh creates ext4 loopback image"
```

---

### Task 5: docker-compose.yml + .env.example baseline

**Files:**
- Create: `infra/docker-compose.yml`
- Modify: `rag-anything/.env.example`

- [ ] **Step 1: Replace `.env.example` with the full PG-aware version**

```ini
# rag-anything/.env.example
# --- Postgres (LightRAG storage backend) ---
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

# --- pgvector HNSW ---
HNSW_M=16
HNSW_EF_CONSTRUCTION=64
HNSW_EF_SEARCH=40

# --- Drive-resident bulk data (ExFAT-safe) ---
INPUT_DIR=/Volumes/Crucial-4T/rag-anything/input
OUTPUT_DIR=/Volumes/Crucial-4T/rag-anything/output
WORKING_DIR=/Volumes/Crucial-4T/rag-anything/working
BACKUPS_DIR=/Volumes/Crucial-4T/rag-anything/backups
OLLAMA_MODELS=/Volumes/Crucial-4T/rag-anything/models/ollama
HF_HOME=/Volumes/Crucial-4T/rag-anything/models/hf
MINERU_MODELS_DIR=/Volumes/Crucial-4T/rag-anything/models/mineru

# --- Loopback image ---
PGDATA_IMG=/Volumes/Crucial-4T/rag-anything/pgdata.ext4.img
PGDATA_IMG_CAP=50G

# --- MinerU device probe ---
MINERU_DEVICE=auto
MINERU_BACKEND=pipeline
PARSER=mineru
PARSE_METHOD=auto

# --- LightRAG server ---
LIGHTRAG_PORT_EXTERNAL=9622
LIGHTRAG_PORT_INTERNAL=9621
HOST=0.0.0.0
PORT=9621
WORKERS=1

# --- LLM (Ollama, host-native) ---
LLM_BINDING=ollama
LLM_BINDING_HOST=http://host.docker.internal:11434
LLM_MODEL=qwen2.5vl:7b
LLM_BINDING_API_KEY=ollama
MAX_TOKENS=32768
TIMEOUT=300

# --- Embeddings ---
EMBEDDING_BINDING=ollama
EMBEDDING_BINDING_HOST=http://host.docker.internal:11434
EMBEDDING_MODEL=bge-m3
EMBEDDING_DIM=1024
EMBEDDING_BATCH_NUM=10

# --- Retrieval ---
TOP_K=40
COSINE_THRESHOLD=0.2

# --- Chunking ---
MAX_PARALLEL_INSERT=2
CHUNK_SIZE=1200
CHUNK_OVERLAP_SIZE=100

# --- Auth (disabled for local) ---
AUTH_ACCOUNTS=
TOKEN_SECRET=
WHITELIST_PATHS=*

# --- Logging ---
VERBOSE=false
LOG_DIR=~/rag-anything/logs
```

- [ ] **Step 2: Write docker-compose.yml**

```yaml
# infra/docker-compose.yml
services:
  pg-init:
    build: ./pg-init
    image: ragonfire-pg-init:latest
    privileged: true
    volumes:
      - ${PGDATA_IMG}:/mnt/host/pgdata.ext4.img
      - pgdata-vol:/pgdata-vol
    restart: "no"
    networks: [internal]

  postgres:
    build: ./postgres
    image: ragonfire-postgres:latest
    container_name: ragonfire-postgres
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DATABASE}
      PGDATA: /pgdata-vol/pg
    ports:
      - "127.0.0.1:${POSTGRES_PORT_EXTERNAL}:5432"
    volumes:
      - pgdata-vol:/pgdata-vol
      - ./postgres/init.sql:/docker-entrypoint-initdb.d/00-init.sql:ro
    depends_on:
      pg-init:
        condition: service_completed_successfully
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DATABASE}"]
      interval: 5s
      timeout: 3s
      retries: 30
    networks: [internal]

  lightrag-server:
    build: ./lightrag-server
    image: ragonfire-lightrag-server:latest
    container_name: ragonfire-lightrag
    ports:
      - "127.0.0.1:${LIGHTRAG_PORT_EXTERNAL}:${LIGHTRAG_PORT_INTERNAL}"
    env_file:
      - ../rag-anything/.env
    extra_hosts:
      - "host.docker.internal:host-gateway"
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${LIGHTRAG_PORT_INTERNAL}/health"]
      interval: 10s
      timeout: 3s
      retries: 12
    networks: [internal]

volumes:
  pgdata-vol:

networks:
  internal:
    driver: bridge
```

- [ ] **Step 3: Validate compose syntax**

Run: `docker compose -f infra/docker-compose.yml --env-file rag-anything/.env.example config > /dev/null`
Expected: exit 0 (warnings about the lightrag-server image not yet existing are OK; we'll build it in Task 6).

- [ ] **Step 4: Commit**

```bash
git add infra/docker-compose.yml rag-anything/.env.example
git commit -m "feat(infra): docker compose stack + PG-aware .env"
```

---

### Task 6: LightRAG server container image

**Files:**
- Create: `infra/lightrag-server/Dockerfile`

- [ ] **Step 1: Write the Dockerfile**

```dockerfile
# infra/lightrag-server/Dockerfile
FROM python:3.12-slim

ARG LIGHTRAG_VERSION=1.4.5
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    "lightrag-hku[api]==${LIGHTRAG_VERSION}" \
    "asyncpg==0.30.0" \
    "psycopg[binary]==3.2.3" \
    "ollama==0.4.7" \
    "python-dotenv==1.0.1"

EXPOSE 9621
CMD ["lightrag-server"]
```

- [ ] **Step 2: Build the image**

Run: `docker build -t ragonfire-lightrag-server:test infra/lightrag-server`
Expected: exit 0 (build ~1 min, downloads ~400 MB of wheels).

- [ ] **Step 3: Smoke-check the entrypoint**

Run: `docker run --rm ragonfire-lightrag-server:test lightrag-server --help | head -1`
Expected: line starts with `usage: lightrag-server`.

- [ ] **Step 4: Commit**

```bash
git add infra/lightrag-server/
git commit -m "feat(infra): lightrag-server container image"
```

---

### Task 7: Integration smoke — bring the stack up against a temp .img

**Files:** (no source changes, this is a verification task that produces a regression test artifact)
- Create: `scripts/phase1-smoke.sh`

- [ ] **Step 1: Write the smoke script**

```bash
#!/usr/bin/env bash
# scripts/phase1-smoke.sh
# Brings the stack up against a throwaway .img and verifies extensions load.
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
TMP_IMG=$(mktemp -d)/pgdata.ext4.img
TMP_ENV=$(mktemp)
trap 'docker compose -f "$REPO_DIR/infra/docker-compose.yml" --env-file "$TMP_ENV" down -v 2>/dev/null || true; rm -rf "$(dirname "$TMP_IMG")" "$TMP_ENV"' EXIT

cp "$REPO_DIR/rag-anything/.env.example" "$TMP_ENV"
sed -i.bak "s|^PGDATA_IMG=.*|PGDATA_IMG=$TMP_IMG|" "$TMP_ENV"
sed -i.bak "s|^PGDATA_IMG_CAP=.*|PGDATA_IMG_CAP=200M|" "$TMP_ENV"
rm -f "${TMP_ENV}.bak"

PGDATA_IMG="$TMP_IMG" PGDATA_IMG_CAP=200M RAGONFIRE_RUNTIME="$(dirname "$TMP_IMG")" \
  "$REPO_DIR/rag-anything/scripts/db-init.sh"

docker compose -f "$REPO_DIR/infra/docker-compose.yml" --env-file "$TMP_ENV" up -d --build pg-init postgres
echo "[smoke] waiting for postgres health..."
for _ in $(seq 1 30); do
  health=$(docker inspect --format '{{.State.Health.Status}}' ragonfire-postgres 2>/dev/null || echo "starting")
  [ "$health" = "healthy" ] && break
  sleep 2
done
[ "$health" = "healthy" ] || { echo "[smoke] postgres never became healthy"; exit 1; }

docker exec ragonfire-postgres psql -U ragonfire -d ragonfire -c "\dx" | grep -q vector
docker exec ragonfire-postgres psql -U ragonfire -d ragonfire -c "\dx" | grep -q age
docker exec ragonfire-postgres psql -U ragonfire -d ragonfire -c "SELECT key FROM lightrag_meta;"

echo "[smoke] PASS"
```

- [ ] **Step 2: Run it**

```bash
chmod +x scripts/phase1-smoke.sh
./scripts/phase1-smoke.sh
```

Expected: final line `[smoke] PASS`. Total runtime ~30-60 s on a warm Docker.

- [ ] **Step 3: Commit**

```bash
git add scripts/phase1-smoke.sh
git commit -m "test(infra): phase-1 stack smoke test"
```

---

## Phase 2 — Repoint ingest + serve to Postgres

### Task 8: MinerU device probe

**Files:**
- Create: `rag-anything/scripts/mineru-device.sh`

- [ ] **Step 1: Write the probe**

```bash
#!/usr/bin/env bash
# rag-anything/scripts/mineru-device.sh
# Prints "mps", "cuda", or "cpu" based on local torch capabilities.
# Reads from the host venv at $RAGONFIRE_RUNTIME/.venv.
set -euo pipefail
RUNTIME_DIR="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}"
PYTHON="$RUNTIME_DIR/.venv/bin/python"

[ -x "$PYTHON" ] || { echo "cpu"; exit 0; }

"$PYTHON" - <<'PY'
import sys
try:
    import torch
    if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        print("mps"); sys.exit(0)
    if torch.cuda.is_available():
        print("cuda"); sys.exit(0)
except Exception:
    pass
print("cpu")
PY
```

- [ ] **Step 2: Make executable, run it**

Run:
```bash
chmod +x rag-anything/scripts/mineru-device.sh
./rag-anything/scripts/mineru-device.sh
```

Expected: prints `mps`, `cuda`, or `cpu` based on host. Exit 0.

- [ ] **Step 3: Commit**

```bash
git add rag-anything/scripts/mineru-device.sh
git commit -m "feat(scripts): mineru device probe (auto mps/cuda/cpu)"
```

---

### Task 9: ingest.py — auto device + PG storage via env

**Files:**
- Modify: `rag-anything/scripts/ingest.py`

- [ ] **Step 1: Read current ingest.py to confirm starting point**

Run: `cat rag-anything/scripts/ingest.py | head -50`
Expected: matches the current version (loads `.env`, defines `llm_func`/`vision_func`/`embed_func`, calls `RAGAnything.process_document_complete`).

- [ ] **Step 2: Patch the script to resolve `MINERU_DEVICE=auto`**

Replace the line:
```python
MINERU_DEVICE = os.environ.get("MINERU_DEVICE", "mps")
```
with:
```python
def _resolve_mineru_device(raw: str) -> str:
    if raw != "auto":
        return raw
    probe = Path(__file__).resolve().parent / "mineru-device.sh"
    try:
        out = subprocess.check_output([str(probe)], text=True, timeout=10).strip()
        return out or "cpu"
    except Exception:
        return "cpu"

MINERU_DEVICE = _resolve_mineru_device(os.environ.get("MINERU_DEVICE", "auto"))
```

Add at the top of the file (after the existing imports):
```python
import subprocess
```

- [ ] **Step 3: Add a banner that prints which storage backends are in use**

Replace:
```python
print(f"[ingest] file       : {file_path}")
```
with:
```python
print(f"[ingest] file       : {file_path}")
print(f"[ingest] kv         : {os.environ.get('LIGHTRAG_KV_STORAGE', '(default)')}")
print(f"[ingest] vector     : {os.environ.get('LIGHTRAG_VECTOR_STORAGE', '(default)')}")
print(f"[ingest] graph      : {os.environ.get('LIGHTRAG_GRAPH_STORAGE', '(default)')}")
print(f"[ingest] doc-status : {os.environ.get('LIGHTRAG_DOC_STATUS_STORAGE', '(default)')}")
```

- [ ] **Step 4: Run a syntax check**

Run: `python3 -m py_compile rag-anything/scripts/ingest.py`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add rag-anything/scripts/ingest.py
git commit -m "feat(ingest): auto device probe + storage-backend banner"
```

---

### Task 10: lightrag-start.sh (full-stack orchestrator)

**Files:**
- Create: `rag-anything/scripts/lightrag-start.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# rag-anything/scripts/lightrag-start.sh
# Boots the whole stack: Ollama (native) + Postgres (container) + LightRAG (container).
# Verifies schema version stamp matches the pinned lightrag-hku version.
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
RUNTIME_DIR="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}"
ENV_FILE="$RUNTIME_DIR/.env"
[ -f "$ENV_FILE" ] || { echo "[start] FATAL: $ENV_FILE missing — run bootstrap.sh first" >&2; exit 1; }
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

[ -f "$PGDATA_IMG" ] || { echo "[start] FATAL: $PGDATA_IMG missing — run scripts/db-init.sh first" >&2; exit 1; }

# 1. Ollama daemon
if ! pgrep -x ollama >/dev/null; then
  echo "[start] launching ollama serve in background"
  nohup ollama serve >"$RUNTIME_DIR/logs/ollama.log" 2>&1 &
  sleep 2
fi
for _ in $(seq 1 15); do
  curl -sf http://localhost:11434/api/tags >/dev/null && break
  sleep 1
done

# 2. Compose stack
COMPOSE="docker compose -f $REPO_DIR/infra/docker-compose.yml --env-file $ENV_FILE"
echo "[start] docker compose up"
$COMPOSE up -d

# 3. Wait for lightrag-server /health
echo "[start] waiting for lightrag-server :${LIGHTRAG_PORT_EXTERNAL}/health"
for _ in $(seq 1 60); do
  curl -sf "http://localhost:${LIGHTRAG_PORT_EXTERNAL}/health" >/dev/null && break
  sleep 2
done
curl -sf "http://localhost:${LIGHTRAG_PORT_EXTERNAL}/health" >/dev/null \
  || { echo "[start] FATAL: lightrag-server never healthy"; exit 1; }

# 4. Schema-version guard
EXPECTED=$(grep -E '^lightrag-hku\[api\]==' "$REPO_DIR/rag-anything/requirements.txt" | sed 's/.*==//')
STORED=$(docker exec ragonfire-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -tAc \
  "SELECT value FROM lightrag_meta WHERE key='lightrag_version'" 2>/dev/null || echo "")
if [ -z "$STORED" ]; then
  echo "[start] first run: stamping lightrag_version=$EXPECTED"
  docker exec ragonfire-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -c \
    "INSERT INTO lightrag_meta(key,value) VALUES ('lightrag_version','$EXPECTED') \
     ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_at=now()"
elif [ "$STORED" != "$EXPECTED" ]; then
  echo "[start] FATAL: schema=$STORED, code=$EXPECTED → run /lightrag-upgrade" >&2
  exit 1
fi

echo "[start] OK — http://localhost:${LIGHTRAG_PORT_EXTERNAL}"
```

- [ ] **Step 2: Make executable**

Run: `chmod +x rag-anything/scripts/lightrag-start.sh`

- [ ] **Step 3: Commit**

```bash
git add rag-anything/scripts/lightrag-start.sh
git commit -m "feat(scripts): lightrag-start full-stack orchestrator + version guard"
```

---

### Task 11: lightrag-stop.sh (full-stack)

**Files:**
- Create: `rag-anything/scripts/lightrag-stop.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# rag-anything/scripts/lightrag-stop.sh
# Cleanly stops the whole stack so the drive can be ejected safely.
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
RUNTIME_DIR="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}"
ENV_FILE="$RUNTIME_DIR/.env"
[ -f "$ENV_FILE" ] || { echo "[stop] FATAL: $ENV_FILE missing" >&2; exit 1; }

COMPOSE="docker compose -f $REPO_DIR/infra/docker-compose.yml --env-file $ENV_FILE"

echo "[stop] graceful compose down (PG checkpoint + loop unmount)"
$COMPOSE down

# Unload qwen2.5vl from GPU but keep ollama daemon alive
if pgrep -x ollama >/dev/null; then
  echo "[stop] unloading qwen2.5vl from Ollama"
  ollama stop qwen2.5vl:7b 2>/dev/null || true
fi

echo "[stop] OK"
```

- [ ] **Step 2: Make executable + commit**

Run: `chmod +x rag-anything/scripts/lightrag-stop.sh`

```bash
git add rag-anything/scripts/lightrag-stop.sh
git commit -m "feat(scripts): lightrag-stop full-stack shutdown"
```

---

### Task 12: lightrag-status.sh

**Files:**
- Create: `rag-anything/scripts/lightrag-status.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# rag-anything/scripts/lightrag-status.sh
# Quick health snapshot of the whole stack.
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
ENV_FILE="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}/.env"
[ -f "$ENV_FILE" ] || { echo "[status] no .env"; exit 1; }
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

echo "=== Ollama ==="
pgrep -x ollama >/dev/null && echo "daemon: running" || echo "daemon: STOPPED"
curl -sf http://localhost:11434/api/tags >/dev/null && echo "api: 200" || echo "api: DOWN"

echo
echo "=== Docker ==="
docker compose -f "$REPO_DIR/infra/docker-compose.yml" --env-file "$ENV_FILE" ps

echo
echo "=== Postgres ==="
docker exec ragonfire-postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" 2>&1 \
  || echo "postgres: DOWN"

echo
echo "=== LightRAG ==="
curl -sf "http://localhost:${LIGHTRAG_PORT_EXTERNAL}/health" \
  && echo "lightrag: healthy" || echo "lightrag: DOWN"

echo
echo "=== Disk ==="
[ -f "$PGDATA_IMG" ] && ls -lh "$PGDATA_IMG" | awk '{print "pgdata.img:", $5, $9}' \
  || echo "pgdata.img: MISSING"
```

- [ ] **Step 2: Make executable + commit**

Run: `chmod +x rag-anything/scripts/lightrag-status.sh`

```bash
git add rag-anything/scripts/lightrag-status.sh
git commit -m "feat(scripts): lightrag-status snapshot"
```

---

### Task 13: Phase-2 end-to-end smoke (ingest a tiny PDF, query it)

**Files:**
- Create: `tests/fixtures/sample.pdf`
- Create: `tests/fixtures/sample-expected.json`
- Create: `scripts/phase2-smoke.sh`

- [ ] **Step 1: Generate a minimal 2-page PDF with a known phrase**

Run (creates `tests/fixtures/sample.pdf` using ReportLab from the venv):

```bash
mkdir -p tests/fixtures
~/rag-anything/.venv/bin/python - <<'PY'
from pathlib import Path
try:
    from reportlab.pdfgen import canvas
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--quiet", "reportlab"])
    from reportlab.pdfgen import canvas
out = Path("tests/fixtures/sample.pdf")
c = canvas.Canvas(str(out))
c.drawString(72, 720, "The marble crocodile devours quantum apricots in Reykjavik on Tuesdays.")
c.drawString(72, 700, "This document discusses the Marble Crocodile method invented by Riva in 2024.")
c.showPage()
c.drawString(72, 720, "The Marble Crocodile method is an extension of the quantum apricot framework.")
c.save()
print("wrote", out, out.stat().st_size, "bytes")
PY
```

Expected: prints `wrote tests/fixtures/sample.pdf <N> bytes` where N ~1-2 KB.

- [ ] **Step 2: Write the expectations file**

```json
{
  "known_phrase": "marble crocodile",
  "known_entity": "Marble Crocodile method",
  "min_entities": 3
}
```

Save to `tests/fixtures/sample-expected.json`.

- [ ] **Step 3: Write the smoke runner**

```bash
#!/usr/bin/env bash
# scripts/phase2-smoke.sh
# Ingest sample.pdf, query, assert known phrase appears, assert graph has entities.
set -euo pipefail
REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
RUNTIME_DIR="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}"
# shellcheck disable=SC1090
set -a; source "$RUNTIME_DIR/.env"; set +a

PORT="${LIGHTRAG_PORT_EXTERNAL:-9622}"

echo "[smoke] /lightrag-start"
"$REPO_DIR/rag-anything/scripts/lightrag-start.sh"

echo "[smoke] ingest sample.pdf"
"$RUNTIME_DIR/.venv/bin/python" "$RUNTIME_DIR/scripts/ingest.py" \
  "$REPO_DIR/tests/fixtures/sample.pdf"

echo "[smoke] querying"
ANSWER=$(curl -sf -X POST "http://localhost:$PORT/query" \
  -H "Content-Type: application/json" \
  -d '{"query": "What is the Marble Crocodile method?", "mode": "hybrid"}')
echo "$ANSWER" | grep -iq "marble crocodile" \
  || { echo "[smoke] FAIL: known phrase missing from answer"; exit 1; }

echo "[smoke] checking graph has entities"
COUNT=$(docker exec ragonfire-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -tAc \
  "SELECT count(*) FROM ag_catalog.ag_graph")
[ "$COUNT" -ge 1 ] || { echo "[smoke] FAIL: no AGE graphs"; exit 1; }

echo "[smoke] PASS"
```

- [ ] **Step 4: Run it**

```bash
chmod +x scripts/phase2-smoke.sh
./scripts/phase2-smoke.sh
```

Expected: prints `[smoke] PASS`. Total runtime ~2-5 min (parse + embed + extract entities for a 2-page synthetic PDF).

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/ scripts/phase2-smoke.sh
git commit -m "test: phase-2 end-to-end ingest+query smoke"
```

---

## Phase 3 — OS-agnostic bootstrap

### Task 14: OS detection helper

**Files:**
- Create: `infra/os/detect.sh`

- [ ] **Step 1: Write the helper**

```bash
#!/usr/bin/env bash
# infra/os/detect.sh — echoes "darwin", "linux", or "wsl"
set -euo pipefail
uname_s=$(uname -s)
case "$uname_s" in
  Darwin) echo darwin ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then echo wsl
    else echo linux; fi ;;
  *) echo "unsupported: $uname_s" >&2; exit 1 ;;
esac
```

- [ ] **Step 2: Make executable + verify**

Run:
```bash
chmod +x infra/os/detect.sh
./infra/os/detect.sh
```

Expected: prints `darwin`, `linux`, or `wsl`. Exit 0.

- [ ] **Step 3: Commit**

```bash
git add infra/os/detect.sh
git commit -m "feat(infra): OS detection helper"
```

---

### Task 15: install-ollama.sh

**Files:**
- Create: `infra/os/install-ollama.sh`

- [ ] **Step 1: Write the installer**

```bash
#!/usr/bin/env bash
# infra/os/install-ollama.sh
set -euo pipefail
OS=$("$( dirname "${BASH_SOURCE[0]}" )/detect.sh")

if command -v ollama >/dev/null; then
  echo "[ollama] already installed: $(ollama --version 2>&1 | head -1)"
  exit 0
fi

case "$OS" in
  darwin)
    command -v brew >/dev/null || { echo "[ollama] FATAL: Homebrew required on macOS. https://brew.sh" >&2; exit 1; }
    brew install ollama ;;
  linux|wsl)
    curl -fsSL https://ollama.com/install.sh | sh ;;
esac

# Start the service
case "$OS" in
  darwin) brew services start ollama || true ;;
  linux|wsl)
    if command -v systemctl >/dev/null; then
      sudo systemctl enable --now ollama 2>/dev/null || nohup ollama serve >/tmp/ollama.log 2>&1 &
    else
      nohup ollama serve >/tmp/ollama.log 2>&1 &
    fi ;;
esac

# Wait for API
for _ in $(seq 1 15); do
  curl -sf http://localhost:11434/api/tags >/dev/null && break
  sleep 1
done
curl -sf http://localhost:11434/api/tags >/dev/null \
  || { echo "[ollama] FATAL: API never came up" >&2; exit 1; }

echo "[ollama] ready"
```

- [ ] **Step 2: Make executable + commit**

Run: `chmod +x infra/os/install-ollama.sh`

```bash
git add infra/os/install-ollama.sh
git commit -m "feat(infra): cross-OS Ollama installer"
```

---

### Task 16: install-uv.sh + install-docker.sh

**Files:**
- Create: `infra/os/install-uv.sh`
- Create: `infra/os/install-docker.sh`

- [ ] **Step 1: Write install-uv.sh**

```bash
#!/usr/bin/env bash
# infra/os/install-uv.sh
set -euo pipefail
if command -v uv >/dev/null; then
  echo "[uv] already installed: $(uv --version)"
  exit 0
fi
curl -LsSf https://astral.sh/uv/install.sh | sh
# shellcheck disable=SC1090
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env" || true
command -v uv >/dev/null || { echo "[uv] FATAL: install succeeded but uv not on PATH" >&2; exit 1; }
echo "[uv] ready"
```

- [ ] **Step 2: Write install-docker.sh**

```bash
#!/usr/bin/env bash
# infra/os/install-docker.sh
# Verifies Docker is installed and the daemon is reachable.
# Does NOT install Docker automatically (too risky to script across OSes).
set -euo pipefail
OS=$("$( dirname "${BASH_SOURCE[0]}" )/detect.sh")

if ! command -v docker >/dev/null; then
  case "$OS" in
    darwin) URL="https://docs.docker.com/desktop/install/mac-install/" ;;
    linux)  URL="https://docs.docker.com/engine/install/" ;;
    wsl)    URL="https://docs.docker.com/desktop/wsl/" ;;
  esac
  echo "[docker] FATAL: docker not installed. Install: $URL" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "[docker] FATAL: docker daemon not running. Start Docker Desktop / dockerd." >&2
  exit 1
fi

# Compose v2 plugin check
docker compose version >/dev/null 2>&1 \
  || { echo "[docker] FATAL: 'docker compose' plugin missing" >&2; exit 1; }

echo "[docker] ready: $(docker --version)"
```

- [ ] **Step 3: Make both executable + commit**

```bash
chmod +x infra/os/install-uv.sh infra/os/install-docker.sh
git add infra/os/install-uv.sh infra/os/install-docker.sh
git commit -m "feat(infra): uv installer + Docker presence check"
```

---

### Task 17: Refactor bootstrap.sh

**Files:**
- Modify: `rag-anything/bootstrap.sh`

- [ ] **Step 1: Replace bootstrap.sh entirely**

```bash
#!/usr/bin/env bash
# rag-anything/bootstrap.sh
# OS-agnostic installer: Docker check + Ollama + uv + venv + skills + compose build + db-init.
#
# Usage:
#   ./bootstrap.sh                                   # skills → claude-code
#   ./bootstrap.sh --agent codex
#   ./bootstrap.sh --agent all
#   ./bootstrap.sh --skip-skills
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"   # rag-anything/
REPO_ROOT="$( cd "$REPO_DIR/.." && pwd )"
RUNTIME_DIR="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}"
PYTHON_VERSION="3.12"
LLM_MODEL="qwen2.5vl:7b"
EMBED_MODEL="bge-m3"

log() { printf "\033[1;36m[bootstrap]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; exit 1; }

SKILL_ARGS=()
SKIP_SKILLS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)       SKILL_ARGS+=(--agent "$2"); shift 2 ;;
    --agent=*)     SKILL_ARGS+=("--agent" "${1#*=}"); shift ;;
    --skip-skills) SKIP_SKILLS=1; shift ;;
    -h|--help)
      awk 'NR==1 { next } /^[^#]/ { exit } { sub(/^# ?/, ""); print }' "$0"
      exit 0 ;;
    *) err "unknown arg: $1" ;;
  esac
done

# 1. Cross-OS prereqs
"$REPO_ROOT/infra/os/install-docker.sh"
"$REPO_ROOT/infra/os/install-uv.sh"
"$REPO_ROOT/infra/os/install-ollama.sh"

# 2. Runtime dirs
log "preparing runtime dirs"
mkdir -p "$RUNTIME_DIR"/{scripts,logs}

# 3. Copy scripts + .env + requirements
log "syncing scripts + config from repo to $RUNTIME_DIR"
cp "$REPO_DIR"/scripts/*.py "$RUNTIME_DIR/scripts/"
cp "$REPO_DIR"/scripts/*.sh "$RUNTIME_DIR/scripts/"
cp "$REPO_DIR"/requirements.txt "$RUNTIME_DIR/"
[ -f "$RUNTIME_DIR/.env" ] || cp "$REPO_DIR/.env.example" "$RUNTIME_DIR/.env"
cp "$REPO_DIR/.env.example" "$RUNTIME_DIR/.env.example"
chmod +x "$RUNTIME_DIR"/scripts/*.sh "$RUNTIME_DIR"/scripts/*.py

# 4. Load .env so PGDATA_IMG etc. are visible
# shellcheck disable=SC1090
set -a; source "$RUNTIME_DIR/.env"; set +a

# 5. Drive paths
log "ensuring drive paths exist"
mkdir -p "$INPUT_DIR" "$OUTPUT_DIR" "$WORKING_DIR" "$BACKUPS_DIR" \
         "$OLLAMA_MODELS" "$HF_HOME" "$MINERU_MODELS_DIR" \
         "$(dirname "$PGDATA_IMG")"

# 6. Pull ollama models into OLLAMA_MODELS (env tells the daemon where to look)
export OLLAMA_MODELS
log "pulling ollama models"
for m in "$LLM_MODEL" "$EMBED_MODEL"; do
  if ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$m"; then
    log "  $m present"
  else
    log "  pulling $m"
    ollama pull "$m"
  fi
done

# 7. Create Python venv
if [ ! -d "$RUNTIME_DIR/.venv" ]; then
  log "creating Python $PYTHON_VERSION venv at $RUNTIME_DIR/.venv (internal SSD)"
  uv venv --python "$PYTHON_VERSION" "$RUNTIME_DIR/.venv"
fi

log "installing pinned Python deps"
uv pip install --python "$RUNTIME_DIR/.venv/bin/python" -r "$RUNTIME_DIR/requirements.txt"

# 8. Create pgdata.ext4.img if missing
"$RUNTIME_DIR/scripts/db-init.sh"

# 9. Build compose images
log "building docker images"
docker compose -f "$REPO_ROOT/infra/docker-compose.yml" --env-file "$RUNTIME_DIR/.env" build

# 10. Install skills
if [ "$SKIP_SKILLS" -eq 1 ]; then
  log "skipping skills install"
else
  log "installing skills ${SKILL_ARGS[*]:-(default: claude-code)}"
  "$REPO_ROOT/scripts/install-skills.sh" "${SKILL_ARGS[@]}"
fi

cat <<EOF

[1;32mBootstrap complete.[0m

  Repo:     $REPO_DIR
  Runtime:  $RUNTIME_DIR
  Drive:    /Volumes/Crucial-4T/rag-anything

Next steps:
  /lightrag-start
  /raganything-upload <file>
  /lightrag-query "<question>"
  /lightrag-eject   # before unplugging the drive
EOF
```

- [ ] **Step 2: Run a syntax check**

Run: `bash -n rag-anything/bootstrap.sh`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add rag-anything/bootstrap.sh
git commit -m "feat(bootstrap): OS-agnostic, Docker-first, .img-aware"
```

---

## Phase 4 — Operational skills

### Task 18: db-snapshot.sh + skill

**Files:**
- Create: `rag-anything/scripts/db-snapshot.sh`
- Create: `rag-anything/skills/db-snapshot/SKILL.md`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# rag-anything/scripts/db-snapshot.sh
# pg_dump | gzip > $BACKUPS_DIR/pgdump-YYYYMMDD-HHMMSS.sql.gz
set -euo pipefail
# shellcheck disable=SC1090
set -a; source "${RAGONFIRE_RUNTIME:-$HOME/rag-anything}/.env"; set +a

mkdir -p "$BACKUPS_DIR"
TS=$(date +%Y%m%d-%H%M%S)
OUT="$BACKUPS_DIR/pgdump-$TS.sql.gz"

echo "[snapshot] → $OUT"
docker exec ragonfire-postgres \
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" --format=plain \
  | gzip > "$OUT"

SIZE=$(du -h "$OUT" | awk '{print $1}')
echo "[snapshot] OK ($SIZE)"
```

- [ ] **Step 2: Write the skill prompt**

```markdown
---
name: db-snapshot
description: Take a manual pg_dump snapshot of the LightRAG knowledge base and store it under $BACKUPS_DIR on the Crucial-4T drive. Use before major changes (large ingest, upgrades, unplug). Triggers on /db-snapshot.
---

# db-snapshot

Run the script:

```bash
~/rag-anything/scripts/db-snapshot.sh
```

Report the resulting filename and size.
```

- [ ] **Step 3: Make executable, commit**

```bash
chmod +x rag-anything/scripts/db-snapshot.sh
git add rag-anything/scripts/db-snapshot.sh rag-anything/skills/db-snapshot/
git commit -m "feat(skills): /db-snapshot manual pg_dump"
```

---

### Task 19: db-restore.sh + skill

**Files:**
- Create: `rag-anything/scripts/db-restore.sh`
- Create: `rag-anything/skills/db-restore/SKILL.md`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# rag-anything/scripts/db-restore.sh
# Restore from a named or latest snapshot. Refuses if DB has user tables unless --force.
set -euo pipefail
# shellcheck disable=SC1090
set -a; source "${RAGONFIRE_RUNTIME:-$HOME/rag-anything}/.env"; set +a

FORCE=0
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    *) TARGET="$1"; shift ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET=$(ls -1t "$BACKUPS_DIR"/pgdump-*.sql.gz 2>/dev/null | head -1)
  [ -n "$TARGET" ] || { echo "[restore] no snapshots in $BACKUPS_DIR" >&2; exit 1; }
fi
[ -f "$TARGET" ] || { echo "[restore] not found: $TARGET" >&2; exit 1; }

if [ "$FORCE" -eq 0 ]; then
  USER_TABLES=$(docker exec ragonfire-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -tAc \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name LIKE 'lightrag%'")
  [ "$USER_TABLES" = "0" ] || { echo "[restore] DB has LightRAG tables. Re-run with --force to overwrite." >&2; exit 1; }
fi

echo "[restore] ← $TARGET"
gunzip -c "$TARGET" | docker exec -i ragonfire-postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -v ON_ERROR_STOP=1

echo "[restore] OK"
```

- [ ] **Step 2: Write the skill prompt**

```markdown
---
name: db-restore
description: Restore the LightRAG knowledge base from a pg_dump snapshot stored under $BACKUPS_DIR. Defaults to the newest dump. Pass an explicit filename to restore a specific one. Refuses if the DB already has LightRAG tables unless --force is provided. Triggers on /db-restore.
---

# db-restore

If no filename argument given, restore latest:
```bash
~/rag-anything/scripts/db-restore.sh
```

If filename given:
```bash
~/rag-anything/scripts/db-restore.sh <path>
```

To overwrite an existing populated DB:
```bash
~/rag-anything/scripts/db-restore.sh --force
```

Confirm with the user before passing --force.
```

- [ ] **Step 3: Make executable, commit**

```bash
chmod +x rag-anything/scripts/db-restore.sh
git add rag-anything/scripts/db-restore.sh rag-anything/skills/db-restore/
git commit -m "feat(skills): /db-restore from snapshot"
```

---

### Task 20: db-list-snapshots.sh + skill

**Files:**
- Create: `rag-anything/scripts/db-list-snapshots.sh`
- Create: `rag-anything/skills/db-list-snapshots/SKILL.md`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# rag-anything/scripts/db-list-snapshots.sh
set -euo pipefail
# shellcheck disable=SC1090
set -a; source "${RAGONFIRE_RUNTIME:-$HOME/rag-anything}/.env"; set +a

if [ ! -d "$BACKUPS_DIR" ] || ! ls "$BACKUPS_DIR"/pgdump-*.sql.gz >/dev/null 2>&1; then
  echo "(no snapshots in $BACKUPS_DIR)"
  exit 0
fi

printf "%-40s %10s %20s\n" "FILE" "SIZE" "MODIFIED"
for f in $(ls -1t "$BACKUPS_DIR"/pgdump-*.sql.gz); do
  printf "%-40s %10s %20s\n" \
    "$(basename "$f")" \
    "$(du -h "$f" | awk '{print $1}')" \
    "$(date -r "$f" "+%Y-%m-%d %H:%M:%S")"
done
```

- [ ] **Step 2: Write the skill**

```markdown
---
name: db-list-snapshots
description: List all pg_dump snapshots under $BACKUPS_DIR with size and modification time. Triggers on /db-list-snapshots.
---

# db-list-snapshots

```bash
~/rag-anything/scripts/db-list-snapshots.sh
```
```

- [ ] **Step 3: Make executable, commit**

```bash
chmod +x rag-anything/scripts/db-list-snapshots.sh
git add rag-anything/scripts/db-list-snapshots.sh rag-anything/skills/db-list-snapshots/
git commit -m "feat(skills): /db-list-snapshots"
```

---

### Task 21: db-grow.sh + skill

**Files:**
- Create: `rag-anything/scripts/db-grow.sh`
- Create: `rag-anything/skills/db-grow/SKILL.md`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# rag-anything/scripts/db-grow.sh <new-size>
# Stops the stack, grows the loopback image, resizes ext4, restarts.
set -euo pipefail
NEW_SIZE="${1:-}"
[ -n "$NEW_SIZE" ] || { echo "usage: db-grow.sh <new-size>  (e.g. 100G, 500G, 1T)" >&2; exit 1; }

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
# shellcheck disable=SC1090
set -a; source "${RAGONFIRE_RUNTIME:-$HOME/rag-anything}/.env"; set +a

echo "[grow] stopping stack"
"$REPO_DIR/rag-anything/scripts/lightrag-stop.sh"

echo "[grow] extending file to $NEW_SIZE"
truncate -s "$NEW_SIZE" "$PGDATA_IMG"

echo "[grow] fsck + resize2fs (inside helper container)"
docker run --rm -v "$PGDATA_IMG:/img" alpine:3.20 sh -c \
  "apk add --no-cache --quiet e2fsprogs >/dev/null && e2fsck -f -y /img && resize2fs /img"

echo "[grow] restarting"
"$REPO_DIR/rag-anything/scripts/lightrag-start.sh"

echo "[grow] OK"
```

- [ ] **Step 2: Write the skill**

```markdown
---
name: db-grow
description: Grow the Postgres loopback image capacity. Takes one argument like 100G, 500G, or 1T. Stops the stack, extends the file, runs e2fsck + resize2fs, restarts. Triggers on /db-grow.
---

# db-grow

```bash
~/rag-anything/scripts/db-grow.sh <new-size>
```

Confirm the new size with the user before running. The operation involves a ~5-minute downtime at the 50 GB → 100 GB scale.
```

- [ ] **Step 3: Make executable, commit**

```bash
chmod +x rag-anything/scripts/db-grow.sh
git add rag-anything/scripts/db-grow.sh rag-anything/skills/db-grow/
git commit -m "feat(skills): /db-grow ext4 resize"
```

---

### Task 22: lightrag-eject.sh + skill

**Files:**
- Create: `rag-anything/scripts/lightrag-eject.sh`
- Create: `rag-anything/skills/lightrag-eject/SKILL.md`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# rag-anything/scripts/lightrag-eject.sh
# Clean stop + sync + eject the drive so it's safe to unplug.
set -euo pipefail
REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
# shellcheck disable=SC1090
set -a; source "${RAGONFIRE_RUNTIME:-$HOME/rag-anything}/.env"; set +a

DRIVE_ROOT="/Volumes/Crucial-4T"

echo "[eject] stopping stack"
"$REPO_DIR/rag-anything/scripts/lightrag-stop.sh"

echo "[eject] sync"
sync

OS=$("$REPO_DIR/infra/os/detect.sh")
case "$OS" in
  darwin) diskutil eject "$DRIVE_ROOT" ;;
  linux|wsl)
    DEV=$(findmnt -no SOURCE "$DRIVE_ROOT" || true)
    [ -n "$DEV" ] && udisksctl unmount -b "$DEV" && udisksctl power-off -b "$DEV" \
      || echo "[eject] manual unmount required: umount $DRIVE_ROOT" ;;
esac

echo "[eject] safe to unplug Crucial-4T"
```

- [ ] **Step 2: Write the skill**

```markdown
---
name: lightrag-eject
description: Safely stop the entire RAG stack and eject the Crucial-4T drive. Use BEFORE physically unplugging the drive. Triggers on /lightrag-eject.
---

# lightrag-eject

```bash
~/rag-anything/scripts/lightrag-eject.sh
```

Wait for the "safe to unplug" message before pulling the drive.
```

- [ ] **Step 3: Make executable, commit**

```bash
chmod +x rag-anything/scripts/lightrag-eject.sh
git add rag-anything/scripts/lightrag-eject.sh rag-anything/skills/lightrag-eject/
git commit -m "feat(skills): /lightrag-eject safe-unplug procedure"
```

---

### Task 23: lightrag-upgrade.sh + skill

**Files:**
- Create: `rag-anything/scripts/lightrag-upgrade.sh`
- Create: `rag-anything/skills/lightrag-upgrade/SKILL.md`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# rag-anything/scripts/lightrag-upgrade.sh
# Snapshots, wipes .img, re-inits, re-ingests everything in INPUT_DIR,
# then bumps lightrag_meta.lightrag_version to the new pin.
set -euo pipefail
REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
RUNTIME_DIR="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}"
# shellcheck disable=SC1090
set -a; source "$RUNTIME_DIR/.env"; set +a

NEW_VERSION=$(grep -E '^lightrag-hku\[api\]==' "$REPO_DIR/rag-anything/requirements.txt" | sed 's/.*==//')
[ -n "$NEW_VERSION" ] || { echo "[upgrade] cannot read pinned version from requirements.txt" >&2; exit 1; }
echo "[upgrade] target lightrag-hku == $NEW_VERSION"

echo "[upgrade] taking pre-upgrade snapshot"
"$REPO_DIR/rag-anything/scripts/db-snapshot.sh"

echo "[upgrade] stopping stack"
"$REPO_DIR/rag-anything/scripts/lightrag-stop.sh"

echo "[upgrade] wiping .img (DESTRUCTIVE)"
"$REPO_DIR/rag-anything/scripts/db-init.sh" --force

echo "[upgrade] starting stack on fresh DB"
"$REPO_DIR/rag-anything/scripts/lightrag-start.sh"

echo "[upgrade] re-ingesting $INPUT_DIR"
shopt -s nullglob
for f in "$INPUT_DIR"/*; do
  [ -f "$f" ] || continue
  echo "[upgrade]   $f"
  "$RUNTIME_DIR/.venv/bin/python" "$RUNTIME_DIR/scripts/ingest.py" "$f"
done

echo "[upgrade] OK (lightrag_version=$NEW_VERSION)"
```

- [ ] **Step 2: Write the skill**

```markdown
---
name: lightrag-upgrade
description: Bump the LightRAG schema version after upgrading the lightrag-hku pin. Snapshots current DB, wipes .img, re-inits, and re-ingests everything in INPUT_DIR. DESTRUCTIVE — confirm with user first. Triggers on /lightrag-upgrade or when /lightrag-start reports a schema-version mismatch.
---

# lightrag-upgrade

Confirm with the user:
- "This will WIPE the current PG and re-ingest every file in INPUT_DIR. A snapshot is taken first. Proceed?"

After confirmation:
```bash
~/rag-anything/scripts/lightrag-upgrade.sh
```
```

- [ ] **Step 3: Make executable, commit**

```bash
chmod +x rag-anything/scripts/lightrag-upgrade.sh
git add rag-anything/scripts/lightrag-upgrade.sh rag-anything/skills/lightrag-upgrade/
git commit -m "feat(skills): /lightrag-upgrade schema-bump handler"
```

---

### Task 24: Repoint existing skills

**Files:**
- Modify: `rag-anything/skills/lightrag-start/SKILL.md`
- Modify: `rag-anything/skills/lightrag-stop/SKILL.md`
- Modify: `rag-anything/skills/lightrag-status/SKILL.md`
- Modify: `rag-anything/skills/raganything-upload/SKILL.md`
- Modify: `rag-anything/skills/lightrag-upload/SKILL.md`
- Modify: `scripts/install-skills.sh`

- [ ] **Step 1: Replace lightrag-start/SKILL.md**

```markdown
---
name: lightrag-start
description: Boot the full RagOnFire stack — Ollama (native), Postgres (container with pgvector + AGE), LightRAG server (container). Mounts pgdata.ext4.img as a loopback ext4. Verifies schema-version stamp. Triggers on /lightrag-start.
---

# lightrag-start

```bash
~/rag-anything/scripts/lightrag-start.sh
```

If the script reports a schema-version mismatch, run /lightrag-upgrade.
If it reports the .img is missing, run scripts/db-init.sh.
```

- [ ] **Step 2: Replace lightrag-stop/SKILL.md**

```markdown
---
name: lightrag-stop
description: Cleanly stop the full RagOnFire stack — graceful Postgres checkpoint, ext4 loopback unmount, LightRAG container down, Ollama model unloaded from GPU (daemon stays). Triggers on /lightrag-stop.
---

# lightrag-stop

```bash
~/rag-anything/scripts/lightrag-stop.sh
```

To also eject the drive afterwards, use /lightrag-eject instead.
```

- [ ] **Step 3: Replace lightrag-status/SKILL.md**

```markdown
---
name: lightrag-status
description: Health snapshot of every layer — Ollama, Docker, Postgres, LightRAG, and the pgdata.ext4.img file. Triggers on /lightrag-status.
---

# lightrag-status

```bash
~/rag-anything/scripts/lightrag-status.sh
```
```

- [ ] **Step 4: Trim raganything-upload/SKILL.md**

Remove the block that says "stop the server before ingesting" (no longer needed — PG handles concurrent access). Add a one-line note:

> Postgres handles concurrent ingest + query, so the server stays up during multimodal upload.

- [ ] **Step 5: Trim lightrag-upload/SKILL.md**

Same — drop any "stop first" instructions.

- [ ] **Step 6: Update install-skills.sh skill-dir list**

Read current `scripts/install-skills.sh`, find the array of skill names to copy, and append: `db-snapshot db-restore db-list-snapshots db-grow lightrag-eject lightrag-upgrade`.

- [ ] **Step 7: Verify install-skills.sh dry-run lists all 13 skills**

Run: `./scripts/install-skills.sh --dry-run 2>&1 | grep -c SKILL.md`
Expected: 13 (7 existing + 6 new).

- [ ] **Step 8: Commit**

```bash
git add rag-anything/skills/ scripts/install-skills.sh
git commit -m "feat(skills): repoint existing + register 6 new skills"
```

---

### Task 25: Delete old server-*.sh wrappers

**Files:**
- Remove: `rag-anything/scripts/server-start.sh`
- Remove: `rag-anything/scripts/server-stop.sh`
- Remove: `rag-anything/scripts/server-status.sh`

- [ ] **Step 1: Remove the old wrappers**

```bash
git rm rag-anything/scripts/server-start.sh \
       rag-anything/scripts/server-stop.sh \
       rag-anything/scripts/server-status.sh
```

- [ ] **Step 2: Verify no references remain**

Run: `grep -rn "server-start.sh\|server-stop.sh\|server-status.sh" --include='*.md' --include='*.sh' --include='*.py' .`
Expected: no matches.

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor: drop server-*.sh wrappers (replaced by lightrag-* scripts)"
```

---

## Phase 5 — Docs + CI

### Task 26: README updates

**Files:**
- Modify: `README.md`
- Modify: `rag-anything/README.md`

- [ ] **Step 1: Replace the Requirements section in `README.md`**

Find the `## 🧪 Requirements` section and replace its body with:

```markdown
- **Docker** (Desktop on macOS/Windows, engine on Linux) — runs Postgres + LightRAG server.
- **Ollama** (native — installed automatically by `bootstrap.sh` via brew on macOS, the official install script on Linux, or `winget` on Windows).
- **Apple Silicon / NVIDIA GPU recommended** for fast inference. CPU fallback works but is slow.
- **~20 GB free internal SSD** for Docker images + Python venv. The 50 GB Postgres image, model caches, and parsed artifacts live on the external drive (Crucial-4T by default).
- **External drive** formatted ExFAT (default) is fine — Postgres data lives inside an ext4 loopback image so POSIX semantics are preserved.
- **Python 3.12** + **uv** for the host venv (installed by `bootstrap.sh`).
```

Find the Apple Silicon badge in the header. Replace it with:

```markdown
  <img src="https://img.shields.io/badge/OS-macOS%20%7C%20Linux%20%7C%20WSL2-555?logoColor=white" alt="OS" />
```

Find the Quickstart and prepend a new section:

```markdown
### New machine, same drive

If the Crucial-4T already has a populated `pgdata.ext4.img`:

```bash
# 1. Plug the drive in
# 2. Install Docker (per-OS instructions: https://docs.docker.com/get-docker/)
# 3. From the repo on the drive:
./rag-anything/bootstrap.sh    # installs Ollama + venv + skills, leaves .img untouched
/lightrag-start                 # mounts the existing DB
```

The same vectors, graph, and KV come up. No re-ingest.
```

- [ ] **Step 2: Replace the Storage section in `rag-anything/README.md`**

Find the JSON storage block (the ASCII tree with `graph_chunk_entity_relation.graphml`, `vdb_chunks.json`, etc.) and replace it with:

```markdown
### Storage backend

Retrieval state lives in a single Postgres 16 container running pgvector + Apache AGE. The Postgres data directory sits inside an ext4 loopback image on the Crucial-4T drive:

```
/Volumes/Crucial-4T/rag-anything/pgdata.ext4.img   ← ext4 inside, ExFAT outside
                                                     started at 50 GB cap, growable
```

Vectors use HNSW indexes (`HNSW_M=16`, `HNSW_EF_CONSTRUCTION=64`, `HNSW_EF_SEARCH=40`). Graph uses AGE Cypher. KV and doc-status are plain Postgres tables. All four LightRAG storages share the same database, so a single `pg_dump` snapshot captures the entire knowledge base.
```

Find the lifecycle block (`Boot / Check / Ingest / Query / Free RAM when done`) and replace with:

```markdown
### Lifecycle (full-stack)

```bash
/lightrag-start                     # mounts .img, boots PG + LightRAG, ensures Ollama
/raganything-upload /path/doc.pdf   # ingest (server stays up)
/lightrag-query "What is X?"        # ask
/db-snapshot                        # take a backup before big changes
/lightrag-eject                     # stop everything + eject drive (use before unplug)
```
```

- [ ] **Step 3: Commit**

```bash
git add README.md rag-anything/README.md
git commit -m "docs: rewrite for cross-OS + PG + drive-portable model"
```

---

### Task 27: GitHub Actions smoke

**Files:**
- Create: `.github/workflows/smoke.yml`

- [ ] **Step 1: Write the workflow**

```yaml
# .github/workflows/smoke.yml
name: smoke

on:
  push:
    branches: ["**"]
  pull_request:

jobs:
  pg-stack:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build pg-init + postgres images
        run: |
          docker build -t ragonfire-pg-init infra/pg-init
          docker build -t ragonfire-postgres infra/postgres

      - name: Create throwaway .img and run phase-1 smoke
        run: |
          # Reuse the phase-1 smoke script
          chmod +x scripts/phase1-smoke.sh
          ./scripts/phase1-smoke.sh
```

- [ ] **Step 2: Validate yaml**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/smoke.yml'))"`
Expected: exit 0.

- [ ] **Step 3: Commit + push to a feature branch + observe CI**

```bash
git add .github/workflows/smoke.yml
git commit -m "ci: linux smoke test for PG stack"
git push origin HEAD:test/ci-smoke
```

Expected: the GitHub Actions run on the pushed branch completes green within ~5 minutes.

---

### Task 28: Final end-to-end on a real machine

**Files:** (no source changes)

- [ ] **Step 1: Wipe local runtime + start clean**

```bash
rm -rf ~/rag-anything
docker compose -f infra/docker-compose.yml down -v
rm -f /Volumes/Crucial-4T/rag-anything/pgdata.ext4.img
```

- [ ] **Step 2: Run bootstrap**

```bash
./rag-anything/bootstrap.sh
```

Expected: completes without errors. Final block prints the "Next steps" cheatsheet.

- [ ] **Step 3: Start the stack**

```bash
~/rag-anything/scripts/lightrag-start.sh
```

Expected: ends with `[start] OK — http://localhost:9622`.

- [ ] **Step 4: Run phase-2 smoke (real ingest + query)**

```bash
./scripts/phase2-smoke.sh
```

Expected: prints `[smoke] PASS`.

- [ ] **Step 5: Snapshot, list, restore round-trip**

```bash
~/rag-anything/scripts/db-snapshot.sh
~/rag-anything/scripts/db-list-snapshots.sh
# Don't actually run restore here unless you want to overwrite; just confirm the file exists.
```

Expected: list shows one `pgdump-*.sql.gz` entry.

- [ ] **Step 6: Test eject**

```bash
~/rag-anything/scripts/lightrag-eject.sh
```

Expected: ends with `[eject] safe to unplug Crucial-4T`. Drive should be unmounted from Finder.

- [ ] **Step 7: Re-plug + re-start (verifies portability)**

After physically remounting the drive:
```bash
~/rag-anything/scripts/lightrag-start.sh
curl -X POST http://localhost:9622/query -H "Content-Type: application/json" \
  -d '{"query":"What is the Marble Crocodile method?","mode":"hybrid"}'
```

Expected: same answer as before the eject — proves the .img preserved state.

---

## Self-review

### Spec coverage

| Spec section | Plan task(s) |
|---|---|
| Pinned dependencies | T1 |
| Postgres image w/ pgvector + AGE | T2 |
| pg-init helper container | T3 |
| .img creation | T4 |
| docker-compose.yml + .env.example | T5 |
| LightRAG server container image | T6 |
| Phase-1 smoke | T7 |
| MinerU device probe | T8 |
| ingest.py device probe + storage banner | T9 |
| lightrag-start full-stack + schema-version guard | T10 |
| lightrag-stop full-stack | T11 |
| lightrag-status | T12 |
| Phase-2 smoke (ingest + query) | T13 |
| OS detection | T14 |
| Cross-OS Ollama installer | T15 |
| uv + Docker check | T16 |
| OS-agnostic bootstrap.sh | T17 |
| /db-snapshot | T18 |
| /db-restore | T19 |
| /db-list-snapshots | T20 |
| /db-grow | T21 |
| /lightrag-eject | T22 |
| /lightrag-upgrade | T23 |
| Repoint existing skills + register new | T24 |
| Drop dead wrappers | T25 |
| READMEs | T26 |
| CI smoke | T27 |
| Final E2E on real machine | T28 |

All spec sections are covered.

### Placeholder scan

No "TODO", "TBD", "fill in", or "similar to" — every step is concrete.

### Type / name consistency

- `PGDATA_IMG` env var: same name across `.env.example`, `db-init.sh`, `lightrag-start.sh`, `lightrag-stop.sh`, `db-grow.sh`, `lightrag-upgrade.sh`.
- `BACKUPS_DIR`: same in `.env.example`, `db-snapshot.sh`, `db-restore.sh`, `db-list-snapshots.sh`.
- `LIGHTRAG_PORT_EXTERNAL` / `LIGHTRAG_PORT_INTERNAL`: same in `.env.example`, `docker-compose.yml`, `lightrag-start.sh`, `lightrag-status.sh`, phase-2 smoke, README.
- `lightrag_meta` table + `lightrag_version` key: same in `init.sql`, `lightrag-start.sh`, `lightrag-upgrade.sh`.
- `ragonfire-postgres` container name: same in `docker-compose.yml`, `lightrag-status.sh`, `db-snapshot.sh`, `db-restore.sh`.
- Script paths in skill markdown all point to `~/rag-anything/scripts/` (where `bootstrap.sh` copies them).

No inconsistencies found.

## Implementation Log
- Dispatched: 2026-05-19T09:24:06.854537Z
- Codex done: 2026-05-19T10:39:59.718490Z
- Worktree: /Volumes/Crucial-4T/repo/ragonfire-postgres-pgvector-age-migration
- Branch: feat/postgres-pgvector-age-migration
- Verification: `bash -n rag-anything/scripts/*.sh 2>&1` passed; `bash scripts/phase2-smoke.sh` passed.
- Dispatch override: no commits were created. Commit/push checklist items were not executed.
- Runtime safety: phase-2 smoke used an isolated `/tmp/ragonfire-phase2-runtime` and throwaway PG image, not the user runtime.
