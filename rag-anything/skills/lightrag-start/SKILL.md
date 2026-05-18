---
name: lightrag-start
description: Start the local LightRAG server on http://localhost:9621. Use this skill when the user wants to bring up their knowledge base server, start LightRAG, boot the RAG service, or before running any other LightRAG/RAG-Anything operation that fails because the server is down. Triggers on phrases like "start lightrag", "boot the knowledge base", "lightrag up", "start the rag server", or "/lightrag-start". Also run this as a prerequisite when /lightrag-upload, /lightrag-query, /lightrag-status, or /lightrag-explore reports the server is unreachable.
---

# LightRAG Start

Start the local LightRAG server (FastAPI) on `http://localhost:9621`. Server runs on-demand, not as a daemon, so it only consumes RAM when needed.

## Configuration

- **Project dir:** `/Users/isaia/rag-anything` (code), `/Volumes/Crucial-4T/rag-anything` (data)
- **Start script:** `/Users/isaia/rag-anything/scripts/server-start.sh`
- **Logs:** `/Users/isaia/rag-anything/logs/server.log`
- **PID file:** `/Users/isaia/rag-anything/logs/server.pid`
- **Backend:** Ollama (`qwen2.5vl:7b` + `bge-m3`) — script auto-starts ollama if down

## Usage

Run the start script:

```bash
/Users/isaia/rag-anything/scripts/server-start.sh
```

The script:
1. Checks PID file — if already running, no-op
2. Starts Ollama if not running
3. Loads `.env` into env vars
4. Launches `lightrag-server` via `nohup`, writes PID to `logs/server.pid`
5. Polls `http://localhost:9621/health` for up to 30s

## Verify it came up

```bash
curl -sf http://localhost:9621/health && echo "OK"
```

## On failure

Show the user the tail of the log:

```bash
tail -30 /Users/isaia/rag-anything/logs/server.log
```

Common failures:
- **`Address already in use`** — server already running from another shell. Run `/lightrag-stop` first.
- **`No module named 'lightrag'`** — venv not installed. Run `/Users/isaia/rag-anything/bootstrap.sh`.
- **Ollama unreachable** — `brew services start ollama` then retry.
- **Crucial-4T not mounted** — server can't write to storage. Plug in the drive.

## Confirm to the user

> LightRAG server running on http://localhost:9621 (pid X). Models: qwen2.5vl:7b + bge-m3 via Ollama. Storage: /Volumes/Crucial-4T/rag-anything/storage.
