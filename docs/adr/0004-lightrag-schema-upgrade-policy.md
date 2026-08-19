# ADR 0004: Upgrade LightRAG by Snapshot and Re-Ingest

## Status

Accepted

## Context

LightRAG's Postgres schema can change across pinned versions. The project needs
a predictable local upgrade path that protects the previous knowledge base
before moving to a new schema.

## Decision

Before a LightRAG version change, create a database snapshot, recreate the
portable Postgres image, start the stack on the new version, and re-ingest files
from the input drop-zone.

## Consequences

The upgrade path is simple and robust for local use. It depends on the input
drop-zone being the reproducible source of truth for re-ingest, and destructive
operations must verify that a usable snapshot exists before wiping data.
