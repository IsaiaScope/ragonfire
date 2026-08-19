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
