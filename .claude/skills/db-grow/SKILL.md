---
name: db-grow
description: Grow the Postgres loopback image capacity. Takes one argument like 100G, 500G, or 1T. Stops the stack, extends the file, runs e2fsck + resize2fs, restarts. Triggers on /db-grow.
---

# db-grow

```bash
~/rag-anything/scripts/db-grow.sh <new-size>
```

Confirm the new size with the user before running. The operation involves a ~5-minute downtime at the 50 GB -> 100 GB scale.
