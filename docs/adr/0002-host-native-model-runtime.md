# ADR 0002: Run Ollama and MinerU Host-Native

## Status

Accepted

## Context

Ollama and MinerU both benefit from host accelerator access and host-specific
model cache behavior. Containerizing them would simplify process management, but
would make GPU access and model storage less predictable across macOS, Linux,
Windows native, and WSL2.

## Decision

Run Ollama and MinerU on the host. Docker runs only Postgres and the LightRAG
server.

## Consequences

The stack keeps fast local inference and parser acceleration. The lifecycle
scripts must manage host daemons and container services together, and the
containerized LightRAG server must reach Ollama through `host.docker.internal`.
