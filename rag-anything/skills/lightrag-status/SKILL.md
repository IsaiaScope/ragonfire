---
name: lightrag-status
description: Check the health of the local LightRAG knowledge base — server up/down, documents indexed, processing status, top entities. Use this skill when the user wants to know the state of their knowledge base, check if documents are still processing, see what's been indexed, or get a quick health check. Triggers on phrases like "lightrag status", "what's in my knowledge base", "is lightrag still processing", "how many documents are indexed", "kb health", or "/lightrag-status".
---

# LightRAG Status

Get a consolidated status report — server, documents, pipeline, top entities.

## Configuration

- **Server:** `http://localhost:9621`

## Step 1 — Is the server up?

```bash
curl -sf http://localhost:9621/health 2>/dev/null && echo UP || echo DOWN
```

If DOWN, report:
> LightRAG server is not running at localhost:9621. Run `/lightrag-start` to bring it up.

Stop here.

## Step 2 — Pipeline status (anything processing now?)

```bash
curl -s http://localhost:9621/documents/pipeline_status
```

Key fields:
- `busy` — `true` if processing
- `latest_message` — current step
- `docs` — documents in current batch

## Step 3 — All documents (grouped by status)

```bash
curl -s http://localhost:9621/documents
```

Counts: `PENDING`, `PROCESSING`, `PROCESSED`, `FAILED`.

## Step 4 — Top entities (most connected = graph hubs)

```bash
curl -s "http://localhost:9621/graph/label/popular?limit=15"
```

## Format the output

```
LightRAG Knowledge Base Status
==============================
Server: http://localhost:9621 — Online
Storage: ~/rag-anything/storage
Backend: ollama qwen2.5vl:7b + bge-m3
Processing: Idle  (or "Processing 3 documents — extracting entities...")

Documents:
  Processed: 10
  Pending:   0
  Failed:    0

Top Entities (most connected):
  1. Anthropic (hub)
  2. Claude Code (hub)
  3. MinerU (hub)
  ...
```

## Error Handling

- **Server unreachable** → tell user to run `/lightrag-start`
- **No documents** → "Knowledge base is empty. Upload with /lightrag-upload (text) or /raganything-upload (multimodal)"
