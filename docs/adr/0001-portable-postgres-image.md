# ADR 0001: Store Postgres Data in an Ext4 Loopback Image

## Status

Accepted

## Context

RagOnFire is designed to move with an external drive across macOS, Linux,
Windows native, and WSL2. The drive can be ExFAT for portability, but Postgres
requires filesystem semantics that ExFAT does not provide reliably for a live
data directory.

## Decision

Store the live Postgres data directory inside `pgdata.ext4.img`, mount that
image as ext4 from the Postgres container, and bind the image file from the host
data root.

## Consequences

The knowledge base can move with the drive without re-ingest, while Postgres
still writes to ext4. The Postgres container needs elevated privileges for the
loop mount. Operational scripts must initialize, grow, stop, and eject the image
carefully.
