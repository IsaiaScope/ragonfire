---
name: lightrag-stop
description: Stop the local LightRAG server to free RAM and release the storage lock. Use this skill when the user wants to shut down LightRAG, free memory, kill the rag server, or before running heavy ingest jobs that need exclusive storage access. Triggers on phrases like "stop lightrag", "shut down the knowledge base", "kill the rag server", "free up memory", or "/lightrag-stop". Auto-called by /raganything-upload to release the storage lock before multimodal ingest.
---

# LightRAG Stop

Stop the local LightRAG server gracefully. Ollama keeps running (low overhead, unloads models after idle timeout).

## Configuration

- **Stop script:** `~/rag-anything/scripts/server-stop.sh`
- **PID file:** `~/rag-anything/logs/server.pid`

## Usage

```bash
~/rag-anything/scripts/server-stop.sh
```

The script:
1. Reads `logs/server.pid`
2. Sends SIGTERM, waits 1s, then SIGKILL if still alive
3. Removes the PID file
4. Falls back to `pkill -f lightrag-server` if no PID file

## Verify it's down

```bash
curl -sf http://localhost:9621/health 2>/dev/null && echo "STILL UP" || echo "DOWN"
```

## When to use

- Before ingesting many files via `/raganything-upload` (releases storage lock, prevents corruption)
- When you're done with the knowledge base and want to free ~3-5 GB of RAM
- Before rebooting / shutting down the Mac
- If the server is stuck and `/lightrag-status` reports unhealthy

## Confirm to the user

> LightRAG server stopped. Ollama still running (unloads models after 5 min idle). Run /lightrag-start to bring the server back up.
