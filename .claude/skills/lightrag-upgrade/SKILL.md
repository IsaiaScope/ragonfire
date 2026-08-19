---
name: lightrag-upgrade
description: Bump the LightRAG schema version after upgrading the lightrag-hku pin. Snapshots current DB, wipes .img, re-inits, and re-ingests everything in INPUT_DIR. DESTRUCTIVE - confirm with user first. Triggers on /lightrag-upgrade or when /lightrag-start reports a schema-version mismatch.
---

# lightrag-upgrade

Confirm with the user:
- "This will WIPE the current PG and re-ingest every file in INPUT_DIR. A snapshot is taken first. Proceed?"

After confirmation:
```bash
~/rag-anything/scripts/lightrag-upgrade.sh
```
