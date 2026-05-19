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
