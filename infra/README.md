<h3 align="center">Infra — Containers & Host Bootstrap 🐳</h3>

<p align="center">
  <em>The Docker layer: Postgres (pgvector + AGE) and the LightRAG server, plus the OS-detection and install scripts that wire up the host.</em>
</p>

<br />

<p align="center">
  <img src="https://img.shields.io/badge/Docker-Compose%20v2-2496ED?logo=docker&logoColor=white" alt="Docker Compose" />
  <img src="https://img.shields.io/badge/Postgres-16-4169E1?logo=postgresql&logoColor=white" alt="Postgres" />
  <img src="https://img.shields.io/badge/pgvector-HNSW-336791?logoColor=white" alt="pgvector" />
  <img src="https://img.shields.io/badge/Apache_AGE-Cypher-336791?logoColor=white" alt="Apache AGE" />
  <img src="https://img.shields.io/badge/ext4-loopback-FCC624?logo=linux&logoColor=black" alt="ext4 loopback" />
</p>

---

## 🐳 Role In RagOnFire

This folder is the **container layer**. Postgres and the LightRAG server run in Docker for portability; Ollama and MinerU stay native on the host for GPU access.

| | Piece | Role |
|-|-------|------|
| 🐘 | **postgres/** | Postgres 16 image with pgvector + Apache AGE, plus the loopback-mount entrypoint and init SQL |
| 🔗 | **lightrag-server/** | LightRAG REST server image (`lightrag-hku[api]`) talking to Postgres + Ollama |
| 💻 | **os/** | Host bootstrap — OS detection and idempotent installers for Docker, Ollama, `uv` |
| 🧩 | **docker-compose.yml** | Wires the two services on one internal bridge network |

```
                docker-compose.yml
                       │
        ┌──────────────┴──────────────┐
        ▼                             ▼
  ragonfire-postgres            ragonfire-lightrag
  pg16 + pgvector + AGE         lightrag-hku[api]
        │                             │
  loop-mounts ext4 .img          talks to Ollama
  (host drive)                   (host.docker.internal)
```

---

## 🧩 docker-compose.yml

Two services on one private bridge (`internal`). Both ports bind to `127.0.0.1` only — nothing is exposed to the LAN.

| | Service | Container | Host port | Notes |
|-|---------|-----------|-----------|-------|
| 🐘 | `postgres` | `ragonfire-postgres` | `${POSTGRES_PORT_EXTERNAL}` → 5432 | `privileged: true` for the loop mount |
| 🔗 | `lightrag-server` | `ragonfire-lightrag` | `${LIGHTRAG_PORT_EXTERNAL}` → `${LIGHTRAG_PORT_INTERNAL}` | waits for Postgres `service_healthy` |

The server reaches Ollama on the host via `host.docker.internal:host-gateway`. The Postgres data image is bind-mounted in from `${PGDATA_IMG}`; logs bind to `${HOST_LOGS_DIR}`.

---

## 🐘 postgres/

The one image that holds the whole knowledge base — vectors, graph, and KV in a single Postgres.

| | File | What |
|-|------|------|
| 📦 | `Dockerfile` | `pgvector/pgvector:pg16` base; builds **Apache AGE** from source (pinned by git SHA `AGE_REF`); adds `util-linux` + `e2fsprogs` for the loop mount |
| 🔁 | `entrypoint-loop.sh` | `mount -o loop` the ext4 `.img` onto `/pgdata-vol`, then hands off to the official `docker-entrypoint.sh` |
| 🌱 | `init.sql` | `CREATE EXTENSION vector` + `age`; creates `lightrag_meta` (schema-version stamp) |

```
${PGDATA_IMG}  (host)
   └─ loop-mounted → /pgdata-vol (ext4 inside container)
        └─ /pgdata-vol/pg  ← PGDATA lives here
```

> ⚠️ AGE has no released package for pg16 — it's compiled from a pinned commit at build time. Bump `AGE_REF` to move it.

---

## 🔗 lightrag-server/

| | File | What |
|-|------|------|
| 🐍 | `Dockerfile` | `python:3.12-slim`; pins `lightrag-hku[api]`, `asyncpg`, `psycopg`, `pgvector`, `ollama`, `python-dotenv` |

Reads config from `${LIGHTRAG_ENV_FILE}` (the runtime `.env`), exposes the REST API on `${LIGHTRAG_PORT_INTERNAL}` (9621), health-checked at `/health`.

---

## 💻 os/

Host-side bootstrap, called by `rag-anything/bootstrap.sh`. Every installer is idempotent and OS-aware.

| | Script | What |
|-|--------|------|
| 🧭 | `detect.sh` | Echoes `darwin` / `linux` / `wsl` / `windows` (override with `RF_OS_OVERRIDE`) |
| 🐳 | `install-docker.sh` | Installs Docker for the detected OS |
| 🦙 | `install-ollama.sh` | Installs the Ollama runtime |
| ⚡ | `install-uv.sh` | Installs `uv` (Python venv + deps) |

---

## 🔧 Build & Run

```bash
# Build both images (run from repo root or via the lifecycle skills)
docker compose -f infra/docker-compose.yml --env-file rag-anything/.env build

# Normal lifecycle goes through the skills, which call db-init then compose up:
/lightrag-start      # mounts .img, boots Postgres + LightRAG
/lightrag-eject      # stops everything + ejects the drive
```

> 🐘 `db-init.sh` must create `${PGDATA_IMG}` before first `up` — the entrypoint refuses to boot without it.

---

## 🔗 Links

| Resource | Link |
|----------|------|
| pgvector | [pgvector/pgvector](https://github.com/pgvector/pgvector) |
| Apache AGE | [apache/age](https://github.com/apache/age) |
| LightRAG | [HKUDS/LightRAG](https://github.com/HKUDS/LightRAG) |
| Postgres 16 | [postgresql.org/docs/16](https://www.postgresql.org/docs/16/) |

---

<p align="center">
  Two containers, one portable database. The rest stays native. 🔥
</p>
