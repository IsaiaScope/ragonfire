# ADR 0005: Isolate RAG-Anything Private Calls Behind One Adapter

## Status

Accepted

## Context

RagOnFire needs custom PyMuPDF and hybrid ingest paths. RAG-Anything exposes the
standard complete document flow publicly, but the custom paths need behavior that
currently lives behind private methods.

## Decision

Keep all private RAG-Anything method calls inside one local adapter module. The
rest of the ingest flow must call the adapter instead of private upstream
methods directly.

## Consequences

If RAG-Anything changes private names or behavior, breakage is localized to one
module and one compatibility test. The adapter is the seam for upstream drift.
