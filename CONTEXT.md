# RagOnFire Context

## Terms

### RagOnFire Runtime

The installed local runtime under `~/rag-anything` or `$RAGONFIRE_RUNTIME`.
It contains the Python virtual environment, copied lifecycle scripts, pinned
requirements, and `.env` used by the agent skills.

### Data Root

The persistent directory under the repository root, normally `data/`. It holds
the portable Postgres image, parser output, ingest input, working files, logs,
snapshots, and model caches that are safe to keep on the external drive.

### Portable Postgres Image

The `pgdata.ext4.img` loopback file that contains the live Postgres data
directory on an ext4 filesystem. The host drive may be ExFAT, but Postgres sees
POSIX filesystem semantics inside the image.

### LightRAG Server

The Dockerized HTTP server that exposes LightRAG query and health endpoints. It
uses Postgres-backed LightRAG storages and talks to host-native Ollama through
`host.docker.internal`.

### Host-Native Ollama

The Ollama daemon running directly on the host OS instead of inside Docker. It
keeps GPU access and model storage behavior aligned with the host platform.

### Host-Native MinerU

The MinerU parser running in the host Python runtime instead of inside Docker.
It uses local accelerator support for layout, OCR, table, and equation parsing.

### Multimodal Ingest

The process that parses an input document, extracts text and multimodal items,
calls local models for extraction/captioning/embeddings, and stores the result
in LightRAG's Postgres-backed knowledge base.

### Parser Routing

The decision that maps a document to `pymupdf`, `mineru`, or `hybrid`. Digital
text PDFs without meaningful figures use the fast PyMuPDF path. Scanned PDFs use
MinerU OCR. Digital PDFs with meaningful raster coverage use the hybrid path.

### Snapshot

A gzip-compressed `pg_dump` of the LightRAG Postgres database. Snapshots are
stored under the backups directory and are the rollback point before destructive
operations.

### Upgrade

The workflow that snapshots the current database, recreates the portable
Postgres image, starts the stack on the new schema, and re-ingests the input
drop-zone.
