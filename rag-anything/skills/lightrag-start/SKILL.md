---
name: lightrag-start
description: Boot the full RagOnFire stack - Ollama (native), Postgres (container with pgvector + AGE), LightRAG server (container). Mounts pgdata.ext4.img as a loopback ext4. Verifies schema-version stamp. Triggers on /lightrag-start.
---

# lightrag-start

```bash
~/rag-anything/scripts/lightrag-start.sh
```

If the script reports a schema-version mismatch, run /lightrag-upgrade.
If it reports the .img is missing, run `~/rag-anything/scripts/db-init.sh`.
