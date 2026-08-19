---
name: lightrag-stop
description: Cleanly stop the full RagOnFire stack - graceful Postgres checkpoint, ext4 loopback unmount, LightRAG container down, Ollama model unloaded from GPU (daemon stays). Triggers on /lightrag-stop.
---

# lightrag-stop

```bash
~/rag-anything/scripts/lightrag-stop.sh
```

To also eject the drive afterwards, use /lightrag-eject instead.
